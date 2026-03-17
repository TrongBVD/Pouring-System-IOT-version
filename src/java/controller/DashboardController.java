package controller;

import dao.AlertDAO;
import dao.DeviceDAO;
import model.Device;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "DashboardController", urlPatterns = {"/DashboardController"})
public class DashboardController extends HttpServlet {

    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        if (request.getSession().getAttribute("LOGIN_USER") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        DeviceDAO dao = new DeviceDAO();
        Device device = dao.getDeviceInfo();

        request.setAttribute("DEVICE", device);

        AlertDAO alertDao = new AlertDAO();
        int activeAlertCount = alertDao.countActiveAlerts();
        request.setAttribute("ACTIVE_ALERT_COUNT", activeAlertCount);

        request.getRequestDispatcher("dashboard.jsp").forward(request, response);
    }
}
