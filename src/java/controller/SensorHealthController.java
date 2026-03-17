package controller;

import model.User;
import utils.DBContext;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "SensorHealthController", urlPatterns = {"/SensorHealthController"})
public class SensorHealthController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");
        if (user == null || "GUEST".equals(user.getRole()) || "OPERATOR".equals(user.getRole())) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        List<Map<String, Object>> logs = new ArrayList<>();
        String sql = "SELECT TOP 100 sl.log_id, sl.device_id, st.sensor_name, st.unit AS sensor_unit, "
                + "sl.measured_value, sl.recorded_at, slm.filtered_value "
                + "FROM SensorLog sl "
                + "JOIN SensorType st ON st.sensor_type_id = sl.sensor_type_id "
                + "LEFT JOIN SensorLogMeta slm ON slm.log_id = sl.log_id "
                + "WHERE sl.session_id IS NULL "
                + "ORDER BY sl.recorded_at DESC";

        try ( Connection conn = DBContext.getConnection();  PreparedStatement ps = conn.prepareStatement(sql);  ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> map = new HashMap<>();
                map.put("log_id", rs.getLong("log_id"));
                map.put("device_id", rs.getInt("device_id"));
                map.put("sensor_name", rs.getString("sensor_name"));
                map.put("sensor_unit", rs.getString("sensor_unit"));
                Object filtered = rs.getObject("filtered_value");
                map.put("calibrated_value", filtered != null ? filtered : rs.getDouble("measured_value"));
                map.put("recorded_at", rs.getTimestamp("recorded_at"));
                logs.add(map);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        request.setAttribute("HEALTH_LOGS", logs);
        request.getRequestDispatcher("sensor_health.jsp").forward(request, response);
    }
}
