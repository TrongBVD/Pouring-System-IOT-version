package controller;

import dao.UserDAO;
import model.User;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;

@WebServlet(name = "UserManageController", urlPatterns = {"/UserManageController"})
public class UserManageController extends HttpServlet {

    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession();
        User adminUser = (User) session.getAttribute("LOGIN_USER");

        if (adminUser == null || !"ADMIN".equals(adminUser.getRole())) {
            response.sendError(HttpServletResponse.SC_FORBIDDEN, "You do not have permission to perform this function.");
            return;
        }

        String action = request.getParameter("action");
        UserDAO dao = new UserDAO();

        if ("create_staff".equals(action)) {
            String newUser = request.getParameter("new_username");
            String newPass = request.getParameter("new_password");
            String targetRole = request.getParameter("target_role");

            if (dao.checkUsernameExists(newUser)) {
                request.setAttribute("error", "Username " + newUser + " already exists!");
                request.getRequestDispatcher("admin.jsp").forward(request, response);
                return;
            }

            // ĐÃ FIX: Truyền object adminUser vào
            boolean isCreated = dao.createAccount(newUser, newPass, targetRole, adminUser);

            if (isCreated) {
                request.setAttribute("success", "Successfully created " + targetRole + " account!");
            } else {
                request.setAttribute("error", "Error creating internal account.");
            }
            request.getRequestDispatcher("admin.jsp").forward(request, response);
        }
    }
}
