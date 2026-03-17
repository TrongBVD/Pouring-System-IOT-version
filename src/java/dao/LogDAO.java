package dao;

import com.google.gson.JsonObject;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import model.PourSession;
import model.User;
import utils.DBContext;

public class LogDAO {

    public int saveSessionBatch(JsonObject json, String telemetryJsonStr, User actor) throws SQLException, ClassNotFoundException {
        String sql = "{call PourSession_Ingest_Batch(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}";

        try ( Connection conn = DBContext.getConnection();  CallableStatement cs = conn.prepareCall(sql)) {
            cs.setInt(1, getInt(json, "device_id", 1));
            cs.setString(2, getString(json, "upload_id", "UP_" + System.currentTimeMillis()));
            cs.setInt(3, getInt(json, "user_id", 1));
            cs.setInt(4, getInt(json, "profile_id", 1));

            cs.setInt(5, getInt(json, "target_ml", 0));
            cs.setDouble(6, getDouble(json, "actual_ml", 0.0));
            cs.setDouble(7, getDouble(json, "duration_s", 0.0));
            cs.setBoolean(8, getBoolean(json, "cup_present", true));

            String resultCode = getString(json, "result_code", null);
            if (resultCode == null || resultCode.trim().isEmpty()) {
                resultCode = deriveResultCodeFromStopReason(getString(json, "stop_reason", "AUTO_PROFILE"));
            }
            cs.setString(9, resultCode);
            cs.setString(10, getString(json, "stop_reason", "AUTO_PROFILE"));

            cs.setTimestamp(11, null);
            cs.setTimestamp(12, null);

            cs.setString(13, getString(json, "start_reason", "REMOTE_APP"));
            cs.setString(14, telemetryJsonStr != null ? telemetryJsonStr : "[]");

            if (hasValue(json, "loadcell_offset_raw")) {
                cs.setLong(15, json.get("loadcell_offset_raw").getAsLong());
            } else {
                cs.setNull(15, Types.BIGINT);
            }

            cs.setBoolean(16, getBoolean(json, "ml_eligible", true));
            if (hasValue(json, "ml_exclusion_reason")) {
                cs.setString(17, json.get("ml_exclusion_reason").getAsString());
            } else {
                cs.setNull(17, Types.NVARCHAR);
            }

            if (hasValue(json, "ml_risk_score")) {
                cs.setDouble(18, json.get("ml_risk_score").getAsDouble());
            } else {
                cs.setNull(18, Types.FLOAT);
            }

            if (hasValue(json, "ml_reason_json")) {
                cs.setString(19, json.get("ml_reason_json").getAsString());
            } else {
                cs.setNull(19, Types.NVARCHAR);
            }

            int actorId = actor != null ? actor.getUserId() : 2;
            String actorRole = actor != null ? actor.getRole() : "SYSTEM";
            cs.setInt(20, actorId);
            cs.setString(21, actorRole);
            cs.registerOutParameter(22, Types.INTEGER);

            cs.execute();
            return cs.getInt(22);
        }
    }

    public List<PourSession> getPourHistory() {
        String sql = baseHistorySql() + " ORDER BY psa.started_at DESC";
        return querySessions(sql, null);
    }

    public List<PourSession> getMyPourSession(int userId) {
        String sql = baseHistorySql() + " WHERE psa.user_id = ? ORDER BY psa.started_at DESC";
        return querySessions(sql, ps -> ps.setInt(1, userId));
    }

    public List<PourSession> getPourSessionMetaList() {
        String sql = baseHistorySql() + " ORDER BY psa.started_at DESC";
        return querySessions(sql, null);
    }

    public boolean curateSession(int sessionId, String result, String note, User actor) {
        return updatePourSessionMeta(sessionId, null, null, result, note, actor);
    }

