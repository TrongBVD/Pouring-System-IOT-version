package dao;

import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import model.Device;
import model.User;
import utils.DBContext;

public class DeviceDAO {

    public String getDeviceStatus(int deviceId) {
        String sql = "SELECT status FROM Device WHERE device_id = ?";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, deviceId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                return rs.getString("status");
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return "OFFLINE";
    }

    public int getActiveCalibrationId(int deviceId) {
        String sql = "SELECT TOP 1 calib_id FROM Calibration WHERE device_id = ? AND valid_to IS NULL ORDER BY valid_from DESC";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, deviceId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                return rs.getInt("calib_id");
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return 1;
    }

    public int getDefaultProfileId() {
        String sql = "SELECT TOP 1 profile_id FROM PourProfile";
        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                return rs.getInt("profile_id");
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return 1;
    }

    public Device getDeviceInfo() {
        Device device = new Device();
        String sql = "SELECT TOP 1 d.device_id, d.location, d.firmware_ver, d.status, p.target_ml "
                + "FROM Device d CROSS JOIN (SELECT TOP 1 target_ml FROM PourProfile) p "
                + "WHERE d.device_id = 1";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql)) {
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                device.setDeviceId(rs.getInt("device_id"));
                device.setLocation(rs.getString("location"));
                device.setFirmwareVer(rs.getString("firmware_ver"));
                device.setStatus(rs.getString("status"));
                device.setTargetMl(rs.getInt("target_ml"));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return device;
    }

    // =========================================================================
    // HÀM MỚI: Cập nhật trạng thái máy và gọi Stored Procedure để ghi Audit Log
    // =========================================================================
    public void updateDeviceStatus(int deviceId, String status, User actor) {
        String sql = "{call Device_UpdateStatus_User(?, ?, ?, ?, ?, ?, ?)}";
        try ( Connection conn = DBContext.getConnection();  CallableStatement cs = conn.prepareCall(sql)) {
            cs.setInt(1, deviceId);
            cs.setString(2, status);
            cs.setInt(3, actor.getUserId());
            cs.setString(4, actor.getRole());
            cs.setNull(5, java.sql.Types.NVARCHAR); // Lý do (reason) - Không bắt buộc

            // 2 biến OUTPUT bắt buộc của Procedure Audit (id và chuỗi băm)
            cs.registerOutParameter(6, java.sql.Types.INTEGER);
            cs.registerOutParameter(7, java.sql.Types.CHAR);

            cs.execute();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
