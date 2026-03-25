<%@page contentType="text/html" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Smart Water System - Register</title>
        <style>
            body {
                font-family: sans-serif;
                background-color: #f0f2f5;
                height: 100vh;
                display: flex;
                justify-content: center;
                align-items: center;
                margin: 0;
            }
            .login-box {
                background: white;
                padding: 40px;
                border-radius: 10px;
                box-shadow: 0 4px 15px rgba(0,0,0,0.1);
                width: 350px;
                text-align: center;
            }
            .login-box h2 {
                color: #333;
                margin-bottom: 20px;
            }
            .input-group {
                margin-bottom: 15px;
                text-align: left;
            }
            .input-group label {
                display: block;
                margin-bottom: 5px;
                color: #666;
                font-size: 14px;
            }
            .input-group input {
                width: 100%;
                padding: 10px;
                box-sizing: border-box;
                border: 1px solid #ccc;
                border-radius: 5px;
                font-size: 16px;
            }
            .btn {
                width: 100%;
                padding: 12px;
                border: none;
                border-radius: 5px;
                font-size: 16px;
                cursor: pointer;
                transition: 0.3s;
                margin-bottom: 10px;
                font-weight: bold;
            }
            .btn-success {
                background-color: #28a745;
                color: white;
            }
            .btn-success:hover {
                background-color: #218838;
            }
            .error {
                color: red;
                margin-bottom: 15px;
                font-size: 14px;
            }
            .link {
                font-size: 14px;
                text-decoration: none;
                color: #007bff;
            }
        </style>
    </head>
    <body>
        <div class="login-box">
            <h2>Register Operator</h2>

            <% if (request.getAttribute("error") != null) {%>
            <div class="error"><%= request.getAttribute("error")%></div>
            <% }%>

            <form action="RegisterController" method="POST">
                <div class="input-group">
                    <label>Username</label>
                    <input type="text" name="username" required>
                </div>
                <div class="input-group">
                    <label>Password</label>
                    <input type="password" name="password" required>
                </div>
                <div class="input-group">
                    <label>Confirm Password</label>
                    <input type="password" name="confirm_password" required>
                </div>
                <button type="submit" class="btn btn-success">Create Account</button>
            </form>
            <div style="margin-top: 15px;">
                <a href="login.jsp" class="link">Back to Login</a>
            </div>
        </div>
    </body>
</html>