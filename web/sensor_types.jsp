<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core"%>
<!DOCTYPE html>
<html>
    <head>
        <title>Sensor Management</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
            .container {
                margin: 20px auto;
                width: 80%;
                background: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            table {
                width: 100%;
                border-collapse: collapse;
            }
            th, td {
                padding: 12px;
                border-bottom: 1px solid #ddd;
                text-align: left;
            }
            th {
                background: #f8f9fa;
            }
            .form-row {
                display: flex;
                gap: 15px;
                margin-bottom: 20px;
                align-items: center;
            }
            .form-control {
                padding: 8px;
                width: 200px;
                border: 1px solid #ccc;
                border-radius: 4px;
            }
            .btn-add {
                background: #2ecc71;
                color: white;
                padding: 8px 15px;
                border: none;
                border-radius: 4px;
                font-weight: bold;
                cursor: pointer;
            }
            .btn-delete {
                background: #e74c3c;
                color: white;
                padding: 6px 10px;
                border: none;
                border-radius: 4px;
                font-size: 12px;
                cursor: pointer;
            }
        </style>
    </head>
    <body>
        <div class="banner">
            <h2>System Configuration: Sensor Types</h2>
            <a href="DashboardController" style="color: white; text-decoration: none;">Back to Dashboard</a>
        </div>

        <div class="container">
            <c:if test="${not empty param.error}"><p style="color:red; font-weight:bold;">❌ ${param.error}</p></c:if>
            <c:if test="${not empty param.msg}"><p style="color:green; font-weight:bold;">✅ ${param.msg}</p></c:if>

            <form action="SensorTypeController" method="POST" class="form-row">
                <input type="hidden" name="action" value="add">
                <input type="text" name="name" class="form-control" placeholder="Sensor name (e.g. Loadcell HX711)" required>
                <input type="text" name="unit" class="form-control" placeholder="Unit (e.g. gram, ml, cm)" required>
                <button type="submit" class="btn-add">+ Add Sensor</button>
            </form>

            <table>
                <thead><tr><th>ID</th><th>Sensor Name</th><th>Unit</th><th>Action</th></tr></thead>
                <tbody>
                <c:forEach var="s" items="${SENSORS}">
                    <tr>
                        <td>#${s.id}</td>
                        <td><strong>${s.name}</strong></td>
                        <td><span class="status-badge st-ACTIVE">${s.unit}</span></td>
                        <td>
                            <form action="SensorTypeController" method="POST" style="margin:0;" onsubmit="return confirm('Delete this sensor?');">
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="id" value="${s.id}">
                                <button type="submit" class="btn-delete">Delete</button>
                            </form>
                        </td>
                    </tr>
                </c:forEach>
                </tbody>
            </table>
        </div>
    </body>
</html>