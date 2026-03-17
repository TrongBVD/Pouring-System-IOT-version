<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>User Management - Smart Water</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            /* CSS bảng như cũ... (giữ nguyên của bạn) */
            .table-container {
                background: white;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.05);
                overflow: hidden;
            }
            table {
                width: 100%;
                border-collapse: collapse;
            }
            th {
                background: #f8f9fa;
                color: #2c3e50;
                font-weight: 600;
                padding: 15px;
                text-align: left;
                border-bottom: 1px solid #eee;
            }
            td {
                padding: 15px;
                text-align: left;
                border-bottom: 1px solid #eee;
            }
            .action-btn {
                padding: 6px 12px;
                border-radius: 4px;
                border: none;
                cursor: pointer;
                font-size: 12px;
                font-weight: bold;
            }
            .btn-lock {
                background: #f1c40f;
                color: #fff;
            }
            .btn-disable {
                background: #e74c3c;
                color: #fff;
            }
            .btn-active {
                background: #2ecc71;
                color: #fff;
            }
            .status-badge {
                display: inline-block;
                padding: 4px 8px;
                border-radius: 12px;
                font-size: 11px;
                font-weight: bold;
            }
            .st-ACTIVE {
                background: #d4edda;
                color: #155724;
            }
            .st-LOCKED {
                background: #fff3cd;
                color: #856404;
            }
            .st-DISABLED {
                background: #f8d7da;
                color: #721c24;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>User Management</h2>
            <div class="device-stats">
                <span>Admin: <strong>${sessionScope.LOGIN_USER.username}</strong></span> | 
                <a href="DashboardController" style="color: #bdc3c7; text-decoration: none; margin-left: 10px;">Back to Dashboard</a>
            </div>
        </div>

        <div class="container" style="margin-top: 30px;">
            <div class="admin-panel" style="margin-bottom: 20px; max-width: 100%;">
                <h3>Create New Staff</h3>
                <form action="AdminController" method="POST">
                    <input type="hidden" name="action" value="create_internal_user">
                    <div class="admin-row">
                        <input type="text" name="new_user" placeholder="Username" class="form-control" style="flex: 2" required>
                        <input type="password" name="new_pass" placeholder="Password" class="form-control" style="flex: 2" required>
                        <select name="new_role" class="form-control" style="flex: 1" required>
                            <option value="" disabled selected>-- Select Role --</option>
                            <option value="ADMIN">Admin</option>
                            <option value="TECHNICIAN">Technician</option> 
                            <option value="AUDITOR">Auditor</option>
                            <option value="OPERATOR">Operator</option>
                        </select>
                        <button type="submit" class="btn btn-primary" style="width: auto; margin-top:0;">Create</button>
                    </div>
                    <c:if test="${not empty error}"><p style="color:red; margin-top:5px;">${error}</p></c:if>
                    <c:if test="${not empty success}"><p style="color:green; margin-top:5px;">${success}</p></c:if>
                    </form>
                </div>

                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>ID</th><th>Username</th><th>Role</th><th>Status</th><th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                        <c:forEach var="u" items="${USER_LIST}">
                            <tr>
                                <td>#${u.userId}</td>
                                <td><strong>${u.username}</strong></td>
                                <td>${u.role}</td>
                                <td><span class="status-badge st-${u.status}">${u.status}</span></td>
                                <td>
                                    <c:if test="${u.userId != sessionScope.LOGIN_USER.userId}">
                                        <form action="AdminController" method="POST" style="display:inline-block;">
                                            <input type="hidden" name="action" value="toggle_user">
                                            <input type="hidden" name="uid" value="${u.userId}">

                                            <c:choose>
                                                <c:when test="${u.status == 'ACTIVE'}">
                                                    <button name="status" value="LOCKED" class="action-btn btn-lock">Lock</button>
                                                    <button name="status" value="DISABLED" class="action-btn btn-disable">Disable</button>
                                                </c:when>
                                                <c:when test="${u.status == 'LOCKED'}">
                                                    <button name="status" value="ACTIVE" class="action-btn btn-active">Activate</button>
                                                    <button name="status" value="DISABLED" class="action-btn btn-disable">Disable</button>
                                                </c:when>
                                                <c:when test="${u.status == 'DISABLED'}">
                                                    <span style="color:#e74c3c; font-weight:bold; font-size:12px;">(Disabled)</span>
                                                </c:when>
                                            </c:choose>
                                        </form>
                                    </c:if>
                                    <c:if test="${u.userId == sessionScope.LOGIN_USER.userId}">
                                        <span style="color:#ccc; font-size:12px;">(You)</span>
                                    </c:if>
                                </td>
                            </tr>
                        </c:forEach>
                    </tbody>
                </table>
            </div>
        </div>
    </body>
</html>