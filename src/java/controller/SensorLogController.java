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

@WebServlet(name = "SensorLogController", urlPatterns = {"/SensorLogController"})
public class SensorLogController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");
        
        // CHỈ ADMIN, TECHNICIAN, AUDITOR MỚI ĐƯỢC XEM LOG
        if (user == null || (!"ADMIN".equals(user.getRole()) && !"TECHNICIAN".equals(user.getRole()) && !"AUDITOR".equals(user.getRole()))) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        List<Map<String, Object>> logs = new ArrayList<>();
        // Query TOP 500 records mới nhất, kết hợp Log Thô & Meta
        String sql = "SELECT TOP 500 sl.log_id, sl.device_id, sl.session_id, st.sensor_name, sl.measured_value, sl.recorded_at, " +
                     "slm.filtered_value, slm.is_outlier, slm.usable_for_alerting " +
                     "FROM SensorLog sl " +
                     "JOIN SensorType st ON sl.sensor_type_id = st.sensor_type_id " +
                     "LEFT JOIN SensorLogMeta slm ON sl.log_id = slm.log_id " +
                     "ORDER BY sl.recorded_at DESC";

        try (Connection conn = DBContext.getConnection(); PreparedStatement ps = conn.prepareStatement(sql); ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> map = new HashMap<>();
                map.put("log_id", rs.getLong("log_id"));
                map.put("device_id", rs.getInt("device_id"));
                map.put("session_id", rs.getInt("session_id"));
                map.put("sensor_name", rs.getString("sensor_name"));
                map.put("measured_value", rs.getDouble("measured_value"));
                map.put("recorded_at", rs.getTimestamp("recorded_at"));
                map.put("filtered_value", rs.getObject("filtered_value"));
                map.put("is_outlier", rs.getObject("is_outlier"));
                map.put("usable_for_alerting", rs.getObject("usable_for_alerting"));
                logs.add(map);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        request.setAttribute("SENSOR_LOGS", logs);
        request.getRequestDispatcher("sensor_logs.jsp").forward(request, response);
    }
}