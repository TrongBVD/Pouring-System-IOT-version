#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <string.h>
#include <Q2HX711.h>
#include <math.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>

/* =========================================================
   ===================== DEVICE / API ======================
   ========================================================= */

static const int DEVICE_ID  = 1;
static const int USER_ID    = 1;   // default = anonymous/local button
static const int PROFILE_ID = 1;
static const int CALIB_ID   = 1;

static const char* BACKEND_URL = "http://192.168.4.2:8080/PouringSystem/api/pour-session/batch";
static const char* HEALTH_URL  = "http://192.168.4.2:8080/PouringSystem/api/health";
static const char* API_KEY     = "ESP32_SECRET_2026";

WebServer server(80);

/* --- BIẾN LƯU TRẠNG THÁI THIẾT BỊ TỪ WEB ĐẨY XUỐNG --- */
String deviceStatus = "ACTIVE"; // ACTIVE, ERROR, OFFLINE

/* =========================================================
   ============ REMOTE COMPONENT STATUS (YES/NO) ===========
   ========================================================= */

static bool remoteHcSr04Ok   = true;
static bool remoteLoadcellOk = true;
static uint32_t lastRemoteStatusMs = 0;

/* =========================================================
   =================== OFFLINE QUEUE (3) ===================
   ========================================================= */

static const int MAX_OFFLINE_SESSIONS = 3;
String offlineQueue[MAX_OFFLINE_SESSIONS];
uint8_t offlineRetryCount[MAX_OFFLINE_SESSIONS] = {0, 0, 0};
int queueHead = 0;
int queueTail = 0;
int queueCount = 0;

static const uint8_t MAX_UPLOAD_RETRIES_PER_ITEM = 3;
bool uploadInProgress = false;

/* =========================================================
   ========================= PINS ==========================
   ========================================================= */

static const int TRIG_PIN   = 18;
static const int ECHO_PIN   = 19;
static const int RELAY_PIN  = 27;
static const int BUTTON_PIN = 33;

static const int HX_DOUT  = 26;
static const int HX_SCK   = 25;
static const int FLOW_PIN = 14;

static const bool RELAY_ACTIVE_LOW = false;

/* =========================================================
   ===================== BUTTON CONFIG =====================
   ========================================================= */

static const bool BUTTON_ACTIVE_LOW = true;
static const bool BUTTON_USE_INTERNAL_PULLUP = true;
static const uint32_t BUTTON_DEBOUNCE_MS = 40;

/* =========================================================
   ======================= WIFI AP =========================
   ========================================================= */

const char* WIFI_NAME = "MayRotNuoc";
const char* WIFI_PASS = "12345678";
static const uint32_t WIFI_WINDOW_MS = 10000;

bool wifiApRunning = false;
uint32_t wifiWindowStartMs = 0;

bool lastClientConnected = false;
uint32_t clientConnectedSinceMs = 0;
static const uint32_t QUEUE_FLUSH_DELAY_MS = 4000;

/* =========================================================
   ========================= LCD ===========================
   ========================================================= */

static const uint8_t LCD_ADDR = 0x27;
LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);

static const uint32_t LCD_PING_PERIOD_MS    = 1000;
static const int      LCD_FAILS_TO_RESET    = 3;
static const uint32_t LCD_RESET_COOLDOWN_MS = 3000;
static const uint32_t I2C_CLOCK_HZ          = 50000;

uint32_t lastLcdPingMs   = 0;
uint32_t lastLcdResetMs  = 0;
uint32_t lastLcdUpdateMs = 0;
int lcdFailCount = 0;

char lcdLastLine1[17] = "";
char lcdLastLine2[17] = "";

/* =========================================================
   ===================== HX711 / LOADCELL ==================
   ========================================================= */

Q2HX711 hx(HX_DOUT, HX_SCK);

long hx_offset = 0;
static const float CAL_FACTOR = 180.0f;
static const uint8_t HX711_TARE_SAMPLES = 20;
static const float LOADCELL_OFFSET_G = 0.0f;

static const uint32_t WEIGHT_PERIOD_IDLE_MS = 180;
uint32_t lastWeightMs = 0;

float weightG = 0.0f;
float weightGFiltered = 0.0f;
static const float WEIGHT_ALPHA_IDLE = 0.20f;

static const float MAX_VALID_WEIGHT_G = 3000.0f;
static const float MIN_VALID_WEIGHT_G = -50.0f;
static const float MAX_STEP_CHANGE_IDLE_G = 260.0f;

float lastAcceptedWeightG = 0.0f;
bool hasAcceptedWeight = false;
bool newWeightSample = false;

/* patch: xác nhận bước nhảy lớn để tránh kẹt giá trị cũ */
float pendingLargeStepWeightG = 0.0f;
uint8_t pendingLargeStepCount = 0;
static const float LARGE_STEP_CONFIRM_BAND_G = 30.0f;
static const uint8_t LARGE_STEP_CONFIRM_SAMPLES = 2;

bool cupPresentByWeight = false;
static const float CUP_DETECT_G = 20.0f;
static const float CUP_REMOVE_G = 2.0f;

/* =========================================================
   ======================= HC-SR04 =========================
   ========================================================= */

static const float START_RANGE_MIN_CM = 5.0f;
static const float START_RANGE_MAX_CM = 10.0f;

static const float MIN_VALID_CM = 4.0f;
static const float MAX_VALID_CM = 120.0f;
static const float HC_SR04_OFFSET_CM = 0.0f;

static const uint32_t ULTRA_PERIOD_MS = 120;
uint32_t lastUltraMs = 0;

float lastDistanceCm = -1.0f;
bool lastValid = false;

static const uint32_t DIST_HOLD_MS = 400;
uint32_t lastValidDistanceMs = 0;

/* =========================================================
   ===================== FLOW SENSOR =======================
   ========================================================= */

static const float FLOW_PULSES_PER_LITER = 450.0f;
static const uint32_t FLOW_ISR_DEBOUNCE_US = 40000UL;
static const uint32_t FLOW_MIN_VALID_WINDOW_MS = 250;
volatile uint32_t flowPulseCounter = 0;

/* =========================================================
   ===================== TARGET / PUMP =====================
   ========================================================= */

static const float TARGET_FINAL_WEIGHT_G = 550.0f;
static const float TARGET_MARGIN_G = 4.0f;
static const float TOPUP_THRESHOLD_G = 30.0f;

static const float PUMP_RATE_G_PER_SEC = 12.0f;

static const uint32_t SETTLE_AFTER_PUMP_MS = 450;
static const uint32_t MAX_SINGLE_PUMP_MS   = 30000;
static const uint32_t TOPUP_PUMP_MS        = 300;
static const uint8_t  MAX_TOPUP_CYCLES     = 15;

static const float MIN_GAIN_PER_TOPUP_G = 1.0f;
float lastSettleWeightG = 0.0f;

bool pumpIsOn = false;

/* ===== anti-noise khi pump ===== */
static const uint32_t WEIGHT_PERIOD_PUMP_MS = 70;
static const float WEIGHT_ALPHA_PUMP = 0.35f;
static const float CUP_REMOVE_G_PUMP = 5.0f;

static const uint32_t ULTRA_PERIOD_PUMP_MS = 70;
static const uint32_t DIST_HOLD_PUMP_MS = 120;
static const float ULTRA_REMOVE_MAX_CM = START_RANGE_MAX_CM + 3.0f;
static const float ULTRA_REMOVE_MIN_CM = START_RANGE_MIN_CM - 2.0f;

static const uint8_t LOADCELL_REMOVE_CONFIRM_PUMP = 2;
static const uint8_t ULTRA_REMOVE_CONFIRM_PUMP = 2;
static const uint8_t SINGLE_SENSOR_HARD_CONFIRM = 4;

static const uint32_t PUMP_SENSOR_ARM_MS = 180;
static const uint32_t PUMP_WEIGHT_STOP_ARM_MS = 350;

/* confidence counter khi đang pump */
uint8_t pumpLoadcellLowCount = 0;
uint8_t pumpUltraLostCount = 0;
uint32_t pumpStateChangedMs = 0;

/* giữ lại trọng lượng cuối còn hợp lệ */
float lastCupWeightBeforeRemovalG = 0.0f;
bool forcedStopByCupRemoval = false;
float forcedFinalWeightG = 0.0f;

/* =========================================================
   ===================== WAIT / DONE =======================
   ========================================================= */

static const uint32_t PRE_POUR_DELAY_MS = 3000;
static const uint32_t DONE_SCREEN_MS    = 5000;

/* =========================================================
   ===================== STATE MACHINE =====================
   ========================================================= */

#define ST_IDLE      0
#define ST_WAIT_3S   1
#define ST_PUMPING   2
#define ST_SETTLING  3
#define ST_DONE      4

