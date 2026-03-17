package controller;

import dao.UserDAO;
import model.User;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.*;

@WebServlet(name = "LoginController", urlPatterns = {"/LoginController"})
public class LoginController extends HttpServlet {

    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        String action = request.getParameter("action");
        UserDAO dao = new UserDAO();
        HttpSession session = request.getSession();
        User user = null;

        if ("guest_login".equals(action)) {
            user = dao.getAnonymousGuest();
        } else {
            user = dao.authenticate(request.getParameter("username"), request.getParameter("password"), request.getParameter("role"));
        }

        if (user != null) {
            // ĐÃ FIX: Điều hướng theo đúng trạng thái tài khoản
            if ("LOCKED".equals(user.getStatus())) {
                response.sendRedirect("login.jsp?error=locked");
            } else if ("DISABLED".equals(user.getStatus())) {
                response.sendRedirect("login.jsp?error=disabled");
            } else {
                session.setAttribute("LOGIN_USER", user);
                response.sendRedirect("DashboardController");
            }
        } else {
            response.sendRedirect("login.jsp?error=invalid");
        }
    }
}
