<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Active Alerts</title>
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
            .btn-resolve {
                background: #2ecc71;
                color: white;
                border: none;
                padding: 8px 12px;
                border-radius: 4px;
                cursor: pointer;
                font-weight: bold;
            }
            .btn-resolve:hover {
                background: #27ae60;
            }
            .readonly-box {
                padding: 12px 14px;
                margin-bottom: 15px;
                border-radius: 6px;
                background: #f4f6f7;
                border: 1px dashed #bdc3c7;
                color: #566573;
                font-weight: bold;
            }
            .modal {
                display: none;
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0,0,0,0.5);
                align-items: center;
                justify-content: center;
            }
            .modal-content {
                background: white;
                padding: 25px;
                border-radius: 8px;
                width: 400px;
            }
            .form-group {
                margin-bottom: 15px;
            }
            .form-group label {
                display: block;
                font-weight: bold;
                margin-bottom: 5px;
            }
            .form-control {
                width: 100%;
                padding: 8px;
                box-sizing: border-box;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>Active System Alerts (Issues Requiring Action)</h2>
            <div class="device-stats">
                <a href="MaintenanceController?view=history" style="color: #f1c40f; text-decoration: none; margin-right: 15px; font-weight: bold;">📜 View Maintenance History</a>
                <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
            </div>
        </div>

        <div class="log-container">
            <c:if test="${sessionScope.LOGIN_USER.role == 'AUDITOR'}">
                <div class="readonly-box">
                    Auditor mode: this page is view-only. You can review active alerts but cannot resolve them.
                </div>
            </c:if>

            <c:if test="${not empty param.msg}">
                <p style="color:green; font-weight:bold;">✅ Issue resolved successfully!</p>
            </c:if>

            <c:if test="${not empty param.error}">
                <p style="color:red; font-weight:bold;">❌ Failed to resolve issue. Please check permissions.</p>
            </c:if>

            <table>
                <thead>
                    <tr>
                        <th>Alert ID</th>
                        <th>Device</th>
                        <th>Session</th>
                        <th>Type</th>
                        <th>Risk</th>
                        <th>Created At</th>
                        <th>Summary</th>
                        <th>Action</th>
                    </tr>
                </thead>
                <tbody>
                    <c:forEach var="a" items="${ACTIVE_ALERTS}">
                        <tr>
                            <td>#${a.alertId}</td>
                            <td>Device ${a.deviceId}</td>
                            <td><c:if test="${not empty a.sessionId}">#${a.sessionId}</c:if></td>
                            <td style="color:#e74c3c; font-weight:bold;">${a.alertType}</td>
                            <td>${a.riskScore}</td>
                            <td>${a.createdAt}</td>
                            <td>${a.summary}</td>
                            <td>
                                <c:choose>
                                    <c:when test="${sessionScope.LOGIN_USER.role == 'ADMIN' || sessionScope.LOGIN_USER.role == 'TECHNICIAN'}">
                                        <button class="btn-resolve" onclick="openResolveModal('${a.alertId}', '${a.deviceId}')">Resolve</button>
                                    </c:when>
                                    <c:otherwise>
                                        <span style="color:#7f8c8d;">View only</span>
                                    </c:otherwise>
                                </c:choose>
                            </td>
                        </tr>
                    </c:forEach>
                </tbody>
            </table>

            <c:if test="${empty ACTIVE_ALERTS}">
                <p style="text-align: center; color: #27ae60; font-weight: bold; padding: 20px;">The system is operating normally. No active issues detected!</p>
            </c:if>
        </div>

        <c:if test="${sessionScope.LOGIN_USER.role == 'ADMIN' || sessionScope.LOGIN_USER.role == 'TECHNICIAN'}">
            <div id="resolveModal" class="modal">
                <div class="modal-content">
                    <h3 style="margin-top:0; border-bottom: 2px solid #eee; padding-bottom:10px;">Resolve Alert #<span id="displayAlertId"></span></h3>
                    <form action="MaintenanceController" method="POST">
                        <input type="hidden" name="action" value="resolve_alert">
                        <input type="hidden" name="alert_id" id="inputAlertId" value="">
                        <input type="hidden" name="device_id" id="inputDeviceId" value="">

                        <div class="form-group">
                            <label>Faulty hardware (Ticket Type):</label>
                            <select name="ticket_type" class="form-control" required>
                                <option value="VALVE">Load cell sensor / Pump (VALVE)</option>
                                <option value="CLEAN">Pipe blockage / Dirt buildup (CLEAN)</option>
                                <option value="FILTER">Water filter (FILTER)</option>
                            </select>
                        </div>

                        <div class="form-group">
                            <label>Corrective action (Action):</label>
                            <select name="action_code" class="form-control" required>
                                <option value="INSPECTED">INSPECTED - Inspection completed</option>
                                <option value="CLEANED">CLEANED - Cleaned</option>
                                <option value="FILTER_REPLACED">FILTER_REPLACED - Filter replaced</option>
                                <option value="VALVE_ADJUSTED">VALVE_ADJUSTED - Valve adjusted</option>
                                <option value="VALVE_REPLACED">VALVE_REPLACED - Valve replaced</option>
                                <option value="RECALIBRATED">RECALIBRATED - Recalibrated</option>
                                <option value="TEST_POUR">TEST_POUR - Test pour performed</option>
                                <option value="NO_ISSUE_FOUND">NO_ISSUE_FOUND - No issue found</option>
                                <option value="ESCALATED">ESCALATED - Escalated</option>
                            </select>
                        </div>

                        <div class="form-group">
                            <label>Detailed note (Note):</label>
                            <textarea name="note" class="form-control" rows="3" placeholder="Enter the reason or replaced components..." required></textarea>
                        </div>

                        <div style="display:flex; justify-content:space-between; margin-top: 20px;">
                            <button type="button" onclick="closeModal()" style="padding: 8px 15px; cursor: pointer;">Cancel</button>
                            <button type="submit" class="btn-resolve">Accept & Resolve</button>
                        </div>
                    </form>
                </div>
            </div>

            <script>
                function openResolveModal(alertId, deviceId) {
                    document.getElementById('displayAlertId').innerText = alertId;
                    document.getElementById('inputAlertId').value = alertId;
                    document.getElementById('inputDeviceId').value = deviceId;
                    document.getElementById('resolveModal').style.display = 'flex';
                }
                function closeModal() {
                    document.getElementById('resolveModal').style.display = 'none';
                }
            </script>
        </c:if>
    </body>
</html>