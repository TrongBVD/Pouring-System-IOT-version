<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Pour History</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            .log-container {
                margin: 20px auto;
                width: 97%;
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
                vertical-align: top;
            }
            th {
                background: #f8f9fa;
                white-space: nowrap;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>Pour History</h2>
            <div>
                <a href="PourSessionMetaController" style="color: white; text-decoration: none; margin-right: 15px;">Open Pour Session Meta page</a>
                <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
            </div>
        </div>
        <div class="log-container">
            <c:if test="${not empty param.msg}"><p style="color:green; font-weight:bold;">Curated successfully.</p></c:if>
            <c:if test="${not empty param.error}"><p style="color:red; font-weight:bold;">Error: ${param.error}</p></c:if>

                <table>
                    <thead>
                        <tr>
                            <th>Session ID</th>
                            <th>Device ID</th>
                            <th>User ID</th>
                            <th>Username</th>
                            <th>Target ML</th>
                            <th>Actual ML</th>
                            <th>Duration (s)</th>
                            <th>Peak Flow</th>
                            <th>Avg Flow</th>
                            <th>Cup Present</th>
                            <th>Start Reason</th>
                            <th>Result Code</th>
                            <th>Stop Reason</th>
                            <th>Started At</th>
                            <th>Ended At</th>
                            <th>Time Source</th>
                            <th>Alert Risk</th>
                            <th>Meta</th>
                        </tr>
                    </thead>
                    <tbody>
                    <c:forEach var="h" items="${POUR_HISTORY}">
                        <tr>
                            <td>#${h.sessionId}</td>
                            <td>${h.deviceId}</td>
                            <td>${h.userId}</td>
                            <td><c:out value="${empty h.username ? '-' : h.username}"/></td>
                            <td>${h.targetMl}</td>
                            <td style="color:#2980b9; font-weight:bold;">${h.actualMl}</td>
                            <td>${h.duration}</td>
                            <td>${h.peakFlow}</td>
                            <td>${h.avgFlow}</td>
                            <td>${h.cupPresent}</td>
                            <td>${h.startReason}</td>
                            <td>${h.resultCode}</td>
                            <td>${h.stopReason}</td>
                            <td>${h.startedAt}</td>
                            <td>${h.endedAt}</td>
                            <td>${h.timeSource}</td>
                            <td>${h.mlRiskScore != null ? h.mlRiskScore : 'N/A'}</td>
                            <td><a href="PourSessionMetaController">adjust on the meta page</a></td>
                        </tr>
                    </c:forEach>
                </tbody>
            </table>
        </div>
    </body>
</html>
