package controller;

import dao.SensorTypeDAO;
import model.User;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "SensorTypeController", urlPatterns = {"/SensorTypeController"})
public class SensorTypeController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");
        // CHỈ ADMIN ĐƯỢC VÀO TRANG NÀY
        if (user == null || !"ADMIN".equals(user.getRole())) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        SensorTypeDAO dao = new SensorTypeDAO();
        request.setAttribute("SENSORS", dao.getAllSensorTypes());
        request.getRequestDispatcher("sensor_types.jsp").forward(request, response);
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");
        if (user == null || !"ADMIN".equals(user.getRole())) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        String action = request.getParameter("action");
        SensorTypeDAO dao = new SensorTypeDAO();

        if ("add".equals(action)) {
            String name = request.getParameter("name");
            String unit = request.getParameter("unit");
            if (dao.addSensorType(name, unit)) {
                response.sendRedirect("SensorTypeController?msg=Added successfully");
            } else {
                response.sendRedirect("SensorTypeController?error=Add failed (Duplicate name)");
            }
        } else if ("delete".equals(action)) {
            int id = Integer.parseInt(request.getParameter("id"));
            if (dao.deleteSensorType(id)) {
                response.sendRedirect("SensorTypeController?msg=Deleted successfully");
            } else {
                response.sendRedirect("SensorTypeController?error=Cannot delete (Currently in use by the device)");
            }
        }
    }
}