uint8_t state = ST_IDLE;
uint32_t stateSinceMs = 0;
uint32_t doneShowSinceMs = 0;

bool pouring = false;
bool userStopRequested = false;

/* start stability */
uint32_t stableStartSinceMs = 0;
static const uint32_t START_STABLE_MS = 700;

/* re-arm */
bool cycleRearmNeeded = false;
uint32_t outOfStartWindowSinceMs = 0;
static const uint32_t REARM_OUT_OF_RANGE_MS = 500;

/* measure / result */
float startWeightAvgG = 0.0f;
float currentMeasuredWeightG = 0.0f;
float targetWeightG = 0.0f;
float pouredWeightG = 0.0f;
float remainingWeightG = 0.0f;
float realtimeRemainingWeightG = 0.0f;
float realtimePouredWeightG = 0.0f;
float targetPourMlForPayload = 0.0f;

float waitWeightSum = 0.0f;
uint16_t waitWeightCount = 0;

uint32_t plannedPumpMs = 0;
uint8_t topupCount = 0;

/* button debounce */
bool buttonLastRawPressed = false;
bool buttonStablePressed = false;
uint32_t buttonLastChangeMs = 0;

/* =========================================================
   ===================== TELEMETRY BUFFER ==================
   ========================================================= */

// 1 = ULTRASONIC, 2 = FLOW, 3 = LOADCELL
static const int SENSOR_ULTRASONIC = 1;
static const int SENSOR_FLOW       = 2;
static const int SENSOR_LOADCELL   = 3;

struct TelemetryRow {
  int sensorTypeId;
  float value;
  uint32_t tOffsetMs;
};

static const size_t MAX_TELEMETRY_ROWS = 900;
TelemetryRow telemetryRows[MAX_TELEMETRY_ROWS];
size_t telemetryCount = 0;

bool sessionCaptureActive = false;
bool sessionUploadQueued = false;
bool sessionUploadSent = false;

uint32_t sessionStartMs = 0;
uint32_t sessionEndMs = 0;
uint32_t lastTelemetrySampleMs = 0;

char sessionUploadId[31] = "";
char sessionStartReason[21] = "MANUAL_BUTTON";
char sessionStopReason[21] = "AUTO_PROFILE";
int sessionUserId = USER_ID;
bool sessionCupPresentForPayload = true;

/* duration thực = tổng thời gian relay ON */
uint32_t sessionActivePumpMs = 0;
uint32_t pumpRunStartedMs = 0;
uint16_t sessionPumpRunCount = 0;

static const uint32_t TELEMETRY_SAMPLE_MS = 500;
uint32_t lastUploadTryMs = 0;
static const uint32_t UPLOAD_RETRY_MS = 1200;

uint32_t lastHealthMs = 0;
const uint32_t HEALTH_PERIOD_MS = 300000;

/* ===== HEALTH SEND CONTROL ===== */
bool healthOverdue = false;
uint32_t lastHealthDebugMs = 0;
static const uint32_t HEALTH_DEBUG_COOLDOWN_MS = 5000;

/* =========================================================
   =================== FORWARD DECLARATIONS ================
   ========================================================= */

void goState(uint8_t newState);
bool readyToStart();
void startSessionCapture(const char* startReason);
void lcdPrint2(const char* l1, const char* l2);
void flushPendingFlowSample(uint32_t now);
void appendTelemetry(int sensorTypeId, float value, uint32_t tOffsetMs);
float sampleHealthFlowMlPerSec(uint32_t windowMs);
String buildHealthJson();

bool parseYesNoValue(const String& s, bool& outValue);
String buildRemoteStatusJson();
void handleComponentStatusUpdate();
void handleComponentStatusGet();
bool hasRemoteComponentFault();
void showRemoteComponentWarning();

float readDistanceStable(bool& valid);
bool pumpSensorCheckArmed(uint32_t now);
bool reachedTargetByRealtimeWeight(uint32_t now);
void updatePumpRemovalConfidence(uint32_t now);
bool confirmedCupRemovedDuringPump();
void triggerImmediateCupStop(const char* reason);
String stateName(uint8_t s);

/* =========================================================
   =================== QUEUE FUNCTIONS =====================
   ========================================================= */

void enqueueSession(const String& json) {
  if (queueCount < MAX_OFFLINE_SESSIONS) {
    offlineQueue[queueTail] = json;
    offlineRetryCount[queueTail] = 0;
    queueTail = (queueTail + 1) % MAX_OFFLINE_SESSIONS;
    queueCount++;
    Serial.print("[QUEUE] Saved. Count=");
    Serial.println(queueCount);
  } else {
    Serial.println("[QUEUE] Full -> overwrite oldest");
    offlineQueue[queueTail] = json;
    offlineRetryCount[queueTail] = 0;
    queueTail = (queueTail + 1) % MAX_OFFLINE_SESSIONS;
    queueHead = (queueHead + 1) % MAX_OFFLINE_SESSIONS;
  }
}

bool hasClientConnected() {
  return wifiApRunning && WiFi.softAPgetStationNum() > 0;
}

String stateName(uint8_t s) {
  if (s == ST_IDLE) return "IDLE";
  if (s == ST_WAIT_3S) return "WAIT_3S";
  if (s == ST_PUMPING) return "PUMPING";
  if (s == ST_SETTLING) return "SETTLING";
  if (s == ST_DONE) return "DONE";
  return "UNKNOWN";
}

/* =========================================================
   =================== WIFI & WEB FUNCTIONS ================
   ========================================================= */

void startWifiAPWindow() {
  if (!wifiApRunning) {
    WiFi.mode(WIFI_AP);
    bool ok = WiFi.softAP(WIFI_NAME, WIFI_PASS);

    if (ok) {
      wifiApRunning = true;
      wifiWindowStartMs = millis();

      Serial.println("[WIFI] AP started");
      Serial.print("[WIFI] SSID: ");
      Serial.println(WIFI_NAME);
      Serial.print("[WIFI] PASS: ");
      Serial.println(WIFI_PASS);
      Serial.print("[WIFI] IP: ");
      Serial.println(WiFi.softAPIP());

      server.begin();
      Serial.println("[WEB] Server restarted");
    } else {
      Serial.println("[WIFI] AP start failed");
    }
  } else {
    wifiWindowStartMs = millis();
  }
}

void stopWifiAP() {
  if (wifiApRunning) {
    server.close();
    server.stop();
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_OFF);
    wifiApRunning = false;
    lastClientConnected = false;
    clientConnectedSinceMs = 0;
    Serial.println("[WIFI] AP stopped");
  }
}

void handleWifiWindow(uint32_t now) {
  if (!wifiApRunning) return;

  int clients = WiFi.softAPgetStationNum();

  if (clients > 0) {
    wifiWindowStartMs = now;
    return;
  }

  if ((now - wifiWindowStartMs) >= WIFI_WINDOW_MS) {
    stopWifiAP();
  }
}

void updateClientState(uint32_t now) {
  bool connected = hasClientConnected();

  if (connected != lastClientConnected) {
    lastClientConnected = connected;

    if (connected) {
      clientConnectedSinceMs = now;
      Serial.println("[WIFI] Client connected");
      lcdPrint2("WiFi connected", "Ready/sending");
    } else {
      clientConnectedSinceMs = 0;
      Serial.println("[WIFI] Client disconnected");
      if (queueCount > 0) lcdPrint2("WiFi no client", "RAM queue mode");
      else lcdPrint2("WiFi no client", "AP timeout soon");
    }
  }
}

/* =========================================================
   ============== REMOTE STATUS WEB FUNCTIONS ==============
   ========================================================= */

bool parseYesNoValue(const String& s, bool& outValue) {
  String v = s;
  v.trim();
  v.toLowerCase();

  if (v == "yes" || v == "true" || v == "1" || v == "ok") {
    outValue = true;
    return true;
  }

  if (v == "no" || v == "false" || v == "0" || v == "fail") {
    outValue = false;
    return true;
  }

  return false;
}

String buildRemoteStatusJson() {
  String json = "{";
  json += "\"hc_sr04\":\"";
  json += (remoteHcSr04Ok ? "yes" : "no");
  json += "\",\"loadcell\":\"";
  json += (remoteLoadcellOk ? "yes" : "no");
  json += "\"}";
  return json;
}

