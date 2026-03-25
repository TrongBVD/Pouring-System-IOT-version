<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <meta charset="UTF-8">
        <title>Full System Audit Logs</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            .log-container {
                margin: 20px auto;
                width: 95%;
                max-width: 1400px;
                background: white;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                padding: 20px;
            }
            .log-table {
                width: 100%;
                border-collapse: collapse;
                margin-top: 15px;
                font-size: 13px;
                font-family: monospace;
            }
            .log-table th {
                background: #f1f2f6;
                color: #2f3640;
                padding: 12px;
                text-align: left;
                border: 1px solid #dcdde1;
                font-weight: bold;
            }
            .log-table td {
                padding: 10px 12px;
                border: 1px solid #dcdde1;
                color: #353b48;
                word-wrap: break-word;
            }
            .log-table tr:nth-child(even) {
                background-color: #f8f9fa;
            }
            .log-table tr:hover {
                background-color: #f1f2f6;
            }

            .badge-role {
                background: #34495e;
                color: white;
                padding: 3px 6px;
                border-radius: 4px;
                font-weight: bold;
            }

            /* CSS NÚT VERIFY */
            .btn-verify {
                background-color: #8e44ad;
                color: white;
                padding: 10px 15px;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                font-weight: bold;
                font-size: 14px;
            }
            .btn-verify:hover {
                background-color: #9b59b6;
            }

            /* CSS KHUNG THÔNG BÁO ALERT */
            .alert-box {
                padding: 15px;
                margin-top: 15px;
                border-radius: 5px;
                font-weight: bold;
            }
            .alert-success {
                background-color: #d4edda;
                color: #155724;
                border: 1px solid #c3e6cb;
            }
            .alert-danger {
                background-color: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
            }

            /* CSS CHO 3 CỘT HASH CHAIN (Cắt bớt chữ, di chuột vào để xem full) */
            .hash-col {
                max-width: 100px;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
                color: #7f8c8d;
                cursor: help;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>System Audit Logs</h2>
            <div class="device-stats">
                <span>Viewer: <strong>${sessionScope.LOGIN_USER.username}</strong> (${sessionScope.LOGIN_USER.role})</span>
                <span> | </span>
                <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
            </div>
        </div>

        <div class="log-container">

            <div style="display: flex; justify-content: space-between; align-items: center;">
                <h3 style="color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 5px; margin: 0;">Immutable Audit Chain</h3>
                <form action="AuditLogController" method="POST" style="margin: 0;">
                    <input type="hidden" name="action" value="verify">
                    <button type="submit" class="btn-verify">🔍 Verify Data Integrity</button>
                </form>
            </div>

            <c:if test="${not empty VERIFY_RESULT}">
                <div class="alert-box ${VERIFY_RESULT == 'VALID' ? 'alert-success' : 'alert-danger'}">
                    <c:choose>
                        <c:when test="${VERIFY_RESULT == 'VALID'}">
                            ✅ SYSTEM INTEGRITY VERIFIED: All hash links match 100%. No signs of direct database tampering were detected.
                        </c:when>
                        <c:when test="${VERIFY_RESULT == 'ERROR'}">
                            ⚠️ ERROR: Unable to perform the data scan at this time.
                        </c:when>
                        <c:otherwise>
                            ❌ CRITICAL SECURITY WARNING: The data has been tampered with (modified or deleted). The chain breaks at: <strong>${VERIFY_RESULT}</strong>.
                        </c:otherwise>
                    </c:choose>
                </div>
            </c:if>

            <div style="overflow-x: auto; margin-top: 15px;">
                <table class="log-table">
                    <thead>
                        <tr>
                            <th width="4%">ID</th>
                            <th width="12%">Time (UTC)</th>
                            <th width="8%">Actor</th>
                            <th width="15%">Action</th>
                            <th width="8%">Object</th>
                            <th width="5%">Obj ID</th>
                            <th width="18%">Differences (JSON)</th>
                            <th width="10%">Prev Hash</th>
                            <th width="10%">Row Hash</th>
                            <th width="10%">Chain Hash</th>
                        </tr>
                    </thead>
                    <tbody>
                        <c:forEach var="a" items="${AUDIT_LOGS}">
                            <tr>
                                <td><strong>#${a.auditId}</strong></td>
                                <td>${a.auditTimestampUtc}</td>
                                <td><span class="badge-role">${a.actorRoleName}</span></td>
                                <td style="color:#e74c3c; font-weight:bold;">${a.action}</td>
                                <td>${a.objectType}</td>
                                <td>${a.objectId}</td>
                                <td style="max-width:200px; color:#27ae60; word-wrap:break-word;">${a.diffJson}</td>

                                <td class="hash-col" title="${empty a.prevHash ? 'NULL (Genesis Block)' : a.prevHash}">
                                    ${empty a.prevHash ? '<span style="color:#bdc3c7; font-style:italic;">NULL</span>' : a.prevHash}
                                </td>
                                <td class="hash-col" title="${a.rowHash}">${a.rowHash}</td>
                                <td class="hash-col" title="${a.chainHash}" style="color:#8e44ad; font-weight:bold;">${a.chainHash}</td>
                            </tr>
                        </c:forEach>
                    </tbody>
                </table>
            </div>
        </div>
    </body>
</html>