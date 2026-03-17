<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>User Management</title>
        <link rel="stylesheet" href="css/style.css">
    </head>
    <body>
        <div class="banner">
            <h2>User Management</h2>
            <a href="DashboardController" style="color:white">Back to Dashboard</a>
        </div>  
        <div class="container">
            <div class="admin-panel" style="max-width: 100%;">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Username</th>
                            <th>Role</th>
                            <th>Status</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody>
                    <c:forEach var="u" items="${USER_LIST}">
                        <tr>
                            <td>${u.userId}</td>
                            <td>${u.username}</td>
                            <td>${u.role}</td>
                            <td><span class="status-badge status-${u.status == 'ACTIVE' ? 'ACTIVE' : 'ERROR'}">${u.status}</span></td>
                            <td>
                                <form action="AdminController" method="POST" style="display:inline;">
                                    <input type="hidden" name="action" value="toggle_user">
                                    <input type="hidden" name="uid" value="${u.userId}">
                                    <c:if test="${u.status == 'ACTIVE'}">
                                        <button name="status" value="LOCKED" class="btn btn-secondary" style="padding: 5px 10px; margin:0; font-size: 12px;">Lock</button>
                                        <button name="status" value="DISABLED" class="btn btn-secondary" style="padding: 5px 10px; margin:0; font-size: 12px; background:#e74c3c; color:white;">Disable</button>
                                    </c:if>
                                    <c:if test="${u.status != 'ACTIVE'}">
                                        <button name="status" value="ACTIVE" class="btn btn-primary" style="padding: 5px 10px; margin:0; font-size: 12px;">Activate</button>
                                    </c:if>
                                </form>
                            </td>
                        </tr>
                    </c:forEach>
                    </tbody>
                </table>
            </div>
        </div>
    </body>
</html>