void handleComponentStatusUpdate() {
  bool changed = false;
  bool parsedValue;

  if (server.hasArg("hc_sr04")) {
    if (!parseYesNoValue(server.arg("hc_sr04"), parsedValue)) {
      server.send(400, "application/json", "{\"error\":\"hc_sr04 must be yes/no\"}");
      return;
    }
    remoteHcSr04Ok = parsedValue;
    changed = true;
  }

  if (server.hasArg("loadcell")) {
    if (!parseYesNoValue(server.arg("loadcell"), parsedValue)) {
      server.send(400, "application/json", "{\"error\":\"loadcell must be yes/no\"}");
      return;
    }
    remoteLoadcellOk = parsedValue;
    changed = true;
  }

  if (!changed) {
    server.send(400, "application/json", "{\"error\":\"missing hc_sr04 or loadcell\"}");
    return;
  }

  lastRemoteStatusMs = millis();

  Serial.print("[REMOTE STATUS] HC-SR04=");
  Serial.print(remoteHcSr04Ok ? "YES" : "NO");
  Serial.print(" | LOADCELL=");
  Serial.println(remoteLoadcellOk ? "YES" : "NO");

  server.send(200, "application/json", buildRemoteStatusJson());
}

void handleComponentStatusGet() {
  server.send(200, "application/json", buildRemoteStatusJson());
}

bool hasRemoteComponentFault() {
  return (!remoteHcSr04Ok || !remoteLoadcellOk);
}

void showRemoteComponentWarning() {
  if (!remoteHcSr04Ok && !remoteLoadcellOk) {
    lcdPrint2("HC+Loadcell loi", "Check web");
  } else if (!remoteHcSr04Ok) {
    lcdPrint2("HC-SR04 loi", "Check web");
  } else if (!remoteLoadcellOk) {
    lcdPrint2("Loadcell loi", "Check web");
  }
}

/* =========================================================
   =================== LCD FUNCTIONS =======================
   ========================================================= */

bool lcdPingOk() {
  Wire.beginTransmission(LCD_ADDR);
  return (Wire.endTransmission() == 0);
}

void makeLcdLine(char* out, const char* in) {
  int i = 0;
  for (; i < 16 && in[i] != '\0'; i++) out[i] = in[i];
  for (; i < 16; i++) out[i] = ' ';
  out[16] = '\0';
}

void lcdHardReset() {
  Serial.println("[LCD] HARD RESET");

  Wire.end();
  delay(20);
  Wire.begin();
  Wire.setClock(I2C_CLOCK_HZ);

  lcd.init();
  lcd.backlight();

  lcdLastLine1[0] = '\0';
  lcdLastLine2[0] = '\0';

  lastLcdResetMs = millis();
  lastLcdUpdateMs = millis();
  lcdFailCount = 0;
}

void lcdPrint2(const char* l1, const char* l2) {
  char line1[17];
  char line2[17];

  makeLcdLine(line1, l1);
  makeLcdLine(line2, l2);

  if (strcmp(line1, lcdLastLine1) == 0 && strcmp(line2, lcdLastLine2) == 0) {
    return;
  }

  lcd.setCursor(0, 0);
  lcd.print(line1);
  lcd.setCursor(0, 1);
  lcd.print(line2);

  strcpy(lcdLastLine1, line1);
  strcpy(lcdLastLine2, line2);

  lastLcdUpdateMs = millis();
}

void lcdClearSafe() {
  lcdPrint2("", "");
}

/* =========================================================
   ===================== BUTTON ============================
   ========================================================= */

bool readButtonRawPressed() {
  int raw = digitalRead(BUTTON_PIN);
  return BUTTON_ACTIVE_LOW ? (raw == LOW) : (raw == HIGH);
}

bool updateButtonAndGetPressEvent(uint32_t now) {
  bool rawPressed = readButtonRawPressed();

  if (rawPressed != buttonLastRawPressed) {
    buttonLastRawPressed = rawPressed;
    buttonLastChangeMs = now;
  }

  bool pressedEvent = false;

  if ((now - buttonLastChangeMs) >= BUTTON_DEBOUNCE_MS) {
    if (buttonStablePressed != buttonLastRawPressed) {
      buttonStablePressed = buttonLastRawPressed;
      if (buttonStablePressed) pressedEvent = true;
    }
  }

  return pressedEvent;
}

/* =========================================================
   ===================== RELAY =============================
   ========================================================= */

void pumpOn() {
  if (!pumpIsOn) {
    digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? LOW : HIGH);
    pumpIsOn = true;
    pumpStateChangedMs = millis();

    pumpLoadcellLowCount = 0;
    pumpUltraLostCount = 0;

    if (sessionCaptureActive) {
      pumpRunStartedMs = millis();
      sessionPumpRunCount++;
    }
  }
}

void pumpOff() {
  if (pumpIsOn) {
    if (sessionCaptureActive && pumpRunStartedMs > 0) {
      uint32_t now = millis();
      sessionActivePumpMs += (now - pumpRunStartedMs);
      pumpRunStartedMs = 0;
    }

    digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
    pumpIsOn = false;
    pumpStateChangedMs = millis();

    pumpLoadcellLowCount = 0;
    pumpUltraLostCount = 0;
  }
}

/* =========================================================
   ===================== HX711 =============================
   ========================================================= */

long hxReadRaw() {
  return hx.read();
}

long readMedianRaw3() {
  long v[3];
  for (int i = 0; i < 3; i++) {
    v[i] = hx.read();
    delay(1);
    yield();
  }

  if (v[0] > v[1]) { long t = v[0]; v[0] = v[1]; v[1] = t; }
  if (v[1] > v[2]) { long t = v[1]; v[1] = v[2]; v[2] = t; }
  if (v[0] > v[1]) { long t = v[0]; v[0] = v[1]; v[1] = t; }

  return v[1];
}

float gramsFromRaw(long raw) {
  return ((float)(raw - hx_offset) / CAL_FACTOR) + LOADCELL_OFFSET_G;
}

long readAverageRaw(int n) {
  if (n < 5) n = 5;
  if (n > 20) n = 20;

  long sum = 0;
  for (int i = 0; i < n; i++) {
    sum += hxReadRaw();
    delay(3);
    yield();
  }
  return sum / n;
}

void tareEmptyScaleAtBoot() {
  Serial.println("[HX711] Taring empty scale at boot...");

  delay(800);

  long s1 = readAverageRaw(HX711_TARE_SAMPLES);
  delay(150);
  long s2 = readAverageRaw(HX711_TARE_SAMPLES);
  delay(150);
  long s3 = readAverageRaw(HX711_TARE_SAMPLES);

  hx_offset = (s1 + s2 + s3) / 3;

  weightG = 0.0f;
  weightGFiltered = 0.0f;
  lastAcceptedWeightG = 0.0f;
  hasAcceptedWeight = true;
  pendingLargeStepWeightG = 0.0f;
  pendingLargeStepCount = 0;
  cupPresentByWeight = false;

  Serial.print("[HX711] Boot raw offset = ");
  Serial.println(hx_offset);

  Serial.print("[HX711] Loadcell gram offset = ");
  Serial.println(LOADCELL_OFFSET_G, 3);
}

float measureAverageWeightOverMs(uint32_t durationMs) {
  uint32_t startMs = millis();
  float sum = 0.0f;
  int count = 0;

  while (millis() - startMs < durationMs) {
    long raw = readMedianRaw3();
    float g = gramsFromRaw(raw);

    if (g >= MIN_VALID_WEIGHT_G && g <= MAX_VALID_WEIGHT_G) {
      sum += g;
      count++;
    }

    delay(25);
    yield();
  }

  if (count <= 0) return weightGFiltered;
  return sum / count;
}

/* =========================================================
   ===================== HC-SR04 ===========================
   ========================================================= */

bool isDistanceInStartWindow() {
  return lastValid && lastDistanceCm >= START_RANGE_MIN_CM && lastDistanceCm <= START_RANGE_MAX_CM;
}

bool isOutOfStartWindow() {
  return (!lastValid) || (lastDistanceCm < START_RANGE_MIN_CM) || (lastDistanceCm > START_RANGE_MAX_CM);
}

float readDistanceCm(bool& valid) {
  valid = false;

  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  uint32_t duration = pulseIn(ECHO_PIN, HIGH, 10000);
  if (duration == 0) return -1.0f;

  float cm = (float)duration * 0.0343f / 2.0f;
  cm += HC_SR04_OFFSET_CM;

  if (cm < MIN_VALID_CM || cm > MAX_VALID_CM) return -1.0f;

  valid = true;
  return cm;
}

float readDistanceStable(bool& valid) {
  if (!pumpIsOn) {
    return readDistanceCm(valid);
  }

  bool v1, v2, v3;
  float d1 = readDistanceCm(v1);
  delay(3);
  float d2 = readDistanceCm(v2);
  delay(3);
  float d3 = readDistanceCm(v3);

  int validCount = 0;
  float vals[3];

  if (v1) vals[validCount++] = d1;
  if (v2) vals[validCount++] = d2;
  if (v3) vals[validCount++] = d3;

  if (validCount == 0) {
    valid = false;
    return -1.0f;
  }

  if (validCount == 1) {
    valid = true;
    return vals[0];
  }

  if (validCount == 2) {
    valid = true;
    return (vals[0] + vals[1]) / 2.0f;
  }

  if (vals[0] > vals[1]) { float t = vals[0]; vals[0] = vals[1]; vals[1] = t; }
  if (vals[1] > vals[2]) { float t = vals[1]; vals[1] = vals[2]; vals[2] = t; }
  if (vals[0] > vals[1]) { float t = vals[0]; vals[0] = vals[1]; vals[1] = t; }

  valid = true;
  return vals[1];
}

