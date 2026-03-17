package controller;

import java.io.IOException;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;

@WebServlet(name = "LogoutController", urlPatterns = {"/LogoutController"})
public class LogoutController extends HttpServlet {

    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        // 1. Lấy session hiện tại
        HttpSession session = request.getSession(false);
        if (session != null) {
            session.invalidate(); // 2. Hủy session ngay lập tức (Xóa mọi dữ liệu server)
        }
        // 3. Chuyển về trang login
        response.sendRedirect("login.jsp");
    }
}
