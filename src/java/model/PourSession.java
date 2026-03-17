package model;

import java.sql.Timestamp;
import java.util.List;

public class PourSession {

    private int sessionId;
    private int deviceId;
    private String uploadId;
    private int userId;
    private String username;
    private int profileId;

    private double targetMl;
    private double actualMl;
    private double duration;
    private double peakFlow;
    private double avgFlow;
    private boolean cupPresent;

    private String startReason;
    private String resultCode;
    private String stopReason;
    private String timeSource;

    private Timestamp startedAt;
    private Timestamp endedAt;

    private Double mlRiskScore;
    private String mlReasonJson;

    private boolean mlEligible;
    private String mlExclusionReason;
    private String curatedResultCode;
    private Integer curatedByUserId;
    private Timestamp curatedAt;
    private String curatedNote;

    private List<TelemetryPoint> telemetry;

    public int getSessionId() {
        return sessionId;
    }

    public void setSessionId(int sessionId) {
        this.sessionId = sessionId;
    }

    public int getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(int deviceId) {
        this.deviceId = deviceId;
    }

    public String getUploadId() {
        return uploadId;
    }

    public void setUploadId(String uploadId) {
        this.uploadId = uploadId;
    }

    public int getUserId() {
        return userId;
    }

    public void setUserId(int userId) {
        this.userId = userId;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public int getProfileId() {
        return profileId;
    }

    public void setProfileId(int profileId) {
        this.profileId = profileId;
    }

    public double getTargetMl() {
        return targetMl;
    }

    public void setTargetMl(double targetMl) {
        this.targetMl = targetMl;
    }

    public double getActualMl() {
        return actualMl;
    }

    public void setActualMl(double actualMl) {
        this.actualMl = actualMl;
    }

    public double getDuration() {
        return duration;
    }

    public void setDuration(double duration) {
        this.duration = duration;
    }

    public double getPeakFlow() {
        return peakFlow;
    }

    public void setPeakFlow(double peakFlow) {
        this.peakFlow = peakFlow;
    }

    public double getAvgFlow() {
        return avgFlow;
    }

    public void setAvgFlow(double avgFlow) {
        this.avgFlow = avgFlow;
    }

    public boolean isCupPresent() {
        return cupPresent;
    }

    public void setCupPresent(boolean cupPresent) {
        this.cupPresent = cupPresent;
    }

    public String getStartReason() {
        return startReason;
    }

    public void setStartReason(String startReason) {
        this.startReason = startReason;
    }

    public String getResultCode() {
        return resultCode;
    }

    public void setResultCode(String resultCode) {
        this.resultCode = resultCode;
    }

    public String getStopReason() {
        return stopReason;
    }

    public void setStopReason(String stopReason) {
        this.stopReason = stopReason;
    }

    public String getTimeSource() {
        return timeSource;
    }

    public void setTimeSource(String timeSource) {
        this.timeSource = timeSource;
    }

    public Timestamp getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(Timestamp startedAt) {
        this.startedAt = startedAt;
    }

    public Timestamp getEndedAt() {
        return endedAt;
    }

    public void setEndedAt(Timestamp endedAt) {
        this.endedAt = endedAt;
    }

    public Double getMlRiskScore() {
        return mlRiskScore;
    }

    public void setMlRiskScore(Double mlRiskScore) {
        this.mlRiskScore = mlRiskScore;
    }

    public String getMlReasonJson() {
        return mlReasonJson;
    }

    public void setMlReasonJson(String mlReasonJson) {
        this.mlReasonJson = mlReasonJson;
    }

    public boolean isMlEligible() {
        return mlEligible;
    }

    public void setMlEligible(boolean mlEligible) {
        this.mlEligible = mlEligible;
    }

    public String getMlExclusionReason() {
        return mlExclusionReason;
    }

    public void setMlExclusionReason(String mlExclusionReason) {
        this.mlExclusionReason = mlExclusionReason;
    }

    public String getCuratedResultCode() {
        return curatedResultCode;
    }

    public void setCuratedResultCode(String curatedResultCode) {
        this.curatedResultCode = curatedResultCode;
    }

    public Integer getCuratedByUserId() {
        return curatedByUserId;
    }

    public void setCuratedByUserId(Integer curatedByUserId) {
        this.curatedByUserId = curatedByUserId;
    }

    public Timestamp getCuratedAt() {
        return curatedAt;
    }

    public void setCuratedAt(Timestamp curatedAt) {
        this.curatedAt = curatedAt;
    }

    public String getCuratedNote() {
        return curatedNote;
    }

    public void setCuratedNote(String curatedNote) {
        this.curatedNote = curatedNote;
    }

    public List<TelemetryPoint> getTelemetry() {
        return telemetry;
    }

    public void setTelemetry(List<TelemetryPoint> telemetry) {
        this.telemetry = telemetry;
    }
}
