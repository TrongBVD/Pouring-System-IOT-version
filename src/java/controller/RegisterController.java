package controller;

import dao.UserDAO;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "RegisterController", urlPatterns = {"/RegisterController"})
public class RegisterController extends HttpServlet {

    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        String u = request.getParameter("username");
        String p = request.getParameter("password");
        UserDAO dao = new UserDAO();

        // ĐÃ FIX: Truyền thẳng "OPERATOR" thay vì null
        if (dao.createAccount(u, p, "OPERATOR", null)) {
            request.setAttribute("success", "Registration successful! Please log in with the Operator role.");
            request.getRequestDispatcher("login.jsp").forward(request, response);
        } else {
            request.setAttribute("error", "Username already exists or a system error occurred.");
            request.getRequestDispatcher("register.jsp").forward(request, response);
        }
    }
}
