<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Pour Session Meta</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            .log-container {
                margin: 20px auto;
                width: 98%;
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
                background:#f8f9fa;
                white-space: nowrap;
            }
            input[type=text], select, textarea {
                width: 100%;
                padding: 6px;
                box-sizing: border-box;
            }
            textarea {
                min-height: 60px;
                resize: vertical;
            }
            .readonly {
                color:#7f8c8d;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>Pour Session Meta</h2>
            <div>
                <a href="PourHistoryController" style="color:white; text-decoration:none; margin-right:15px;">Back to Pour History</a>
                <a href="DashboardController" style="color:white; text-decoration:none;">Back to Dashboard</a>
            </div>
        </div>
        <div class="log-container">
            <c:if test="${not empty param.msg}"><p style="color:green; font-weight:bold;">Meta updated successfully.</p></c:if>
            <c:if test="${not empty param.error}"><p style="color:red; font-weight:bold;">Error: ${param.error}</p></c:if>

                <table>
                    <thead>
                        <tr>
                            <th>Session</th>
                            <th>User</th>
                            <th>Actual / Duration</th>
                            <th>Peak / Avg</th>
                            <th>Cup / Result</th>
                            <th>Started</th>
                            <th>Risk</th>
                            <th>Adjustment</th>
                        </tr>
                    </thead>
                    <tbody>
                    <c:forEach var="m" items="${POUR_SESSION_META_LIST}">
                        <tr>
                            <td>
                                <strong>#${m.sessionId}</strong><br>
                                <span class="readonly">Device: ${m.deviceId}</span>
                            </td>
                            <td>
                                <strong><c:out value="${empty m.username ? '-' : m.username}"/></strong><br>
                                <span class="readonly">user_id=${m.userId}</span>
                            </td>
                            <td>
                                ${m.actualMl} ml<br>
                                ${m.duration} s
                            </td>
                            <td>
                                peak=${m.peakFlow}<br>
                                avg=${m.avgFlow}
                            </td>
                            <td>
                                cup_present=${m.cupPresent}<br>
                                <strong>${m.resultCode}</strong><br>
                                <span class="readonly">Stop: ${m.stopReason}</span>
                            </td>
                            <td>${m.startedAt}</td>
                            <td>${m.mlRiskScore != null ? m.mlRiskScore : 'N/A'}</td>
                            <td>
                                <c:choose>
                                    <c:when test="${sessionScope.LOGIN_USER.role == 'ADMIN' || sessionScope.LOGIN_USER.role == 'TECHNICIAN'}">
                                        <form action="PourSessionMetaController" method="POST" style="margin:0; display:flex; flex-direction:column; gap:8px; min-width:280px;">
                                            <input type="hidden" name="action" value="update_meta">
                                            <input type="hidden" name="session_id" value="${m.sessionId}">

                                            <div class="readonly" style="background:#f8f9fa; padding:8px; border-radius:4px; border:1px solid #ddd;">
                                                <strong>Current ML Eligible:</strong>
                                                <c:choose>
                                                    <c:when test="${m.mlEligible}">1 (true / eligible)</c:when>
                                                    <c:otherwise>0 (false / excluded)</c:otherwise>
                                                </c:choose>
                                                <br>
                                                <strong>Current Exclusion Reason:</strong>
                                                <c:out value="${empty m.mlExclusionReason ? 'NULL' : m.mlExclusionReason}"/>
                                            </div>

                                            <label>ML Eligible</label>
                                            <select name="ml_eligible">
                                                <option value="">Keep current value</option>
                                                <option value="1">1 = true / eligible</option>
                                                <option value="0">0 = false / excluded</option>
                                            </select>

                                            <label>ML Exclusion Reason</label>
                                            <input type="text" name="ml_exclusion_reason" placeholder="Example: SENSOR_NOISY / MANUAL_EXCLUDE">

                                            <div class="readonly" style="background:#f8f9fa; padding:8px; border-radius:4px; border:1px solid #ddd;">
                                                <strong>Current Curated Result:</strong>
                                                <c:out value="${empty m.curatedResultCode ? 'NULL' : m.curatedResultCode}"/>
                                                <br>
                                                <strong>Current Curated Note:</strong>
                                                <c:out value="${empty m.curatedNote ? 'NULL' : m.curatedNote}"/>
                                            </div>

                                            <label>Curated Result Code</label>
                                            <select name="curated_result_code">
                                                <option value="">Keep unchanged</option>
                                                <option value="SUCCESS">SUCCESS</option>
                                                <option value="UNDER_POUR">UNDER_POUR</option>
                                                <option value="OVER_POUR">OVER_POUR</option>
                                                <option value="NO_CUP">NO_CUP</option>
                                                <option value="TIMEOUT">TIMEOUT</option>
                                                <option value="ERROR">ERROR</option>
                                            </select>

                                            <label>Curated Note</label>
                                            <textarea name="curated_note" placeholder="Adjustment note / reason / ticket ID"></textarea>

                                            <button type="submit" style="background:#8e44ad; color:white; border:none; padding:8px 12px; cursor:pointer; border-radius:4px; font-weight:bold;">
                                                Save adjustment
                                            </button>
                                        </form>
                                    </c:when>

                                    <c:otherwise>
                                        <div class="readonly" style="min-width:280px;">
                                            <strong>View-only mode.</strong><br>
                                            Only ADMIN / TECHNICIAN can make adjustments.<br><br>

                                            <strong>Current ML Eligible:</strong>
                                            <c:choose>
                                                <c:when test="${m.mlEligible}">1 (true / eligible)</c:when>
                                                <c:otherwise>0 (false / excluded)</c:otherwise>
                                            </c:choose>
                                            <br>

                                            <strong>Current Exclusion Reason:</strong>
                                            <c:out value="${empty m.mlExclusionReason ? 'NULL' : m.mlExclusionReason}"/>
                                            <br>

                                            <strong>Current Curated Result:</strong>
                                            <c:out value="${empty m.curatedResultCode ? 'NULL' : m.curatedResultCode}"/>
                                            <br>

                                            <strong>Current Curated Note:</strong>
                                            <c:out value="${empty m.curatedNote ? 'NULL' : m.curatedNote}"/>
                                        </div>
                                    </c:otherwise>
                                </c:choose>
                            </td>
                        </tr>
                    </c:forEach>
                </tbody>
            </table>
        </div>
    </body>
</html>
