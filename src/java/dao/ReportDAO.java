package dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import model.AuditChainRow; // ĐÃ SỬA: Import đúng Model Blockchain
import utils.DBContext;

public class ReportDAO {

    // ĐÃ SỬA: Đổi kiểu trả về thành List<AuditChainRow>
    public List<AuditChainRow> getFullAuditLogs() {
        List<AuditChainRow> list = new ArrayList<>();

        // ĐÃ FIX: Dùng JOIN trực tiếp 2 bảng AuditLog và HashChain thay vì gọi View.
        // Đặt alias [timestamp] AS audit_timestamp_utc để khớp với getTimestamp bên dưới.
        String sql = "SELECT hc.anchor_id, al.audit_id, hc.prev_hash, hc.row_hash, hc.chain_hash, "
                + "al.[timestamp] AS audit_timestamp_utc, al.actor_user_id, al.actor_role_name, "
                + "al.action, al.object_type, al.object_id, al.diff_json "
                + "FROM dbo.AuditLog al "
                + "JOIN dbo.HashChain hc ON al.audit_id = hc.audit_id "
                + "ORDER BY al.audit_id DESC";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                AuditChainRow row = new AuditChainRow();

                row.setAnchorId(rs.getInt("anchor_id"));
                row.setAuditId(rs.getInt("audit_id"));
                row.setPrevHash(rs.getString("prev_hash"));
                row.setRowHash(rs.getString("row_hash"));
                row.setChainHash(rs.getString("chain_hash"));

                // Lấy Timestamp chuẩn
                java.sql.Timestamp ts = rs.getTimestamp("audit_timestamp_utc");
                if (ts != null) {
                    row.setAuditTimestampUtc(ts.toLocalDateTime());
                }

                row.setActorUserId(rs.getInt("actor_user_id"));
                row.setActorRoleName(rs.getString("actor_role_name"));
                row.setAction(rs.getString("action"));
                row.setObjectType(rs.getString("object_type"));
                row.setObjectId(rs.getInt("object_id"));

                // Xử lý Null cho diff_json
                String diff = rs.getString("diff_json");
                row.setDiffJson(diff != null ? diff : "<NULL>");

                list.add(row);
            }
        } catch (Exception e) {
            // Lời khuyên: Đừng chỉ in ra console, khi debug bạn có thể tạm ném lỗi ra ngoài 
            // để trên web hiện trang báo lỗi 500 kèm chi tiết, rất dễ fix!
            System.err.println("ERROR IN getFullAuditLogs: " + e.getMessage());
            e.printStackTrace();
        }
        return list;
    }

    // HÀM MỚI: QUÉT VÀ KIỂM TRA ĐỘ TOÀN VẸN CỦA DỮ LIỆU (Giữ nguyên của bạn)
    public String verifyAuditIntegrity() {
        String sql = "SELECT TOP 1 hc.audit_id "
                + "FROM dbo.HashChain hc JOIN dbo.AuditLog al ON hc.audit_id = al.audit_id "
                + "WHERE "
                + "hc.row_hash <> CONVERT(CHAR(64), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), "
                + "CAST(CONCAT('audit_id=', al.audit_id, '|', 'timestamp_utc=', CONVERT(NVARCHAR(33), al.[timestamp], 126), '|', "
                + "'actor_user_id=', al.actor_user_id, '|', 'actor_role=', al.actor_role_name, '|', "
                + "'action=', al.action, '|', 'object_type=', al.object_type, '|', 'object_id=', al.object_id, '|', "
                + "'diff=', COALESCE(al.diff_json, '<NULL>')) AS NVARCHAR(MAX)))), 2) "
                + "OR "
                + "hc.chain_hash <> CONVERT(CHAR(64), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), "
                + "CAST(CONCAT(COALESCE(hc.prev_hash, REPLICATE('0', 64)), '|', hc.row_hash) AS NVARCHAR(MAX)))), 2) "
                + "OR "
                + "(hc.prev_hash IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.HashChain prev WHERE prev.chain_hash = hc.prev_hash)) "
                + "ORDER BY hc.audit_id ASC";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                return "BROKEN_AT_ID_" + rs.getInt(1);
            }
            return "VALID";
        } catch (Exception e) {
            e.printStackTrace();
            return "ERROR";
        }
    }
}
