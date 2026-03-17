package filter;

import java.io.IOException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import javax.servlet.Filter;
import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.annotation.WebFilter;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import utils.SecurityUtils;

@WebFilter(filterName = "SecurityFilter", urlPatterns = {"/*"})
public class SecurityFilter implements Filter {

    // Các đường dẫn public không cần login
    private static final List<String> PUBLIC_PATHS = Arrays.asList(
            "/login.jsp",
            "/register.jsp",
            "/LoginController",
            "/RegisterController",
            "/LogoutController"
    );

    // API cho ESP32
    private static final Set<String> DEVICE_API_PATHS = new HashSet<>(Arrays.asList(
            "/api/pour-session/batch",
            "/api/health"
    ));

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest req = (HttpServletRequest) request;
        HttpServletResponse res = (HttpServletResponse) response;

        // Xóa cache
        res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
        res.setHeader("Pragma", "no-cache");
        res.setDateHeader("Expires", 0);

        String path = req.getServletPath();
        HttpSession session = req.getSession(false);
        boolean isLoggedIn = (session != null && session.getAttribute("LOGIN_USER") != null);

        // 1) Static resources
        if (path.startsWith("/css/") || path.startsWith("/js/") || path.startsWith("/images/")) {
            chain.doFilter(request, response);
            return;
        }

        // 2) Cho ESP32 đi qua nếu gọi đúng API + có API key hợp lệ
        if (DEVICE_API_PATHS.contains(path)) {
            String apiKey = req.getHeader("X-API-Key");

            if (SecurityUtils.isValidDeviceApiKey(apiKey)) {
                chain.doFilter(request, response);
                return;
            } else {
                res.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                res.setContentType("text/plain;charset=UTF-8");
                res.getWriter().write("Invalid API key");
                return;
            }
        }

        // 3) Kiểm tra public page
        boolean isPublicPage = PUBLIC_PATHS.contains(path);

        // 4) Logic điều hướng
        if (!isPublicPage && !isLoggedIn) {
            res.sendRedirect(req.getContextPath() + "/login.jsp");
        } else if (isPublicPage && isLoggedIn && path.equals("/login.jsp")) {
            res.sendRedirect(req.getContextPath() + "/DashboardController");
        } else {
            chain.doFilter(request, response);
        }
    }

    @Override
    public void init(FilterConfig filterConfig) throws ServletException {
    }

    @Override
    public void destroy() {
    }
}
