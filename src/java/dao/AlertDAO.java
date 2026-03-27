package dao;

import java.sql.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import model.User;
import utils.DBContext;

public class AlertDAO {

    // 1. Đếm số lượng lỗi chưa xử lý (để hiện chấm đỏ trên Menu)
    public int countActiveAlerts() {
        int count = 0;
        String sql = "SELECT COUNT(*) FROM Alert WHERE status IN ('OPEN', 'IN_PROGRESS')";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                count = rs.getInt(1);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return count;
    }

    // 2. Lấy danh sách các lỗi chưa xử lý
    public List<Map<String, Object>> getActiveAlerts() {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT a.alert_id, a.device_id, a.session_id, a.alert_type, a.risk_score, a.created_at, ae.summary_text "
                + "FROM Alert a LEFT JOIN AlertEvidence ae ON a.alert_id = ae.alert_id AND ae.evidence_type = 'RULE' "
                + "WHERE a.status IN ('OPEN', 'IN_PROGRESS') ORDER BY a.created_at DESC";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, Object> map = new HashMap<>();
                map.put("alertId", rs.getInt("alert_id"));
                map.put("deviceId", rs.getInt("device_id"));
                map.put("sessionId", rs.getInt("session_id"));
                map.put("alertType", rs.getString("alert_type"));
                map.put("riskScore", rs.getDouble("risk_score"));
                map.put("createdAt", rs.getTimestamp("created_at"));
                map.put("summary", rs.getString("summary_text"));
                list.add(map);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    // 3. Lấy toàn bộ lịch sử bảo trì
    public List<Map<String, Object>> getMaintenanceHistory() {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT m.ticket_id, m.device_id, m.ticket_type, m.note, m.status, m.opened_at, m.closed_at, "
                + "ml.action_code, u.username as tech_name "
                + "FROM MaintenanceTicket m "
                + "LEFT JOIN MaintenanceLog ml ON m.ticket_id = ml.ticket_id "
                + "LEFT JOIN Users u ON ml.technician_id = u.user_id "
                + "ORDER BY m.opened_at DESC";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, Object> map = new HashMap<>();
                map.put("ticketId", rs.getInt("ticket_id"));
                map.put("deviceId", rs.getInt("device_id"));
                map.put("type", rs.getString("ticket_type"));
                map.put("note", rs.getString("note"));
                map.put("status", rs.getString("status"));
                map.put("openedAt", rs.getTimestamp("opened_at"));
                map.put("closedAt", rs.getTimestamp("closed_at"));
                map.put("action", rs.getString("action_code"));
                map.put("techName", rs.getString("tech_name"));
                list.add(map);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    // 4. Xử lý lỗi (Resolve Alert) - đi qua stored procedure có audit
    public boolean resolveAlert(int alertId, int deviceId, String ticketType, String actionCode, String note, User actor) {
        String sql = "{call dbo.Alert_Resolve_Maintenance(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}";

        if (actor == null) {
            return false;
        }

        try ( Connection conn = DBContext.getConnection();  CallableStatement cs = conn.prepareCall(sql)) {

            String actorRole = actor.getRole() == null ? "UNKNOWN" : actor.getRole().trim().toUpperCase();
            String safeTicketType = ticketType == null ? null : ticketType.trim().toUpperCase();
            String safeActionCode = actionCode == null ? null : actionCode.trim().toUpperCase();
            String safeTicketNote = (note == null || note.trim().isEmpty()) ? null : note.trim();
            String safeLogNote = "Alert #" + alertId + " resolved"
                    + (safeTicketNote != null ? ". " + safeTicketNote : "");

            // Input params
            cs.setInt(1, alertId);                 // @alert_id
            cs.setInt(2, deviceId);                // @device_id
            cs.setString(3, safeTicketType);       // @ticket_type
            cs.setString(4, safeActionCode);       // @action_code
            cs.setString(5, safeTicketNote);       // @ticket_note
            cs.setString(6, safeLogNote);          // @log_note
            cs.setInt(7, actor.getUserId());       // @actor_user_id
            cs.setString(8, actorRole);            // @actor_role_name

            // @evidence_id = NULL
            cs.setNull(9, Types.INTEGER);

            // Output params
            cs.registerOutParameter(10, Types.INTEGER);  // @new_ticket_id
            cs.registerOutParameter(11, Types.INTEGER);  // @new_maintenance_log_id
            cs.registerOutParameter(12, Types.INTEGER);  // @audit_id
            cs.registerOutParameter(13, Types.CHAR);     // @chain_hash

            cs.execute();

            int newTicketId = cs.getInt(10);
            int newMaintenanceLogId = cs.getInt(11);
            int auditId = cs.getInt(12);
            String chainHash = cs.getString(13);

            System.out.println("Maintenance resolved via proc:"
                    + " alertId=" + alertId
                    + ", ticketId=" + newTicketId
                    + ", maintenanceLogId=" + newMaintenanceLogId
                    + ", auditId=" + auditId
                    + ", chainHash=" + chainHash);

            return true;

        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }
}