/* =========================================================
   ===================== FLOW HELPERS ======================
   ========================================================= */

void IRAM_ATTR flowPulseISR() {
  static uint32_t lastPulseUs = 0;
  uint32_t nowUs = (uint32_t)micros();

  if ((uint32_t)(nowUs - lastPulseUs) >= FLOW_ISR_DEBOUNCE_US) {
    flowPulseCounter++;
    lastPulseUs = nowUs;
  }
}

uint32_t takeFlowPulses() {
  noInterrupts();
  uint32_t pulses = flowPulseCounter;
  flowPulseCounter = 0;
  interrupts();
  return pulses;
}

float flowMlPerSecFromPulses(uint32_t pulses, uint32_t windowMs) {
  if (windowMs == 0) return 0.0f;
  float pulsesPerSec = ((float)pulses * 1000.0f) / (float)windowMs;
  return (pulsesPerSec * 1000.0f) / FLOW_PULSES_PER_LITER;
}

float sampleHealthFlowMlPerSec(uint32_t windowMs) {
  if (windowMs < FLOW_MIN_VALID_WINDOW_MS) {
    windowMs = FLOW_MIN_VALID_WINDOW_MS;
  }

  noInterrupts();
  flowPulseCounter = 0;
  interrupts();

  delay(windowMs);

  uint32_t pulses = takeFlowPulses();
  return flowMlPerSecFromPulses(pulses, windowMs);
}

String buildHealthJson() {
  float healthFlowMlPerSec = sampleHealthFlowMlPerSec(300);

  String healthJson = "[{\"sensor_name\":\"LOADCELL\",\"value\":\"" + String(weightGFiltered, 2) + "\"}";

  if (lastValid) {
    healthJson += ",{\"sensor_name\":\"ULTRASONIC\",\"value\":\"" + String(lastDistanceCm, 2) + "\"}";
  }

  healthJson += ",{\"sensor_name\":\"FLOW\",\"value\":\"" + String(healthFlowMlPerSec, 2) + "\"}";
  healthJson += "]";

  return healthJson;
}

void flushPendingFlowSample(uint32_t now) {
  if (!sessionCaptureActive) return;
  if (now < sessionStartMs) return;
  if (now < lastTelemetrySampleMs) return;

  uint32_t sampleWindowMs = now - lastTelemetrySampleMs;
  if (sampleWindowMs < FLOW_MIN_VALID_WINDOW_MS) return;

  uint32_t tOffsetMs = now - sessionStartMs;
  uint32_t flowPulses = takeFlowPulses();

  if (flowPulses > 0) {
    float flowMlPerSec = flowMlPerSecFromPulses(flowPulses, sampleWindowMs);
    appendTelemetry(SENSOR_FLOW, flowMlPerSec, tOffsetMs);

    Serial.print("[FLOW FLUSH] pulses=");
    Serial.print(flowPulses);
    Serial.print(" windowMs=");
    Serial.print(sampleWindowMs);
    Serial.print(" flow=");
    Serial.println(flowMlPerSec, 3);
  }

  lastTelemetrySampleMs = now;
}

/* =========================================================
   ===================== TELEMETRY =========================
   ========================================================= */

void clearTelemetryBuffer() {
  telemetryCount = 0;
}

void appendTelemetry(int sensorTypeId, float value, uint32_t tOffsetMs) {
  if (telemetryCount >= MAX_TELEMETRY_ROWS) {
    static uint32_t lastWarnMs = 0;
    if (millis() - lastWarnMs > 1000) {
      lastWarnMs = millis();
      Serial.println("[TELEM] Buffer full, dropping row");
    }
    return;
  }

  telemetryRows[telemetryCount].sensorTypeId = sensorTypeId;
  telemetryRows[telemetryCount].value = value;
  telemetryRows[telemetryCount].tOffsetMs = tOffsetMs;
  telemetryCount++;
}

void generateUploadId(char* out, size_t outLen) {
  static uint32_t uploadCounter = 0;
  uploadCounter++;

  uint32_t ms  = millis();
  uint32_t sec = ms / 1000UL;

  snprintf(out, outLen, "ESP%08lu%08lu%08lu%03d",
           (unsigned long)sec,
           (unsigned long)(ms % 100000000UL),
           (unsigned long)(uploadCounter % 100000000UL),
           DEVICE_ID);
}

void startSessionCapture(const char* startReason) {
  clearTelemetryBuffer();

  sessionCaptureActive = true;
  sessionUploadQueued = false;
  sessionUploadSent = false;

  sessionStartMs = millis();
  sessionEndMs = sessionStartMs;
  lastTelemetrySampleMs = sessionStartMs;

  sessionActivePumpMs = 0;
  pumpRunStartedMs = 0;
  sessionPumpRunCount = 0;

  strncpy(sessionStartReason, startReason, sizeof(sessionStartReason) - 1);
  sessionStartReason[sizeof(sessionStartReason) - 1] = '\0';

  strncpy(sessionStopReason, "AUTO_PROFILE", sizeof(sessionStopReason) - 1);
  sessionStopReason[sizeof(sessionStopReason) - 1] = '\0';

  sessionCupPresentForPayload = true;

  generateUploadId(sessionUploadId, sizeof(sessionUploadId));

  noInterrupts();
  flowPulseCounter = 0;
  interrupts();

  Serial.print("[SESSION] Started capture, upload_id=");
  Serial.println(sessionUploadId);
  Serial.print("[SESSION] user_id=");
  Serial.println(sessionUserId);
}

void stopSessionCapture() {
  uint32_t now = millis();

  if (pumpIsOn && sessionCaptureActive && pumpRunStartedMs > 0) {
    sessionActivePumpMs += (now - pumpRunStartedMs);
    pumpRunStartedMs = 0;
  }

  flushPendingFlowSample(now);

  sessionCaptureActive = false;
  sessionEndMs = now;
}

void sampleTelemetryIfNeeded(uint32_t now) {
  if (!sessionCaptureActive) return;
  if (now < sessionStartMs) return;
  if (now < lastTelemetrySampleMs) return;
  if ((now - lastTelemetrySampleMs) < TELEMETRY_SAMPLE_MS) return;

  uint32_t sampleWindowMs = now - lastTelemetrySampleMs;
  uint32_t tOffsetMs = now - sessionStartMs;
  lastTelemetrySampleMs = now;

  uint32_t flowPulses = takeFlowPulses();
  float flowMlPerSec = flowMlPerSecFromPulses(flowPulses, sampleWindowMs);

  if (pumpIsOn || flowPulses > 0) {
    appendTelemetry(SENSOR_FLOW, flowMlPerSec, tOffsetMs);

    Serial.print("[FLOW DBG] pulses=");
    Serial.print(flowPulses);
    Serial.print(" windowMs=");
    Serial.print(sampleWindowMs);
    Serial.print(" flow=");
    Serial.println(flowMlPerSec, 3);
  }

  appendTelemetry(SENSOR_LOADCELL, weightG, tOffsetMs);

  if (lastValid) {
    appendTelemetry(SENSOR_ULTRASONIC, lastDistanceCm, tOffsetMs);
  }
}

String buildBatchJson() {
  String json;
  json.reserve(480 + telemetryCount * 48);

  float actualMl = pouredWeightG;
  if (actualMl < 0) actualMl = 0;

  float durationS = (float)sessionActivePumpMs / 1000.0f;
  if (durationS < 0) durationS = 0;

  float targetMl = targetPourMlForPayload;
  if (targetMl <= 0) targetMl = TARGET_FINAL_WEIGHT_G;

  json += "{";
  json += "\"device_id\":";
  json += String(DEVICE_ID);

  json += ",\"upload_id\":\"";
  json += String(sessionUploadId);
  json += "\"";

  json += ",\"user_id\":";
  json += String(sessionUserId);

  json += ",\"profile_id\":";
  json += String(PROFILE_ID);

  json += ",\"target_ml\":";
  json += String(targetMl, 3);

  json += ",\"actual_ml\":";
  json += String(actualMl, 3);

  json += ",\"duration_s\":";
  json += String(durationS, 3);

  json += ",\"loadcell_offset_raw\":";
  json += String(hx_offset);

  json += ",\"cup_present\":";
  json += (sessionCupPresentForPayload ? "true" : "false");

  json += ",\"start_reason\":\"";
  json += String(sessionStartReason);
  json += "\"";

  json += ",\"stop_reason\":\"";
  json += String(sessionStopReason);
  json += "\"";

  json += ",\"telemetry\":[";
  for (size_t i = 0; i < telemetryCount; i++) {
    if (i > 0) json += ",";

    json += "{";
    json += "\"sensor_type_id\":";
    json += String(telemetryRows[i].sensorTypeId);
    json += ",\"value\":";
    json += String(telemetryRows[i].value, 4);
    json += ",\"t_offset_ms\":";
    json += String(telemetryRows[i].tOffsetMs);
    json += "}";
  }
  json += "]";

  json += "}";
  return json;
}

