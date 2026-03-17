package controller;

import dao.DeviceDAO;
import dao.UserDAO;
import model.User;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "AdminController", urlPatterns = {"/AdminController"})
public class AdminController extends HttpServlet {

    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        request.setCharacterEncoding("UTF-8");
        User admin = (User) request.getSession().getAttribute("LOGIN_USER");

        if (admin == null || (!"ADMIN".equals(admin.getRole()) && !"TECHNICIAN".equals(admin.getRole()))) {
            response.sendRedirect("login.jsp");
            return;
        }

        String action = request.getParameter("action");
        DeviceDAO dDao = new DeviceDAO();
        UserDAO uDao = new UserDAO();

        if ("create_internal_user".equals(action) && "ADMIN".equals(admin.getRole())) {
            String newUser = request.getParameter("new_user");
            if (uDao.checkUsernameExists(newUser)) {
                request.setAttribute("error", "Username already exists!");
            } else {
                boolean ok = uDao.createAccount(newUser, request.getParameter("new_pass"), request.getParameter("new_role"), admin);
                if (ok) {
                    request.setAttribute("success", "User created successfully: " + newUser);
                } else {
                    request.setAttribute("error", "System error while creating user.");
                }
            }
            request.setAttribute("USER_LIST", uDao.getAllUsers());
            request.getRequestDispatcher("admin_users.jsp").forward(request, response);
            return;
        }

        if ("toggle_user".equals(action) && "ADMIN".equals(admin.getRole())) {
            int uid = Integer.parseInt(request.getParameter("uid"));
            String st = request.getParameter("status");
            uDao.updateUserStatus(uid, st, admin);
            response.sendRedirect("AdminController?view=users");
            return;
        }

        if ("update_status".equals(action) && ("ADMIN".equals(admin.getRole()) || "TECHNICIAN".equals(admin.getRole()))) {
            String newStatus = request.getParameter("device_status");
            if ("ACTIVE".equals(newStatus) || "MAINTENANCE".equals(newStatus)) {
                // 1. Cập nhật SQL (Giữ nguyên như cũ)
                dDao.updateDeviceStatus(1, newStatus, admin);
                
                // 2. Ép ESP32 khóa/mở ngay lập tức
                try {
                    URL url = new URL("http://192.168.4.1/set-status");
                    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                    conn.setRequestMethod("POST");
                    conn.setDoOutput(true);
                    conn.setConnectTimeout(2000);
                    conn.getOutputStream().write(("status=" + newStatus).getBytes("UTF-8"));
                    conn.getResponseCode();
                } catch (Exception e) {
                    System.out.println("Could not push status to ESP32 immediately. Will sync on next ping.");
                }

                response.sendRedirect("DashboardController?msg=success");
            } else {
                response.sendRedirect("DashboardController?error=Invalid Status");
            }
            return;
        }
    }

    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        String view = request.getParameter("view");

        if ("users".equals(view)) {
            UserDAO uDao = new UserDAO();
            request.setAttribute("USER_LIST", uDao.getAllUsers());
            request.getRequestDispatcher("admin_users.jsp").forward(request, response);
        } else {
            response.sendRedirect("DashboardController");
        }
    }
}
