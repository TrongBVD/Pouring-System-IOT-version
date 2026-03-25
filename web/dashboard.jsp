<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <meta charset="UTF-8">
        <title>Dashboard - Smart Water</title>
        <link rel="stylesheet" href="css/style.css">
    </head>
    <body>
        <div class="banner">
            <div>
                <h2>Smart Water System</h2>
                <div class="device-stats">
                    <span>User: <strong>${sessionScope.LOGIN_USER.username}</strong> (${sessionScope.LOGIN_USER.role})</span>
                    <span> | </span>
                    <a href="LogoutController" style="color: #bdc3c7; text-decoration: none;">Logout</a>
                    <c:if test="${sessionScope.LOGIN_USER.role == 'ADMIN'}">
                        | <a href="AdminController?view=users" style="color: #3498db; text-decoration: none; font-weight:bold;">Manage Users</a>
                    </c:if>
                </div>
            </div>
            <div class="device-stats">
                <span>Device ID: <strong>#${DEVICE.deviceId}</strong></span>
                <span>Loc: ${DEVICE.location}</span>
                <span>Ver: ${DEVICE.firmwareVer}</span>
                <span class="status-badge status-${DEVICE.status}">${DEVICE.status}</span>
            </div>
        </div>

        <div class="container main-content">

            <c:if test="${not empty param.error}">
                <div style="background-color: #f8d7da; color: #721c24; padding: 10px; border-radius: 5px; margin-bottom: 15px; font-weight: bold;">
                    ⚠️ Error: ${param.error}
                </div>
            </c:if>
            <c:if test="${not empty param.msg && param.msg == 'success'}">
                <div style="background-color: #d4edda; color: #155724; padding: 10px; border-radius: 5px; margin-bottom: 15px; font-weight: bold;">
                    ✅ Updated successfully!
                </div>
            </c:if>

            <c:if test="${sessionScope.LOGIN_USER.role != 'AUDITOR' && sessionScope.LOGIN_USER.role != 'TECHNICIAN'}">
                <div style="display: flex; gap: 40px; align-items: center; margin-bottom: 20px;">
                    <c:choose>
                        <c:when test="${DEVICE.status == 'ERROR' || DEVICE.status == 'OFFLINE'}">
                            <div class="pour-btn disabled" style="background-color: #95a5a6; cursor: not-allowed; opacity: 0.7;">
                                <span class="pour-text">LOCKED</span>
                                <span class="pour-sub">Status: ${DEVICE.status}</span>
                            </div>
                        </c:when>
                        <c:otherwise>
                            <div class="pour-btn btn-pour-start" id="btnPour" onclick="triggerPour()" style="background-color: #95a5a6; pointer-events: none;">
                                <span class="pour-text">START POUR</span>
                                <span class="pour-sub" id="pourStatusText">Checking IoT network connection...</span>
                            </div>
                        </c:otherwise>
                    </c:choose>
                </div>

                <script>
                    setInterval(function () {
                        fetch('PourController?action=ping')
                                .then(response => response.text())
                                .then(data => {
                                    let btn = document.getElementById('btnPour');
                                    let txt = document.getElementById('pourStatusText');

                                    if (!btn || !txt)
                                        return;

                                    if (data.trim() === 'OK_ACTIVE') {
                                        btn.style.backgroundColor = '#3498db';
                                        btn.style.pointerEvents = 'auto';
                                        txt.innerText = 'Device ready (Click to pour)';
                                    } else if (data.trim() === 'OK_MAINTENANCE') {
                                        btn.style.backgroundColor = '#34495e';
                                        btn.style.pointerEvents = 'none';
                                        txt.innerText = 'SYSTEM LOCKED: Under maintenance';
                                    } else {
                                        btn.style.backgroundColor = '#e74c3c';
                                        btn.style.pointerEvents = 'none';
                                        txt.innerText = 'Device offline / Pouring in progress';
                                    }
                                }).catch(e => {
                            let btn = document.getElementById('btnPour');
                            let txt = document.getElementById('pourStatusText');
                            if (btn)
                                btn.style.pointerEvents = 'none';
                            if (txt)
                                txt.innerText = 'Lost IoT network connection';
                        });
                    }, 3000);

                    function triggerPour() {
                        let btn = document.getElementById('btnPour');
                        btn.style.pointerEvents = 'none';
                        document.getElementById('pourStatusText').innerText = 'Sending pour command...';

                        fetch('PourController?action=start_pour', {method: 'POST'})
                                .then(response => response.text())
                                .then(data => {
                                    if (data.trim() === 'OK') {
                                        document.getElementById('pourStatusText').innerText = 'Pouring water!';
                                        btn.style.backgroundColor = '#2ecc71';
                                    } else if (data.trim() === 'MAINTENANCE') {
                                        alert("The system is locked for maintenance and cannot pour!");
                                    } else {
                                        alert("Error: The device is busy or no cup has been placed!");
                                    }
                                });
                    }
                </script>
            </c:if>

            <c:if test="${sessionScope.LOGIN_USER.role == 'AUDITOR' || sessionScope.LOGIN_USER.role == 'TECHNICIAN'}">
                <div style="padding: 20px; background: #ecf0f1; border-radius: 8px; text-align: center; font-weight: bold; margin-bottom: 20px; color: #7f8c8d; border: 1px dashed #bdc3c7;">
                    You are in view/service mode. This account cannot start the water pouring device.
                </div>
            </c:if>

            <c:if test="${sessionScope.LOGIN_USER.role == 'AUDITOR'}">
                <div style="padding: 20px; background: #ecf0f1; border-radius: 8px; text-align: center; font-weight: bold; margin-bottom: 20px; color: #7f8c8d; border: 1px dashed #bdc3c7;">
                    You are in OBSERVER mode (Auditor). You do not have permission to control the water pouring device.
                </div>
            </c:if>

            <c:if test="${sessionScope.LOGIN_USER.role == 'ADMIN'}">
                <div class="admin-panel" style="margin-top: 20px;">
                    <h3>Admin Controls</h3>
                    <form action="AdminController" method="POST">
                        <input type="hidden" name="action" value="update_status">
                        <div class="admin-row">
                            <div class="form-group" style="flex:1">
                                <label>Set Device Status</label>
                                <select name="device_status" class="form-control" required>
                                    <option value="ACTIVE" ${DEVICE.status == 'ACTIVE' ? 'selected' : ''}>ACTIVE</option>
                                    <option value="MAINTENANCE" ${DEVICE.status == 'MAINTENANCE' ? 'selected' : ''}>MAINTENANCE</option>
                                    <c:if test="${DEVICE.status == 'OFFLINE'}">
                                        <option value="OFFLINE" selected disabled>OFFLINE (System Auto)</option>
                                    </c:if>
                                    <c:if test="${DEVICE.status == 'ERROR'}">
                                        <option value="ERROR" selected disabled>ERROR (System Auto)</option>
                                    </c:if>
                                </select>
                            </div>
                            <button type="submit" class="btn btn-secondary" style="width: auto;">Set Status</button>
                        </div>
                    </form>
                    <hr>
                    <h3>System Configuration</h3>
                    <div style="display: flex; gap: 15px;">
                        <a href="SensorTypeController" class="btn btn-secondary" style="background:#34495e; color:white; text-decoration:none; padding:10px 15px; border-radius:5px; text-align:center;">
                            ⚙️ Sensor Type Management
                        </a>
                    </div>
                </div>
            </c:if>

            <c:if test="${sessionScope.LOGIN_USER.role != 'GUEST' && sessionScope.LOGIN_USER.role != 'OPERATOR'}">
                <div class="admin-panel" style="margin-top: 20px; text-align: left;">
                    <h3 style="margin-bottom: 15px;">System Logs & Records</h3>
                    <div style="display: flex; gap: 20px; flex-wrap: wrap;">
                        <a href="PourHistoryController" class="btn btn-primary" style="text-decoration:none; padding: 10px 15px; border-radius: 5px; text-align:center; flex:1;">
                            📊 Pour History<br><small>(Water pouring history)</small>
                        </a>

                        <a href="PourSessionMetaController" class="btn" style="background-color:#8e44ad; color:white; text-decoration:none; padding: 10px 15px; border-radius: 5px; text-align:center; flex:1;">
                            🧩 Pour Session Meta<br>
                            <small>
                                <c:choose>
                                    <c:when test="${sessionScope.LOGIN_USER.role == 'AUDITOR'}">(View only)</c:when>
                                    <c:otherwise>(View / adjust metadata)</c:otherwise>
                                </c:choose>
                            </small>
                        </a>

                        <c:if test="${sessionScope.LOGIN_USER.role == 'AUDITOR' || sessionScope.LOGIN_USER.role == 'ADMIN' || sessionScope.LOGIN_USER.role == 'TECHNICIAN'}">
                            <a href="SensorLogController" class="btn" style="background-color:#3498db; color:white; text-decoration:none; padding: 10px 15px; border-radius: 5px; text-align:center; flex:1;">
                                📈 Sensor Logs<br><small>(Raw data & metadata)</small>
                            </a>

                            <a href="SensorHealthController" class="btn" style="background-color:#16a085; color:white; text-decoration:none; padding: 10px 15px; border-radius: 5px; text-align:center; flex:1;">
                                🩺 Health Report<br><small>(Device metrics every 5 minutes)</small>
                            </a>

                            <c:if test="${sessionScope.LOGIN_USER.role == 'AUDITOR' || sessionScope.LOGIN_USER.role == 'ADMIN'}">
                                <a href="AuditLogController" class="btn" style="background-color:#8e44ad; color:white; text-decoration:none; padding: 10px 15px; border-radius: 5px; text-align:center; flex:1;">
                                    🔒 Full Audit Logs<br><small>(Blockchain hash chain)</small>
                                </a>
                            </c:if>

                            <c:if test="${sessionScope.LOGIN_USER.role == 'ADMIN' || sessionScope.LOGIN_USER.role == 'TECHNICIAN' || sessionScope.LOGIN_USER.role == 'AUDITOR'}">
                                <a href="MaintenanceController" class="btn" style="background-color:#e67e22; color:white; text-decoration:none; padding: 10px 15px; border-radius: 5px; text-align:center; flex:1; position: relative;">
                                    🛠️ Maintenance
                                    <c:if test="${ACTIVE_ALERT_COUNT > 0 && sessionScope.LOGIN_USER.role != 'AUDITOR'}">
                                        <span style="position: absolute; top: -10px; right: -10px; background: #e74c3c; color: white; border-radius: 50%; padding: 5px 10px; font-weight: bold; font-size: 14px;">
                                            ${ACTIVE_ALERT_COUNT}
                                        </span>
                                    </c:if>
                                    <br>
                                    <small>
                                        <c:choose>
                                            <c:when test="${sessionScope.LOGIN_USER.role == 'AUDITOR'}">(View only)</c:when>
                                            <c:otherwise>(Maintenance & issues)</c:otherwise>
                                        </c:choose>
                                    </small>
                                </a>
                            </c:if>
                        </c:if>
                    </div>
                </div>
            </c:if>   
        </div>
    </body>
</html>