void queueSessionUpload(const char* stopReason) {
  if (sessionUploadQueued) return;

  stopSessionCapture();

  strncpy(sessionStopReason, stopReason, sizeof(sessionStopReason) - 1);
  sessionStopReason[sizeof(sessionStopReason) - 1] = '\0';

  String json = buildBatchJson();
  enqueueSession(json);

  sessionUploadQueued = true;
  sessionUploadSent = false;

  Serial.println("[UPLOAD] Batch queued");
  Serial.print("[UPLOAD] loadcell_offset_raw = ");
  Serial.println(hx_offset);
  Serial.print("[UPLOAD] telemetry rows = ");
  Serial.println((int)telemetryCount);
  Serial.print("[UPLOAD] activePumpMs = ");
  Serial.println(sessionActivePumpMs);
  Serial.print("[UPLOAD] pumpRunCount = ");
  Serial.println(sessionPumpRunCount);
  Serial.println(json);
}

/* ===== domain helpers ===== */

void queueManualStopAfterPump() {
  sessionCupPresentForPayload = true;
  queueSessionUpload("MANUAL_BUTTON");
}

void queueNoCupAbort() {
  sessionCupPresentForPayload = false;
  queueSessionUpload("ERROR_ABORT");
}

void queueAutoSuccess() {
  sessionCupPresentForPayload = true;
  queueSessionUpload("AUTO_PROFILE");
}

void queueTimeoutFail() {
  sessionCupPresentForPayload = true;
  queueSessionUpload("TIMEOUT_FAILSAFE");
}

void queueErrorAbortUnderPour() {
  sessionCupPresentForPayload = true;
  queueSessionUpload("ERROR_ABORT");
}

void queueSystemError() {
  sessionCupPresentForPayload = true;
  queueSessionUpload("ERROR_ABORT");
}

void tryUploadIfNeeded(uint32_t now) {
  if (queueCount == 0) return;
  if (!hasClientConnected()) return;
  if (clientConnectedSinceMs == 0) return;
  if ((now - clientConnectedSinceMs) < QUEUE_FLUSH_DELAY_MS) return;
  if ((now - lastUploadTryMs) < UPLOAD_RETRY_MS) return;
  if (uploadInProgress) return;

  lastUploadTryMs = now;
  uploadInProgress = true;

  WiFiClient client;
  HTTPClient http;

  String payload = offlineQueue[queueHead];

  Serial.println("[UPLOAD] Sending batch from queue...");
  Serial.print("[UPLOAD] Payload bytes = ");
  Serial.println(payload.length());
  Serial.println("[UPLOAD] Payload preview:");
  Serial.println(payload);

  http.setReuse(false);
  http.begin(client, BACKEND_URL);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-Key", API_KEY);
  http.addHeader("Connection", "close");
  http.setTimeout(8000);

  int httpCode = http.POST((uint8_t*)payload.c_str(), payload.length());

  String resp = "";
  if (httpCode > 0) {
    resp = http.getString();
    if (resp.length() > 200) {
      resp = resp.substring(0, 200);
    }
  }

  Serial.print("[UPLOAD] HTTP code = ");
  Serial.println(httpCode);
  if (resp.length() > 0) {
    Serial.print("[UPLOAD] Response = ");
    Serial.println(resp);
  }

  http.end();
  client.stop();
  delay(20);

  if (httpCode >= 200 && httpCode < 300) {
    offlineQueue[queueHead] = "";
    offlineRetryCount[queueHead] = 0;
    queueHead = (queueHead + 1) % MAX_OFFLINE_SESSIONS;
    queueCount--;

    sessionUploadSent = true;
    sessionUploadQueued = false;

    Serial.print("[UPLOAD] Sent OK. Remaining=");
    Serial.println(queueCount);

    if (queueCount == 0) {
      lcdPrint2("Upload complete", "Ready to pump");
    }
  } else {
    offlineRetryCount[queueHead]++;

    Serial.print("[UPLOAD] Send failed. Retry=");
    Serial.print(offlineRetryCount[queueHead]);
    Serial.print("/");
    Serial.println(MAX_UPLOAD_RETRIES_PER_ITEM);

    if (offlineRetryCount[queueHead] >= MAX_UPLOAD_RETRIES_PER_ITEM) {
      Serial.println("[UPLOAD] Drop bad queue item after max retries");
      offlineQueue[queueHead] = "";
      offlineRetryCount[queueHead] = 0;
      queueHead = (queueHead + 1) % MAX_OFFLINE_SESSIONS;
      queueCount--;

      lcdPrint2("Bad upload drop", "Check backend");
    }
  }

  uploadInProgress = false;
}

/* =========================================================
   ===================== HELPERS ===========================
   ========================================================= */

bool readyToStart() {
  return cupPresentByWeight && isDistanceInStartWindow();
}

bool pumpSensorCheckArmed(uint32_t now) {
  return pumpIsOn && ((now - pumpStateChangedMs) >= PUMP_SENSOR_ARM_MS);
}

bool reachedTargetByRealtimeWeight(uint32_t now) {
  if (!pumpIsOn) return false;
  if ((now - pumpStateChangedMs) < PUMP_WEIGHT_STOP_ARM_MS) return false;
  if (targetWeightG <= 0.0f) return false;

  float stopWeight = targetWeightG - TARGET_MARGIN_G;
  return weightGFiltered >= stopWeight;
}

void updatePumpRemovalConfidence(uint32_t now) {
  if (!pumpIsOn) {
    pumpLoadcellLowCount = 0;
    pumpUltraLostCount = 0;
    return;
  }

  if (!pumpSensorCheckArmed(now)) {
    return;
  }

  bool loadcellLooksRemoved =
      (weightG <= CUP_REMOVE_G_PUMP) ||
      (weightGFiltered <= CUP_REMOVE_G_PUMP);

  bool ultraLooksRemoved =
      (!lastValid) ||
      (lastDistanceCm > ULTRA_REMOVE_MAX_CM) ||
      (lastDistanceCm < ULTRA_REMOVE_MIN_CM);

  if (loadcellLooksRemoved) {
    if (pumpLoadcellLowCount < 255) pumpLoadcellLowCount++;
  } else {
    pumpLoadcellLowCount = 0;
  }

  if (ultraLooksRemoved) {
    if (pumpUltraLostCount < 255) pumpUltraLostCount++;
  } else {
    pumpUltraLostCount = 0;
  }
}

bool confirmedCupRemovedDuringPump() {
  bool bothConfirmed =
      (pumpLoadcellLowCount >= LOADCELL_REMOVE_CONFIRM_PUMP &&
       pumpUltraLostCount >= 1) ||
      (pumpLoadcellLowCount >= 1 &&
       pumpUltraLostCount >= ULTRA_REMOVE_CONFIRM_PUMP);

  bool oneSensorVeryStrong =
      (pumpLoadcellLowCount >= SINGLE_SENSOR_HARD_CONFIRM) ||
      (pumpUltraLostCount >= SINGLE_SENSOR_HARD_CONFIRM);

  return bothConfirmed || oneSensorVeryStrong;
}

void triggerImmediateCupStop(const char* reason) {
  pouring = false;
  pumpOff();

  forcedStopByCupRemoval = true;
  forcedFinalWeightG = lastCupWeightBeforeRemovalG;
  if (forcedFinalWeightG < startWeightAvgG) {
    forcedFinalWeightG = startWeightAvgG;
  }

  Serial.print("[SAFETY STOP] ");
  Serial.print(reason);
  Serial.print(" | savedWeight=");
  Serial.println(forcedFinalWeightG, 2);

  lcdPrint2("Ly da nhac len", "Da dung bom");
  goState(ST_SETTLING);
}

bool stableReadyToStart(uint32_t now) {
  if (readyToStart()) {
    if (stableStartSinceMs == 0) stableStartSinceMs = now;
    return (now - stableStartSinceMs) >= START_STABLE_MS;
  } else {
    stableStartSinceMs = 0;
    return false;
  }
}

void goState(uint8_t newState) {
  state = newState;
  stateSinceMs = millis();
}

uint32_t computePumpMsFromNeed(float needG) {
  if (needG <= 0) return 0;
  float ms = (needG / PUMP_RATE_G_PER_SEC) * 1000.0f;
  if (ms < 80.0f) ms = 80.0f;
  if (ms > MAX_SINGLE_PUMP_MS) ms = MAX_SINGLE_PUMP_MS;
  return (uint32_t)ms;
}

