<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Maintenance History</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            .log-container {
                margin: 20px auto;
                width: 95%;
                background: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            table {
                width: 100%;
                border-collapse: collapse;
                font-family: sans-serif;
            }
            th, td {
                padding: 12px;
                border-bottom: 1px solid #ddd;
                text-align: left;
            }
            th {
                background: #f8f9fa;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>Maintenance History</h2>
            <div class="device-stats">
                <a href="MaintenanceController" style="color: #f1c40f; text-decoration: none; margin-right: 15px; font-weight: bold;">⚠️ Back to Active Alerts</a>
                <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
            </div>
        </div>

        <div class="log-container">
            <table>
                <thead><tr><th>Ticket ID</th><th>Device</th><th>Issue Type</th><th>Action</th><th>Note</th><th>Technician</th><th>Closed At</th></tr></thead>
                <tbody>
                <c:forEach var="m" items="${MAINTENANCE_HISTORY}">
                    <tr>
                        <td>#${m.ticketId}</td>
                        <td>Device ${m.deviceId}</td>
                        <td><span class="status-badge st-LOCKED">${m.type}</span></td>
                        <td><strong>${m.action}</strong></td>
                        <td>${m.note}</td>
                        <td>${m.techName}</td>
                        <td>${m.closedAt}</td>
                    </tr>
                </c:forEach>
                </tbody>
            </table>
        </div>
    </body>
</html>