    public boolean updatePourSessionMeta(int sessionId, Boolean mlEligible, String mlExclusionReason,
            String curatedResultCode, String curatedNote, User actor) {
        String sql = "{call PourSessionMeta_Update(?, ?, ?, ?, ?, ?, ?, ?)}";

        try ( Connection conn = DBContext.getConnection();  CallableStatement cs = conn.prepareCall(sql)) {
            cs.setInt(1, sessionId);

            if (mlEligible == null) {
                cs.setNull(2, Types.BIT);
            } else {
                cs.setBoolean(2, mlEligible);
            }

            if (mlExclusionReason == null || mlExclusionReason.trim().isEmpty()) {
                cs.setNull(3, Types.NVARCHAR);
            } else {
                cs.setString(3, mlExclusionReason.trim());
            }

            if (curatedResultCode == null || curatedResultCode.trim().isEmpty()) {
                cs.setNull(4, Types.NVARCHAR);
            } else {
                cs.setString(4, curatedResultCode.trim());
            }

            if (curatedNote == null || curatedNote.trim().isEmpty()) {
                cs.setNull(5, Types.NVARCHAR);
            } else {
                cs.setString(5, curatedNote.trim());
            }

            cs.setInt(6, actor.getUserId());
            cs.setString(7, actor.getRole());
            cs.registerOutParameter(8, Types.INTEGER);
            cs.execute();
            return cs.getInt(8) > 0;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private interface StatementSetter {

        void accept(PreparedStatement ps) throws SQLException;
    }

    private List<PourSession> querySessions(String sql, StatementSetter setter) {
        List<PourSession> list = new ArrayList<>();
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            if (setter != null) {
                setter.accept(ps);
            }
            try ( ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    list.add(mapResultSetToPourSession(rs));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    private String baseHistorySql() {
        return "SELECT psa.session_id, psa.device_id, psa.upload_id, psa.user_id, u.username, psa.profile_id, "
                + "psa.target_ml, psa.actual_ml, psa.duration_s, psa.peak_flow, psa.avg_flow, psa.cup_present, "
                + "psa.start_reason, psa.result_code, psa.stop_reason, psa.started_at, psa.ended_at, psa.time_source, "
                + "pm.ml_eligible, pm.ml_exclusion_reason, pm.curated_result_code, pm.curated_by_user_id, pm.curated_at, pm.curated_note, "
                + "a.risk_score AS ml_risk_score "
                + "FROM dbo.PourSession_Analysis psa "
                + "JOIN dbo.Users u ON u.user_id = psa.user_id "
                + "LEFT JOIN dbo.PourSessionMeta pm ON pm.session_id = psa.session_id "
                + "OUTER APPLY (SELECT TOP 1 al.risk_score FROM dbo.Alert al WHERE al.session_id = psa.session_id ORDER BY al.created_at DESC, al.alert_id DESC) a";
    }

    private PourSession mapResultSetToPourSession(ResultSet rs) throws SQLException {
        PourSession p = new PourSession();
        p.setSessionId(rs.getInt("session_id"));
        p.setDeviceId(rs.getInt("device_id"));
        p.setUploadId(rs.getString("upload_id"));
        p.setUserId(rs.getInt("user_id"));
        p.setUsername(rs.getString("username"));
        p.setProfileId(rs.getInt("profile_id"));
        p.setTargetMl(rs.getDouble("target_ml"));
        p.setActualMl(rs.getDouble("actual_ml"));
        p.setDuration(rs.getDouble("duration_s"));
        p.setPeakFlow(rs.getDouble("peak_flow"));
        p.setAvgFlow(rs.getDouble("avg_flow"));
        p.setCupPresent(rs.getBoolean("cup_present"));
        p.setStartReason(rs.getString("start_reason"));
        p.setResultCode(rs.getString("result_code"));
        p.setStopReason(rs.getString("stop_reason"));
        p.setStartedAt(rs.getTimestamp("started_at"));
        p.setEndedAt(rs.getTimestamp("ended_at"));
        p.setTimeSource(rs.getString("time_source"));

        double risk = rs.getDouble("ml_risk_score");
        if (!rs.wasNull()) {
            p.setMlRiskScore(risk);
        }

        boolean mlEligible = rs.getBoolean("ml_eligible");
        if (!rs.wasNull()) {
            p.setMlEligible(mlEligible);
        }
        p.setMlExclusionReason(rs.getString("ml_exclusion_reason"));
        p.setCuratedResultCode(rs.getString("curated_result_code"));

        int curatedBy = rs.getInt("curated_by_user_id");
        if (!rs.wasNull()) {
            p.setCuratedByUserId(curatedBy);
        }
        Timestamp curatedAt = rs.getTimestamp("curated_at");
        if (curatedAt != null) {
            p.setCuratedAt(curatedAt);
        }
        p.setCuratedNote(rs.getString("curated_note"));
        return p;
    }

    private boolean hasValue(JsonObject json, String key) {
        return json != null && json.has(key) && !json.get(key).isJsonNull();
    }

    private int getInt(JsonObject json, String key, int defaultValue) {
        return hasValue(json, key) ? json.get(key).getAsInt() : defaultValue;
    }

    private double getDouble(JsonObject json, String key, double defaultValue) {
        return hasValue(json, key) ? json.get(key).getAsDouble() : defaultValue;
    }

    private boolean getBoolean(JsonObject json, String key, boolean defaultValue) {
        return hasValue(json, key) ? json.get(key).getAsBoolean() : defaultValue;
    }

    private String getString(JsonObject json, String key, String defaultValue) {
        return hasValue(json, key) ? json.get(key).getAsString() : defaultValue;
    }

    private String deriveResultCodeFromStopReason(String stopReason) {
        String normalized = stopReason == null ? "AUTO_PROFILE" : stopReason.trim().toUpperCase();
        switch (normalized) {
            case "TIMEOUT_FAILSAFE":
                return "TIMEOUT";
            case "ERROR_ABORT":
                return "ERROR";
            case "MANUAL_BUTTON":
                return "UNDER_POUR";
            case "AUTO_PROFILE":
            default:
                return "SUCCESS";
        }
    }
}
