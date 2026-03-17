<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Raw Sensor Logs & Meta</title>
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
                font-family: monospace;
                font-size: 13px;
            }
            th, td {
                padding: 10px;
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
            <h2>System Sensor Logs & Metadata (Top 500)</h2>
            <div class="device-stats">
                <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
            </div>
        </div>
        <div class="log-container">
            <table>
                <thead>
                    <tr>
                        <th>Log ID</th>
                        <th>Device</th>
                        <th>Session</th>
                        <th>Sensor Type</th>
                        <th>Measured (Raw)</th>
                        <th>Filtered (Meta)</th>
                        <th>Is Outlier</th>
                        <th>Usable ML/Alert</th>
                        <th>Recorded At</th>
                    </tr>
                </thead>
                <tbody>
                <c:forEach var="l" items="${SENSOR_LOGS}">
                    <tr>
                        <td>#${l.log_id}</td>
                        <td>D${l.device_id}</td>
                        <td>${l.session_id != 0 ? l.session_id : '-'}</td>
                        <td><strong>${l.sensor_name}</strong></td>
                        <td style="color:#e67e22; font-weight:bold;">${l.measured_value}</td>
                        <td style="color:#27ae60; font-weight:bold;">${l.filtered_value != null ? l.filtered_value : '-'}</td>
                        <td>
                    <c:if test="${l.is_outlier == true}"><span style="color:#c0392b; font-weight:bold;">YES</span></c:if>
                    <c:if test="${l.is_outlier == false}">NO</c:if>
                    </td>
                    <td>
                    <c:if test="${l.usable_for_alerting == true}">YES</c:if>
                    <c:if test="${l.usable_for_alerting == false}"><span style="color:#c0392b; font-weight:bold;">NO</span></c:if>
                    </td>
                    <td>${l.recorded_at}</td>
                    </tr>
                </c:forEach>
                </tbody>
            </table>
        </div>
    </body>
</html>