void finishToDone(uint32_t now, const char* line1Text, const char* line2Text) {
  lcdPrint2(line1Text, line2Text);
  cycleRearmNeeded = true;
  doneShowSinceMs = now;
  startWifiAPWindow();
  goState(ST_DONE);
}

void resetSession() {
  pouring = false;
  pumpOff();
  userStopRequested = false;
  startWeightAvgG = 0.0f;
  currentMeasuredWeightG = 0.0f;
  targetWeightG = 0.0f;
  pouredWeightG = 0.0f;
  remainingWeightG = 0.0f;
  realtimeRemainingWeightG = 0.0f;
  realtimePouredWeightG = 0.0f;
  targetPourMlForPayload = 0.0f;
  waitWeightSum = 0.0f;
  waitWeightCount = 0;
  plannedPumpMs = 0;
  topupCount = 0;
  lastSettleWeightG = 0.0f;
  outOfStartWindowSinceMs = 0;
  sessionCaptureActive = false;
  sessionUploadQueued = false;
  sessionUploadSent = false;
  sessionActivePumpMs = 0;
  pumpRunStartedMs = 0;
  sessionPumpRunCount = 0;
  sessionUserId = USER_ID;
  sessionCupPresentForPayload = true;
  telemetryCount = 0;

  pumpLoadcellLowCount = 0;
  pumpUltraLostCount = 0;
  lastCupWeightBeforeRemovalG = 0.0f;
  forcedStopByCupRemoval = false;
  forcedFinalWeightG = 0.0f;
}

/* =========================================================
   ===================== SETUP =============================
   ========================================================= */

void setup() {
  Serial.begin(115200);
  delay(300);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
  pumpIsOn = false;

  if (BUTTON_USE_INTERNAL_PULLUP) pinMode(BUTTON_PIN, INPUT_PULLUP);
  else pinMode(BUTTON_PIN, INPUT);

  pinMode(FLOW_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), flowPulseISR, FALLING);

  Wire.begin();
  Wire.setClock(I2C_CLOCK_HZ);

  lcd.init();
  lcd.backlight();

  server.on("/ping", HTTP_GET, []() {
    if (deviceStatus == "ACTIVE") server.send(200, "text/plain", "OK_ACTIVE");
    else server.send(200, "text/plain", deviceStatus);
  });

  server.on("/set-status", HTTP_POST, []() {
    if (server.hasArg("status")) {
      deviceStatus = server.arg("status");

      lcdLastLine1[0] = '\0';

      if (state == ST_IDLE) {
        if (deviceStatus != "ACTIVE") lcdPrint2("SYSTEM LOCKED", deviceStatus.c_str());
        else lcdPrint2("San sang", "Dat ly vao");
      }

      server.send(200, "text/plain", "OK");
    } else {
      server.send(400, "text/plain", "Missing status");
    }
  });

  server.on("/component-status", HTTP_POST, handleComponentStatusUpdate);
  server.on("/component-status", HTTP_GET, handleComponentStatusGet);

  server.on("/pour", HTTP_POST, []() {
    if (state != ST_IDLE) {
      server.send(400, "text/plain", "BUSY");
      return;
    }

    if (deviceStatus != "ACTIVE") {
      server.send(403, "text/plain", "LOCKED");
      return;
    }

    if (hasRemoteComponentFault()) {
      server.send(400, "text/plain", "COMPONENT_FAULT");
      return;
    }

    if (!readyToStart()) {
      server.send(400, "text/plain", "NO_CUP_OR_BAD_RANGE");
      return;
    }

    int parsedUserId = USER_ID;
    if (server.hasArg("user_id")) {
      int argUserId = server.arg("user_id").toInt();
      if (argUserId > 0) parsedUserId = argUserId;
    }
    sessionUserId = parsedUserId;

    waitWeightSum = 0.0f;
    waitWeightCount = 0;
    startSessionCapture("REMOTE_APP");
    lcdPrint2("Web ra lenh", "Cho 3 giay...");
    Serial.print("[WEB] Start pour via WiFi | user_id=");
    Serial.println(sessionUserId);
    goState(ST_WAIT_3S);

    server.send(200, "text/plain", "OK");
  });

  lcdPrint2("System booting", "Starting AP...");
  delay(700);

  startWifiAPWindow();

  if (wifiApRunning) lcdPrint2("AP started", "Wait client...");
  else lcdPrint2("AP failed", "Local only");
  delay(900);

  Serial.println("De loadcell trong luc khoi dong.");
  tareEmptyScaleAtBoot();

  Serial.print("[HC-SR04] Offset cm = ");
  Serial.println(HC_SR04_OFFSET_CM, 3);

  if (hasClientConnected()) lcdPrint2("WiFi connected", "Ready to pump");
  else lcdPrint2("WiFi no client", "AP timeout soon");
  delay(1200);

  lcdPrint2("San sang", "Dat ly vao");

  lastLcdUpdateMs = millis();
  lastLcdResetMs = millis();
  goState(ST_IDLE);

  lastHealthMs = millis();
  healthOverdue = false;
  lastHealthDebugMs = 0;

  Serial.println("System started!");
  Serial.println("[HEALTH] Timer initialized");
}

/* =========================================================
   ===================== LOOP ==============================
   ========================================================= */

