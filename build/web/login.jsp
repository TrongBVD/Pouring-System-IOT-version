<%-- File: login.jsp --%>
<%@page import="javax.servlet.http.HttpSession"%>
<%
    // BẪY SESSION: Hủy session ngay khi vào trang Login để ngăn nút Next
    HttpSession currentSession = request.getSession(false);
    if (currentSession != null && currentSession.getAttribute("LOGIN_USER") != null) {
        currentSession.invalidate();
    }
%>
<%@page contentType="text/html" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Smart Water - Login</title>
        <link rel="stylesheet" href="css/style.css">
    </head>
    <body>
        <div class="login-wrapper">
            <div class="form-box">
                <h2 style="color: #2c3e50;">Smart Water Audit</h2>

                <%-- HỨNG LỖI TỪ URL --%>
                <%
                    String err = request.getParameter("error");
                    String sts = request.getParameter("status");
                    if ("invalid".equals(err)) { %> <p style="color:red; font-weight:bold;">Invalid username or password!</p> <% }
                        if ("locked".equals(err)) { %> <p style="color:#e67e22; font-weight:bold;">Account has been TEMPORARILY LOCKED!</p> <% }
                        if ("disabled".equals(err)) { %> <p style="color:#c0392b; font-weight:bold;">Account has been DISABLED!</p> <% }
                        if ("registered".equals(sts)) { %> <p style="color:green; font-weight:bold;">Registration successful! Please log in.</p> <% }
                %>

                <form action="LoginController" method="POST">
                    <input type="hidden" name="action" value="normal_login">
                    <div class="form-group">
                        <label>Role</label>
                        <select name="role" class="form-control">
                            <option value="OPERATOR">Operator</option>
                            <option value="ADMIN">Admin</option>
                            <option value="TECHNICIAN">Technician</option>
                            <option value="AUDITOR">Auditor</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Username</label>
                        <input type="text" name="username" required class="form-control">
                    </div>
                    <div class="form-group">
                        <label>Password</label>
                        <input type="password" name="password" required class="form-control">
                    </div>
                    <button type="submit" class="btn btn-primary">Login</button>
                </form>

                <form action="LoginController" method="POST" style="margin-top: 15px;">
                    <input type="hidden" name="action" value="guest_login">
                    <button type="submit" class="btn btn-secondary">Continue with no account</button>
                </form>
                <br>
                <a href="register.jsp">Create Operator Account</a>
            </div>
        </div>
    </body>
</html>