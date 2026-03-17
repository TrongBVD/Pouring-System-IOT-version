package controller;

import dao.LogDAO;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import model.User;

@WebServlet(name = "PourSessionMetaController", urlPatterns = {"/PourSessionMetaController"})
public class PourSessionMetaController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        User user = (User) request.getSession().getAttribute("LOGIN_USER");
        if (user == null || "GUEST".equals(user.getRole()) || "OPERATOR".equals(user.getRole())) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        LogDAO logDao = new LogDAO();
        request.setAttribute("POUR_SESSION_META_LIST", logDao.getPourSessionMetaList());
        request.getRequestDispatcher("pour_session_meta.jsp").forward(request, response);
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        request.setCharacterEncoding("UTF-8");
        User user = (User) request.getSession().getAttribute("LOGIN_USER");
        if (user == null || "AUDITOR".equals(user.getRole()) || "GUEST".equals(user.getRole()) || "OPERATOR".equals(user.getRole())) {
            response.sendRedirect("DashboardController?error=permission_denied");
            return;
        }

        String action = request.getParameter("action");
        if (!"update_meta".equals(action)) {
            response.sendRedirect("PourSessionMetaController?error=invalid_action");
            return;
        }

        int sessionId = Integer.parseInt(request.getParameter("session_id"));
        String mlEligibleRaw = trimToNull(request.getParameter("ml_eligible"));
        String mlExclusionReason = trimToNull(request.getParameter("ml_exclusion_reason"));
        String curatedResultCode = trimToNull(request.getParameter("curated_result_code"));
        String curatedNote = trimToNull(request.getParameter("curated_note"));

        Boolean mlEligible = null;
        if (mlEligibleRaw != null) {
            mlEligible = "1".equals(mlEligibleRaw) || "true".equalsIgnoreCase(mlEligibleRaw);
        }

        if (Boolean.TRUE.equals(mlEligible)) {
            mlExclusionReason = null;
        }

        LogDAO logDao = new LogDAO();
        boolean success = logDao.updatePourSessionMeta(sessionId, mlEligible, mlExclusionReason, curatedResultCode, curatedNote, user);

        if (success) {
            response.sendRedirect("PourSessionMetaController?msg=updated");
        } else {
            response.sendRedirect("PourSessionMetaController?error=update_failed");
        }
    }

    private String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String v = value.trim();
        return v.isEmpty() ? null : v;
    }
}
