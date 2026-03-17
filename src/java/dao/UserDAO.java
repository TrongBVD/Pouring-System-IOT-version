package dao;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import model.User;
import utils.DBContext;
import utils.SecurityUtils;

public class UserDAO {

    public User authenticate(String username, String rawPass, String role) {
        User user = null;
        String sql = "SELECT u.user_id, u.username, u.status, r.role_id, r.role_name FROM Users u "
                + "JOIN UserRole ur ON u.user_id = ur.user_id JOIN Roles r ON ur.role_id = r.role_id "
                + "WHERE u.username = ? AND u.password_hash = ? AND r.role_name = ? AND ur.revoked_at IS NULL";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, username);
            ps.setString(2, SecurityUtils.hashPasswordSHA256(rawPass));
            ps.setString(3, role);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                // ĐÃ FIX: Trả về đối tượng User bất kể trạng thái để Controller tự kiểm tra hiển thị lỗi
                user = new User(rs.getInt("user_id"), rs.getString("username"), rs.getString("status"), rs.getString("role_name"));
                loadPermissions(conn, user, rs.getInt("role_id"));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return user;
    }

    public User getAnonymousGuest() {
        User user = null;
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement("SELECT u.user_id, u.username, u.status, r.role_id, r.role_name FROM Users u JOIN UserRole ur ON u.user_id=ur.user_id JOIN Roles r ON ur.role_id=r.role_id WHERE u.username = 'anonymous'")) {
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                user = new User(rs.getInt("user_id"), rs.getString("username"), rs.getString("status"), "GUEST");
                loadPermissions(conn, user, rs.getInt("role_id"));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return user;
    }

    private void loadPermissions(Connection conn, User user, int roleId) throws SQLException {
        String sql = "SELECT p.module, p.action FROM Permissions p JOIN RolePerm rp ON p.permission_id = rp.permission_id WHERE rp.role_id = ?";
        try ( PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, roleId);
            ResultSet rs = ps.executeQuery();
            while (rs.next()) {
                user.addPermission(rs.getString("module"), rs.getString("action"));
            }
        }
    }

    public boolean createAccount(String username, String rawPass, String requestedRole, User actorUser) {
        String passHash = SecurityUtils.hashPasswordSHA256(rawPass);
        int actorId;
        String actorRole;
        String finalRoleToAssign;

        if (actorUser != null) {
            actorId = actorUser.getUserId();
            actorRole = actorUser.getRole();
            if ("TECH".equalsIgnoreCase(requestedRole)) {
                finalRoleToAssign = "TECHNICIAN";
            } else {
                finalRoleToAssign = (requestedRole != null) ? requestedRole.toUpperCase() : "GUEST";
            }
        } else {
            actorId = 2; // SYSTEM
            actorRole = "SYSTEM";
            // ĐÃ FIX: Mặc định đăng ký mới là OPERATOR thay vì GUEST
            finalRoleToAssign = (requestedRole != null) ? requestedRole.toUpperCase() : "OPERATOR";
        }

        try ( Connection conn = DBContext.getConnection()) {
            conn.setAutoCommit(false); // Bật transaction

            int newUserId = 0;
            // 1. Gọi User_Create (Đúng tên dbo.User_Create)
            String callUser = "{call User_Create(?, ?, ?, ?, ?, ?)}";
            try ( CallableStatement cs = conn.prepareCall(callUser)) {
                cs.setString(1, username);
                cs.setString(2, passHash);
                cs.setString(3, "ACTIVE");
                cs.setInt(4, actorId);
                cs.setString(5, actorRole);
                cs.registerOutParameter(6, Types.INTEGER);
                cs.execute();
                newUserId = cs.getInt(6);
            }

            if (newUserId > 0) {
                // 2. Gọi Role_Assign (SỬA TÊN Ở ĐÂY)
                String callRole = "{call Role_Assign(?, ?, ?, ?)}";
                try ( CallableStatement cs = conn.prepareCall(callRole)) {
                    cs.setInt(1, newUserId);
                    cs.setString(2, finalRoleToAssign);
                    cs.setInt(3, actorId);
                    cs.setString(4, actorRole);
                    cs.execute();
                }
                conn.commit(); // Thành công cả 2 thì mới lưu
                return true;
            }
        } catch (Exception e) {
            // Rollback nếu cần hoặc in lỗi
            e.printStackTrace();
        }
        return false;
    }

    public boolean checkUsernameExists(String username) {
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement("SELECT 1 FROM Users WHERE username=?")) {
            ps.setString(1, username);
            return ps.executeQuery().next();
        } catch (Exception e) {
            return true;
        }
    }

    public List<User> getAllUsers() {
        List<User> list = new ArrayList<>();
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement("SELECT u.user_id, u.username, u.status, r.role_name FROM Users u JOIN UserRole ur ON u.user_id=ur.user_id JOIN Roles r ON ur.role_id=r.role_id WHERE ur.revoked_at IS NULL AND u.username NOT IN ('guest','anonymous', 'SYSTEM')")) {
            ResultSet rs = ps.executeQuery();
            while (rs.next()) {
                list.add(new User(rs.getInt("user_id"), rs.getString("username"), rs.getString("status"), rs.getString("role_name")));
            }
        } catch (Exception e) {
        }
        return list;
    }

    public void updateUserStatus(int uid, String status, User actor) {
        String sql = "{call User_UpdateStatus(?, ?, ?, ?)}";
        try ( Connection conn = DBContext.getConnection();  CallableStatement cs = conn.prepareCall(sql)) {
            cs.setInt(1, uid);
            cs.setString(2, status);
            cs.setInt(3, actor.getUserId());
            cs.setString(4, actor.getRole());
            cs.execute();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
