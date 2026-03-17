package controller;

import dao.AlertDAO;
import model.User;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "MaintenanceController", urlPatterns = {"/MaintenanceController"})
public class MaintenanceController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");

        // CHỈ CHO PHÉP ADMIN VÀ TECHNICIAN TRUY CẬP (Đã chặn OPERATOR, GUEST, AUDITOR)
        if (user == null || (!"ADMIN".equals(user.getRole()) && !"TECHNICIAN".equals(user.getRole()))) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        String view = request.getParameter("view");
        AlertDAO dao = new AlertDAO();

        if ("history".equals(view)) {
            // Xem lịch sử bảo trì
            request.setAttribute("MAINTENANCE_HISTORY", dao.getMaintenanceHistory());
            request.getRequestDispatcher("maintenance_history.jsp").forward(request, response);
        } else {
            // Mặc định: Xem các lỗi đang Active (Cần sửa chữa)
            request.setAttribute("ACTIVE_ALERTS", dao.getActiveAlerts());
            request.getRequestDispatcher("active_alerts.jsp").forward(request, response);
        }
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");

        // CHỈ CHO PHÉP ADMIN VÀ TECHNICIAN SỬA LỖI
        if (user == null || (!"ADMIN".equals(user.getRole()) && !"TECHNICIAN".equals(user.getRole()))) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        String action = request.getParameter("action");
        if ("resolve_alert".equals(action)) {
            int alertId = Integer.parseInt(request.getParameter("alert_id"));
            int deviceId = Integer.parseInt(request.getParameter("device_id"));
            String ticketType = request.getParameter("ticket_type"); // CLEAN, FILTER, VALVE
            String actionCode = request.getParameter("action_code"); // INSPECTED, CLEANED...
            String note = request.getParameter("note");

            AlertDAO dao = new AlertDAO();
            if (dao.resolveAlert(alertId, deviceId, ticketType, actionCode, note, user)) {
                response.sendRedirect("MaintenanceController?msg=resolved");
            } else {
                response.sendRedirect("MaintenanceController?error=resolve_failed");
            }
        }
    }
}
