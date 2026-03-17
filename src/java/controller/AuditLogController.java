package controller;

import dao.ReportDAO;
import model.User;
import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;

@WebServlet(name = "AuditLogController", urlPatterns = {"/AuditLogController"})
public class AuditLogController extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession();
        User currentUser = (User) session.getAttribute("LOGIN_USER");

        if (currentUser == null || (!"ADMIN".equals(currentUser.getRole()) && !"AUDITOR".equals(currentUser.getRole()))) {
            response.sendError(HttpServletResponse.SC_FORBIDDEN, "Access Denied: You do not have permission to view Audit Logs.");
            return;
        }

        // Lấy thông báo kết quả Verify (nếu có) từ Session chuyển sang Request
        String verifyResult = (String) session.getAttribute("VERIFY_RESULT");
        if (verifyResult != null) {
            request.setAttribute("VERIFY_RESULT", verifyResult);
            session.removeAttribute("VERIFY_RESULT"); // PRG Pattern: Hiện 1 lần rồi xóa
        }

        ReportDAO reportDAO = new ReportDAO();
        request.setAttribute("AUDIT_LOGS", reportDAO.getFullAuditLogs());
        request.getRequestDispatcher("audit_logs.jsp").forward(request, response);
    }

    // HÀM MỚI: Bắt sự kiện bấm nút Verify Integrity
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        // ĐÃ FIX: THÊM KIỂM TRA QUYỀN BẢO MẬT Ở TẦNG POST
        HttpSession session = request.getSession();
        User currentUser = (User) session.getAttribute("LOGIN_USER");

        if (currentUser == null || (!"ADMIN".equals(currentUser.getRole()) && !"AUDITOR".equals(currentUser.getRole()))) {
            response.sendError(HttpServletResponse.SC_FORBIDDEN, "Access Denied: Cannot perform actions.");
            return;
        }

        String action = request.getParameter("action");

        if ("verify".equals(action)) {
            ReportDAO reportDAO = new ReportDAO();
            String result = reportDAO.verifyAuditIntegrity();
            session.setAttribute("VERIFY_RESULT", result);
        }

        response.sendRedirect("AuditLogController");
    }
}
