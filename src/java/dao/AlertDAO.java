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

    // 4. Xử lý lỗi (Resolve Alert) - Đóng Alert và tạo Maintenance Ticket + Log
    public boolean resolveAlert(int alertId, int deviceId, String ticketType, String actionCode, String note, User actor) {
        String sqlAlert = "UPDATE Alert SET status = 'RESOLVED', resolved_at = SYSUTCDATETIME(), assigned_to = ? WHERE alert_id = ?";
        String sqlTicket = "INSERT INTO MaintenanceTicket (device_id, ticket_type, note, status, closed_at) VALUES (?, ?, ?, 'CLOSED', SYSUTCDATETIME())";
        String sqlLog = "INSERT INTO MaintenanceLog (ticket_id, technician_id, action_code, note) VALUES (?, ?, ?, ?)";

        try ( Connection conn = DBContext.getConnection()) {
            conn.setAutoCommit(false); // Bắt đầu Transaction

            try {
                // 1. Đóng Alert
                try ( PreparedStatement ps = conn.prepareStatement(sqlAlert)) {
                    ps.setInt(1, actor.getUserId());
                    ps.setInt(2, alertId);
                    ps.executeUpdate();
                }

                // 2. Tạo Ticket bảo trì
                int ticketId = -1;
                try ( PreparedStatement ps = conn.prepareStatement(sqlTicket, Statement.RETURN_GENERATED_KEYS)) {
                    ps.setInt(1, deviceId);
                    ps.setString(2, ticketType);
                    ps.setString(3, note);
                    ps.executeUpdate();
                    ResultSet rs = ps.getGeneratedKeys();
                    if (rs.next()) {
                        ticketId = rs.getInt(1);
                    }
                }

                // 3. Ghi Log chi tiết hành động
                if (ticketId != -1) {
                    try ( PreparedStatement ps = conn.prepareStatement(sqlLog)) {
                        ps.setInt(1, ticketId);
                        ps.setInt(2, actor.getUserId());
                        ps.setString(3, actionCode);
                        ps.setString(4, "Alert #" + alertId + " Resolved. " + note);
                        ps.executeUpdate();
                    }
                }

                conn.commit(); // Hoàn tất Transaction
                return true;
            } catch (SQLException ex) {
                conn.rollback();
                ex.printStackTrace();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }
}
