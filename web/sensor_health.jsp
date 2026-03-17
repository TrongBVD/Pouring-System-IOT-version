<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Health Report</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            .log-container {
                margin: 20px auto;
                width: 90%;
                background: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            table {
                width: 100%;
                border-collapse: collapse;
                font-family: monospace;
                font-size: 14px;
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
            <h2>Sensor Health Logs (Updated every 5 minutes)</h2>
            <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
        </div>
        <div class="log-container">
            <table>
                <thead><tr><th>Log ID</th><th>Device ID</th><th>Sensor Type</th><th>Calibrated Value</th><th>Recorded At</th></tr></thead>
                <tbody>
                    <c:forEach var="h" items="${HEALTH_LOGS}">
                        <tr>
                            <td>#${h.log_id}</td>
                            <td>Device ${h.device_id}</td>
                            <td><strong>${h.sensor_name}</strong></td>
                            <td style="color:#2980b9; font-weight:bold;">${h.calibrated_value} ${h.sensor_unit}</td>
                            <td>${h.recorded_at}</td>
                        </tr>
                    </c:forEach>
                </tbody>
            </table>
        </div>
    </body>
</html>