void loop() {
  uint32_t now = millis();

  if (wifiApRunning && !uploadInProgress) {
    server.handleClient();
    now = millis();
  }

  newWeightSample = false;
  bool buttonPressedEvent = updateButtonAndGetPressEvent(now);

  if (!wifiApRunning) {
    startWifiAPWindow();
  } else {
    handleWifiWindow(now);
    updateClientState(now);
  }

  if (!pouring && (state == ST_DONE || state == ST_IDLE)) {
    tryUploadIfNeeded(now);
  }

  bool clientConnected = hasClientConnected();
  bool idleNow = (state == ST_IDLE);
  uint32_t healthElapsedMs = now - lastHealthMs;

  if (healthElapsedMs >= HEALTH_PERIOD_MS) {
    if (!healthOverdue) {
      healthOverdue = true;
      Serial.print("[HEALTH] Mark overdue. elapsedMs=");
      Serial.print(healthElapsedMs);
      Serial.print(" | client=");
      Serial.print(clientConnected ? "YES" : "NO");
      Serial.print(" | idle=");
      Serial.println(idleNow ? "YES" : "NO");
    }

    if (!clientConnected) {
      if ((now - lastHealthDebugMs) >= HEALTH_DEBUG_COOLDOWN_MS) {
        lastHealthDebugMs = now;
        Serial.print("[HEALTH] Due but no client connected -> keep overdue. elapsedMs=");
        Serial.println(healthElapsedMs);
      }
    } else if (!idleNow) {
      if ((now - lastHealthDebugMs) >= HEALTH_DEBUG_COOLDOWN_MS) {
        lastHealthDebugMs = now;
        Serial.print("[HEALTH] Due but device not IDLE -> keep overdue. state=");
        Serial.print(stateName(state));
        Serial.print(" | elapsedMs=");
        Serial.println(healthElapsedMs);
      }
    } else {
      String healthJson = buildHealthJson();

      Serial.print("[HEALTH] Sending overdue health... elapsedMs=");
      Serial.print(healthElapsedMs);
      Serial.print(" | payload=");
      Serial.println(healthJson);

      HTTPClient http;
      WiFiClient client;
      http.setReuse(false);
      http.begin(client, HEALTH_URL);
      http.addHeader("Content-Type", "application/json");
      http.addHeader("X-API-Key", API_KEY);
      http.addHeader("Connection", "close");

      int httpCode = http.POST((uint8_t*)healthJson.c_str(), healthJson.length());
      String resp = http.getString();
      http.end();
      client.stop();

      Serial.print("[HEALTH] HTTP code=");
      Serial.println(httpCode);

      if (resp.length() > 0) {
        Serial.print("[HEALTH] Response=");
        Serial.println(resp);
      }

      if (httpCode >= 200 && httpCode < 300) {
        lastHealthMs = now;
        healthOverdue = false;
        lastHealthDebugMs = 0;

        Serial.print("[HEALTH] Send success -> timer reset at ms=");
        Serial.println(lastHealthMs);
      } else {
        Serial.println("[HEALTH] Send failed -> keep overdue for retry");
      }
    }
  }

  if (now - lastLcdPingMs >= LCD_PING_PERIOD_MS) {
    lastLcdPingMs = now;

    if (!lcdPingOk()) {
      lcdFailCount++;
      if (lcdFailCount >= LCD_FAILS_TO_RESET && (now - lastLcdResetMs) > LCD_RESET_COOLDOWN_MS) {
        lcdHardReset();
      }
    } else {
      lcdFailCount = 0;
    }
  }

  uint32_t weightPeriod = pumpIsOn ? WEIGHT_PERIOD_PUMP_MS : WEIGHT_PERIOD_IDLE_MS;

  if (now - lastWeightMs >= weightPeriod) {
    lastWeightMs = now;

    long raw = readMedianRaw3();
    float newWeight = gramsFromRaw(raw);

    bool accept = true;
    bool hardResetFilter = false;

    if (newWeight < MIN_VALID_WEIGHT_G || newWeight > MAX_VALID_WEIGHT_G) {
      accept = false;
    }

    if (accept && hasAcceptedWeight) {
      float delta = fabs(newWeight - lastAcceptedWeightG);

      if (delta > MAX_STEP_CHANGE_IDLE_G) {
        if (pendingLargeStepCount == 0 ||
            fabs(newWeight - pendingLargeStepWeightG) > LARGE_STEP_CONFIRM_BAND_G) {
          pendingLargeStepWeightG = newWeight;
          pendingLargeStepCount = 1;
          accept = false;
        } else {
          pendingLargeStepCount++;

          if (pendingLargeStepCount >= LARGE_STEP_CONFIRM_SAMPLES) {
            accept = true;
            hardResetFilter = true;
            pendingLargeStepCount = 0;
          } else {
            accept = false;
          }
        }
      } else {
        pendingLargeStepCount = 0;
      }
    }

    if (accept) {
      if (!pumpIsOn && !cupPresentByWeight && newWeight < 0.0f && newWeight > -5.0f) {
        newWeight = 0.0f;
      }

      weightG = newWeight;
      lastAcceptedWeightG = newWeight;
      hasAcceptedWeight = true;

      float alpha = pumpIsOn ? WEIGHT_ALPHA_PUMP : WEIGHT_ALPHA_IDLE;

      if (hardResetFilter) {
        weightGFiltered = newWeight;
        Serial.print("[HX711] Large real step accepted -> reset filter to ");
        Serial.println(newWeight, 2);
      } else {
        weightGFiltered = (1.0f - alpha) * weightGFiltered + alpha * weightG;
      }

      if (!pumpIsOn && !cupPresentByWeight && weightGFiltered < 0.5f) {
        weightGFiltered = 0.0f;
      }

      newWeightSample = true;
    } else {
      static uint32_t lastSpikeLogMs = 0;
      if (fabs(newWeight - lastAcceptedWeightG) > 150.0f && (millis() - lastSpikeLogMs > 1500)) {
        lastSpikeLogMs = millis();
        Serial.print("[HX711 SPIKE IGNORED] weight=");
        Serial.println(newWeight, 2);
      }
    }

    if (!cupPresentByWeight && weightGFiltered >= CUP_DETECT_G) {
      cupPresentByWeight = true;
      Serial.println("[CUP] detected by weight");
    }

    if (cupPresentByWeight && weightGFiltered > CUP_REMOVE_G_PUMP) {
      lastCupWeightBeforeRemovalG = weightGFiltered;
    }

    if (!pumpIsOn) {
      if (cupPresentByWeight && weightGFiltered <= CUP_REMOVE_G) {
        cupPresentByWeight = false;
        Serial.println("[CUP] removed");
      }
    }
  }

  uint32_t ultraPeriod = pumpIsOn ? ULTRA_PERIOD_PUMP_MS : ULTRA_PERIOD_MS;

  if (now - lastUltraMs >= ultraPeriod) {
    lastUltraMs = now;

    bool validNow;
    float cm = readDistanceStable(validNow);

    if (validNow) {
      lastValid = true;
      lastDistanceCm = cm;
      lastValidDistanceMs = now;
    } else {
      uint32_t holdMs = pumpIsOn ? DIST_HOLD_PUMP_MS : DIST_HOLD_MS;

      if (lastValid && (now - lastValidDistanceMs) <= holdMs) {
        // giữ giá trị cũ trong khoảng ngắn
      } else {
        lastValid = false;
        lastDistanceCm = -1.0f;
      }
    }
  }

  updatePumpRemovalConfidence(now);
  sampleTelemetryIfNeeded(now);

  if (targetWeightG > 0.0f) {
    realtimeRemainingWeightG = targetWeightG - weightGFiltered;
    if (realtimeRemainingWeightG < 0.0f) realtimeRemainingWeightG = 0.0f;

    realtimePouredWeightG = weightGFiltered - startWeightAvgG;
    if (realtimePouredWeightG < 0.0f) realtimePouredWeightG = 0.0f;
  } else {
    realtimeRemainingWeightG = 0.0f;
    realtimePouredWeightG = 0.0f;
  }

  switch (state) {
    case ST_IDLE: {
      pouring = false;
      pumpOff();
      userStopRequested = false;

      if (hasRemoteComponentFault()) {
        showRemoteComponentWarning();
      } else if (deviceStatus != "ACTIVE") {
        lcdPrint2("SYSTEM LOCKED", deviceStatus.c_str());
      }

      if (cycleRearmNeeded) {
        if (!cupPresentByWeight) {
          cycleRearmNeeded = false;
          outOfStartWindowSinceMs = 0;
          Serial.println("[REARM] Cup removed -> next cycle allowed");
        } else if (isOutOfStartWindow()) {
          if (outOfStartWindowSinceMs == 0) outOfStartWindowSinceMs = now;

          if ((now - outOfStartWindowSinceMs) >= REARM_OUT_OF_RANGE_MS) {
            cycleRearmNeeded = false;
            outOfStartWindowSinceMs = 0;
            Serial.println("[REARM] Cup moved out of sensor zone -> next cycle allowed");
          }
        } else {
          outOfStartWindowSinceMs = 0;
        }
      } else {
        if (buttonPressedEvent) {
          if (deviceStatus != "ACTIVE") {
            lcdPrint2("SYSTEM LOCKED", "Khong the pump");
            Serial.println("[BLOCK] Start denied by device status");
            break;
          }

          if (hasRemoteComponentFault()) {
            lcdPrint2("Linh kien loi", "Khong the pump");
            Serial.println("[BLOCK] Start denied by remote status");
            break;
          }

          if (stableReadyToStart(now) || readyToStart()) {
            waitWeightSum = 0.0f;
            waitWeightCount = 0;
            sessionUserId = USER_ID;
            startSessionCapture("MANUAL_BUTTON");

            if (hasClientConnected()) lcdPrint2("Button accepted", "3 sec countdown");
            else lcdPrint2("Button accepted", "Offline 3 sec");

            Serial.println("[BUTTON] Start pour");
            goState(ST_WAIT_3S);
          } else {
            lcdPrint2("Dat ly dung", "5-10cm");
            Serial.println("[BUTTON] Start ignored: cup/range invalid");
          }
        }
      }
      break;
    }

    case ST_WAIT_3S: {
      pouring = false;
      pumpOff();
      userStopRequested = false;

      if (buttonPressedEvent) {
        Serial.println("[BUTTON] Cancel in WAIT_3S");
        resetSession();
        lcdClearSafe();
        stableStartSinceMs = 0;
        waitWeightSum = 0.0f;
        waitWeightCount = 0;
        goState(ST_IDLE);
        break;
      }

      if (!readyToStart()) {
        Serial.println("[STATE] WAIT_3S -> IDLE");
        queueNoCupAbort();
        lcdPrint2("No cup / moved", "Queued upload");
        stableStartSinceMs = 0;
        waitWeightSum = 0.0f;
        waitWeightCount = 0;
        goState(ST_IDLE);
        break;
      }

      if (newWeightSample) {
        if (weightGFiltered >= MIN_VALID_WEIGHT_G && weightGFiltered <= MAX_VALID_WEIGHT_G) {
          waitWeightSum += weightGFiltered;
          waitWeightCount++;
        }
      }

      if ((now - stateSinceMs) >= PRE_POUR_DELAY_MS) {
        if (waitWeightCount > 0) startWeightAvgG = waitWeightSum / (float)waitWeightCount;
        else startWeightAvgG = measureAverageWeightOverMs(300);

        targetWeightG = TARGET_FINAL_WEIGHT_G;
        currentMeasuredWeightG = startWeightAvgG;

        targetPourMlForPayload = targetWeightG - startWeightAvgG;
        if (targetPourMlForPayload < 0) targetPourMlForPayload = 0;

        remainingWeightG = targetWeightG - currentMeasuredWeightG;
        if (remainingWeightG < 0) remainingWeightG = 0;

        pouredWeightG = 0.0f;
        topupCount = 0;
        lastSettleWeightG = startWeightAvgG;
        userStopRequested = false;

        lastCupWeightBeforeRemovalG = startWeightAvgG;
        forcedStopByCupRemoval = false;
        forcedFinalWeightG = 0.0f;

        if (remainingWeightG <= TARGET_MARGIN_G) {
          queueAutoSuccess();
          lcdPrint2("Da du muc", "Lay ly ra");
          cycleRearmNeeded = true;
          doneShowSinceMs = now;
          startWifiAPWindow();
          goState(ST_DONE);
          break;
        }

        plannedPumpMs = computePumpMsFromNeed(remainingWeightG);

        Serial.println("[POUR START]");
        Serial.print("  startWeightAvgG = ");
        Serial.println(startWeightAvgG, 2);
        Serial.print("  targetWeightG   = ");
        Serial.println(targetWeightG, 2);
        Serial.print("  targetPayloadMl = ");
        Serial.println(targetPourMlForPayload, 2);
        Serial.print("  initialNeedG    = ");
        Serial.println(remainingWeightG, 2);
        Serial.print("  plannedPumpMs   = ");
        Serial.println(plannedPumpMs);

        pumpOn();
        pouring = true;
        lcdPrint2("Dang pump...", "AUTO");
        goState(ST_PUMPING);
      }
      break;
    }

    case ST_PUMPING: {
      pouring = true;

      if (confirmedCupRemovedDuringPump()) {
        triggerImmediateCupStop("Cup lost confirmed");
        break;
      }

      if (buttonPressedEvent) {
        userStopRequested = true;
        pouring = false;
        pumpOff();
        Serial.println("[BUTTON] User finished pour");
        goState(ST_SETTLING);
        break;
      }

      if (reachedTargetByRealtimeWeight(now)) {
        pouring = false;
        pumpOff();
        Serial.print("[PUMP] OFF by realtime weight | weight=");
        Serial.print(weightGFiltered, 2);
        Serial.print(" | stopAt=");
        Serial.println(targetWeightG - TARGET_MARGIN_G, 2);
        goState(ST_SETTLING);
        break;
      }

      if ((now - stateSinceMs) >= plannedPumpMs) {
        pouring = false;
        pumpOff();
        Serial.println("[PUMP] OFF by planned time");
        goState(ST_SETTLING);
      }
      break;
    }

    case ST_SETTLING: {
      pouring = false;
      pumpOff();

      if ((now - stateSinceMs) >= SETTLE_AFTER_PUMP_MS) {
        float finalWeight;
        if (forcedStopByCupRemoval) finalWeight = forcedFinalWeightG;
        else finalWeight = measureAverageWeightOverMs(400);

        if (!forcedStopByCupRemoval && !cupPresentByWeight) {
          if (lastCupWeightBeforeRemovalG > (startWeightAvgG + 0.5f)) {
            finalWeight = lastCupWeightBeforeRemovalG;
            Serial.println("[SETTLING] Cup absent after pump -> use last stable cup weight");
            Serial.print("[SETTLING] snapshotWeight=");
            Serial.println(finalWeight, 2);
          } else {
            queueNoCupAbort();
            finishToDone(now, "Ket thuc som", "Lay ly ra");
            break;
          }
        }

        currentMeasuredWeightG = finalWeight;

        weightG = finalWeight;
        weightGFiltered = finalWeight;
        lastAcceptedWeightG = finalWeight;
        hasAcceptedWeight = true;
        pendingLargeStepWeightG = 0.0f;
        pendingLargeStepCount = 0;

        remainingWeightG = targetWeightG - currentMeasuredWeightG;
        if (remainingWeightG < 0) remainingWeightG = 0;

        pouredWeightG = currentMeasuredWeightG - startWeightAvgG;
        if (pouredWeightG < 0) pouredWeightG = 0;

        float gainThisCycle = finalWeight - lastSettleWeightG;
        lastSettleWeightG = finalWeight;

        if (forcedStopByCupRemoval) {
          queueNoCupAbort();

          Serial.println("[RESULT] Cup removed during pumping");
          Serial.print("[RESULT] final_weight_g = ");
          Serial.println(currentMeasuredWeightG, 2);
          Serial.print("[RESULT] poured_ml = ");
          Serial.println(pouredWeightG, 2);
          Serial.print("[RESULT] duration_s = ");
          Serial.println((float)sessionActivePumpMs / 1000.0f, 2);
          Serial.println("[RESULT] stop_reason = ERROR_ABORT");

          finishToDone(now, "Ly da nhac len", "Da in ket qua");
          forcedStopByCupRemoval = false;
          break;
        }

        if (userStopRequested) {
          queueManualStopAfterPump();
          finishToDone(now, "Da dung tay", "Lay ly ra");
          userStopRequested = false;
          break;
        }

        if (remainingWeightG <= TARGET_MARGIN_G) {
          queueAutoSuccess();
          finishToDone(now, "Da du muc", "Lay ly ra");
          break;
        }

        if (topupCount > 0 && gainThisCycle < MIN_GAIN_PER_TOPUP_G) {
          queueErrorAbortUnderPour();
          finishToDone(now, "Ket thuc som", "Lay ly ra");
          break;
        }

        if (topupCount >= MAX_TOPUP_CYCLES) {
          queueTimeoutFail();
          finishToDone(now, "Ket thuc som", "Lay ly ra");
          break;
        }

        topupCount++;

        if (remainingWeightG > TOPUP_THRESHOLD_G) plannedPumpMs = computePumpMsFromNeed(remainingWeightG);
        else plannedPumpMs = TOPUP_PUMP_MS;

        pumpOn();
        pouring = true;
        lcdPrint2("Dang pump...", "AUTO");
        goState(ST_PUMPING);
      }
      break;
    }

    case ST_DONE: {
      pouring = false;
      pumpOff();

      if ((now - doneShowSinceMs) >= DONE_SCREEN_MS) {
        if (deviceStatus != "ACTIVE") {
          lcdPrint2("SYSTEM LOCKED", deviceStatus.c_str());
        } else if (queueCount > 0 && !hasClientConnected()) {
          lcdPrint2("Queued offline", "Wait reconnect");
        } else if (hasClientConnected()) {
          lcdPrint2("WiFi connected", "Ready to pump");
        } else if (hasRemoteComponentFault()) {
          showRemoteComponentWarning();
        } else {
          lcdPrint2("San sang", "Dat ly vao");
        }

        resetSession();
        goState(ST_IDLE);
      }
      break;
    }
  }

  static uint32_t lastLogMs = 0;
  if (now - lastLogMs >= 1000) {
    lastLogMs = now;

    Serial.print("State=");
    Serial.print(stateName(state));

    Serial.print(" | Dist=");
    Serial.print(lastValid ? lastDistanceCm : -1.0f);

    Serial.print(" cm | AbsW=");
    Serial.print(weightGFiltered, 2);

    Serial.print(" g | StartW=");
    Serial.print(startWeightAvgG, 2);

    Serial.print(" | TargetW=");
    Serial.print(targetWeightG, 2);

    Serial.print(" | PouredNow=");
    Serial.print(realtimePouredWeightG, 2);

    Serial.print(" | RealtimeNeed=");
    Serial.print(realtimeRemainingWeightG, 2);

    Serial.print(" | PlannedNeed=");
    Serial.print(remainingWeightG, 2);

    Serial.print(" | TargetPayload=");
    Serial.print(targetPourMlForPayload, 2);

    Serial.print(" | Cup=");
    Serial.print(cupPresentByWeight ? "YES" : "NO");
    Serial.print(" | SessionCup=");
    Serial.print(sessionCupPresentForPayload ? "YES" : "NO");
    Serial.print(" | Pump=");
    Serial.print(pumpIsOn ? "ON" : "OFF");
    Serial.print(" | UserId=");
    Serial.print(sessionUserId);
    Serial.print(" | Rows=");
    Serial.print((int)telemetryCount);
    Serial.print(" | ActivePumpMs=");
    Serial.print(sessionActivePumpMs);
    Serial.print(" | PumpRuns=");
    Serial.print(sessionPumpRunCount);
    Serial.print(" | Queue=");
    Serial.print(queueCount);
    Serial.print(" | Wifi=");
    Serial.print(wifiApRunning ? "ON" : "OFF");
    Serial.print(" | Clients=");
    Serial.print(wifiApRunning ? WiFi.softAPgetStationNum() : 0);
    Serial.print(" | Btn=");
    Serial.print(buttonStablePressed ? "PRESSED" : "RELEASED");
    Serial.print(" | HC=");
    Serial.print(remoteHcSr04Ok ? "YES" : "NO");
    Serial.print(" | LC=");
    Serial.print(remoteLoadcellOk ? "YES" : "NO");
    Serial.print(" | HXoff=");
    Serial.print(hx_offset);
    Serial.print(" | DevStatus=");
    Serial.print(deviceStatus);
    Serial.print(" | LCcnt=");
    Serial.print(pumpLoadcellLowCount);
    Serial.print(" | Ucnt=");
    Serial.println(pumpUltraLostCount);
  }

  delay(1);
}
