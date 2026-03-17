package dao;

import utils.DBContext;
import java.sql.*;

public class SystemConfigDAO {

    public boolean isMaintenanceMode() throws SQLException, ClassNotFoundException {
        String sql = "SELECT config_value FROM SystemConfig WHERE config_key = 'MAINTENANCE_MODE'";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                return "ON".equalsIgnoreCase(rs.getString("config_value"));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return false; // Mặc định là không bảo trì nếu lỗi
    }
}
