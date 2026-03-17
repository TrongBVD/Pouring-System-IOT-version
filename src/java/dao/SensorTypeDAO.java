package dao;

import java.sql.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import utils.DBContext;

public class SensorTypeDAO {

    public List<Map<String, Object>> getAllSensorTypes() {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT * FROM SensorType ORDER BY sensor_type_id DESC";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> map = new HashMap<>();
                map.put("id", rs.getInt("sensor_type_id"));

                // ĐÃ SỬA: Map với tên cột mới là "sensor_name"
                map.put("name", rs.getString("sensor_name"));

                map.put("unit", rs.getString("unit"));
                list.add(map);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    public boolean addSensorType(String name, String unit) {
        // ĐÃ SỬA: Lệnh INSERT sử dụng cột "sensor_name"
        String sql = "INSERT INTO SensorType (sensor_name, unit) VALUES (?, ?)";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, name);
            ps.setString(2, unit);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            return false;
        }
    }

    public boolean deleteSensorType(int id) {
        // Lưu ý: Nếu Sensor đang được dùng ở Calibration hay SensorLog thì không xóa được (Foreign Key)
        String sql = "DELETE FROM SensorType WHERE sensor_type_id = ?";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            return false;
        }
    }
}
