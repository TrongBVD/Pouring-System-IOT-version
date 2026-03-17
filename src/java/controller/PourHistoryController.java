package controller;

import dao.LogDAO;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import model.User;

@WebServlet(name = "PourHistoryController", urlPatterns = {"/PourHistoryController"})
public class PourHistoryController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");

        if (user == null || "GUEST".equals(user.getRole())) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        LogDAO logDao = new LogDAO();
        if ("OPERATOR".equals(user.getRole())) {
            request.setAttribute("POUR_HISTORY", logDao.getMyPourSession(user.getUserId()));
        } else {
            request.setAttribute("POUR_HISTORY", logDao.getPourHistory());
        }

        request.getRequestDispatcher("pour_history.jsp").forward(request, response);
    }
}
