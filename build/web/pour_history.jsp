<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Pour History</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            body {
                background: #f4f7f6;
            }

            .history-page {
                width: 96%;
                max-width: 1700px;
                margin: 20px auto 30px;
            }

            .history-card {
                background: white;
                border-radius: 12px;
                box-shadow: 0 4px 18px rgba(0,0,0,0.08);
                padding: 24px;
            }

            .history-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                gap: 16px;
                margin-bottom: 20px;
                flex-wrap: wrap;
            }

            .history-title {
                margin: 0;
                font-size: 30px;
                color: #2c3e50;
            }

            .history-subtitle {
                margin: 6px 0 0;
                color: #7f8c8d;
                font-size: 16px;
            }

            .history-actions {
                display: flex;
                gap: 12px;
                flex-wrap: wrap;
            }

            .history-btn {
                display: inline-block;
                padding: 12px 18px;
                border-radius: 8px;
                text-decoration: none;
                font-weight: 600;
                font-size: 16px;
                transition: 0.2s ease;
                color: white;
                background: #34495e;
            }

            .history-btn:hover {
                opacity: 0.92;
            }

            .history-btn.secondary {
                background: #3498db;
            }

            .message {
                padding: 14px 16px;
                border-radius: 8px;
                margin-bottom: 16px;
                font-size: 16px;
                font-weight: 600;
            }

            .message.success {
                background: #eafaf1;
                color: #1e8449;
                border: 1px solid #b7e4c7;
            }

            .message.error {
                background: #fdecea;
                color: #c0392b;
                border: 1px solid #f5b7b1;
            }

            .table-wrap {
                width: 100%;
                overflow-x: auto;
                border: 1px solid #e5e7eb;
                border-radius: 10px;
            }

            .history-table {
                width: 100%;
                min-width: 1650px;
                border-collapse: collapse;
                font-size: 15px;
                background: white;
            }

            .history-table thead th {
                position: sticky;
                top: 0;
                background: #2c3e50;
                color: white;
                text-align: left;
                padding: 14px 12px;
                white-space: nowrap;
                font-size: 15px;
            }

            .history-table tbody td {
                padding: 14px 12px;
                border-bottom: 1px solid #eef1f4;
                vertical-align: top;
                white-space: nowrap;
            }

            .history-table tbody tr:nth-child(even) {
                background: #fafbfc;
            }

            .history-table tbody tr:hover {
                background: #f1f7fd;
            }

            .session-id {
                font-weight: 700;
                color: #2c3e50;
            }

            .actual-ml {
                color: #2980b9;
                font-weight: 700;
            }

            .pill {
                display: inline-block;
                padding: 6px 10px;
                border-radius: 999px;
                font-size: 13px;
                font-weight: 700;
                white-space: nowrap;
            }

            .pill.success {
                background: #eafaf1;
                color: #1e8449;
            }

            .pill.fail {
                background: #fdecea;
                color: #c0392b;
            }

            .pill.warn {
                background: #fff8e1;
                color: #b9770e;
            }

            .pill.info {
                background: #ebf5fb;
                color: #2471a3;
            }

            .meta-link {
                color: #8e44ad;
                font-weight: 600;
                text-decoration: none;
            }

            .meta-link:hover {
                text-decoration: underline;
            }

            @media (max-width: 768px) {
                .history-page {
                    width: 98%;
                }

                .history-card {
                    padding: 16px;
                }

                .history-title {
                    font-size: 24px;
                }

                .history-btn {
                    width: 100%;
                    text-align: center;
                }
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

        <div class="history-page">
            <div class="history-card">
                <div class="history-header">
                    <div>
                        <h1 class="history-title">Pour Session History</h1>
                        <p class="history-subtitle">Review all completed pouring sessions, results, timestamps, and metadata links.</p>
                    </div>

                    <div class="history-actions">
                        <a class="history-btn secondary" href="PourSessionMetaController">Open Meta Page</a>
                        <a class="history-btn" href="DashboardController">Back to Dashboard</a>
                    </div>
                </div>

                <c:if test="${not empty param.msg}">
                    <div class="message success">Curated successfully.</div>
                </c:if>

                <c:if test="${not empty param.error}">
                    <div class="message error">Error: ${param.error}</div>
                </c:if>

                <div class="table-wrap">
                    <table class="history-table">
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
                                    <td class="session-id">#${h.sessionId}</td>
                                    <td>${h.deviceId}</td>
                                    <td>${h.userId}</td>
                                    <td><c:out value="${empty h.username ? '-' : h.username}"/></td>
                                    <td>${h.targetMl}</td>
                                    <td class="actual-ml">${h.actualMl}</td>
                                    <td>${h.duration}</td>
                                    <td>${h.peakFlow}</td>
                                    <td>${h.avgFlow}</td>

                                    <td>
                                        <span class="pill ${h.cupPresent ? 'success' : 'fail'}">
                                            ${h.cupPresent ? 'TRUE' : 'FALSE'}
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill info">${h.startReason}</span>
                                    </td>

                                    <td>
                                        <span class="pill
                                              ${h.resultCode == 'SUCCESS' ? 'success' :
                                                (h.resultCode == 'NO_CUP' || h.resultCode == 'ERROR' || h.resultCode == 'UNDER_POUR' || h.resultCode == 'OVER_POUR' ? 'fail' : 'warn')}">
                                                  ${h.resultCode}
                                              </span>
                                        </td>

                                        <td>${h.stopReason}</td>
                                        <td>${h.startedAt}</td>
                                        <td>${h.endedAt}</td>
                                        <td>${h.timeSource}</td>
                                        <td>${h.mlRiskScore != null ? h.mlRiskScore : 'N/A'}</td>
                                        <td>
                                            <a class="meta-link" href="PourSessionMetaController">Adjust on meta page</a>
                                        </td>
                                    </tr>
                                </c:forEach>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </body>
    </html>