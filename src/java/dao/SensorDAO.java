package dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Timestamp;
import utils.DBContext;

public class SensorDAO {

    public void saveSensorLog(int deviceId, int sessionId, int sensorTypeId, double value, Timestamp time) {
        String sql = "INSERT INTO SensorLog (device_id, session_id, sensor_type_id, measured_value, recorded_at) VALUES (?, ?, ?, ?, ?)";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, deviceId);
            ps.setInt(2, sessionId);
            ps.setInt(3, sensorTypeId);
            ps.setDouble(4, value);
            ps.setTimestamp(5, time);
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
