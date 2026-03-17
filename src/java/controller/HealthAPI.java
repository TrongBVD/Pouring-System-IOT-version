package controller;

import utils.DBContext;
import java.io.BufferedReader;
import java.io.IOException;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Types;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@WebServlet(name = "HealthAPI", urlPatterns = {"/api/health"})
public class HealthAPI extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        StringBuilder sb = new StringBuilder();
        BufferedReader reader = request.getReader();
        String line;
        while ((line = reader.readLine()) != null) {
            sb.append(line);
        }
        String healthJson = sb.toString();

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        try (
                 Connection conn = DBContext.getConnection();  CallableStatement cs = conn.prepareCall("{call dbo.SensorLog_Health_Ingest(?, ?, ?, ?, ?, ?)}")) {
            cs.setInt(1, 1);               // @device_id
            cs.setString(2, healthJson);   // @health_json
            cs.setInt(3, 2);               // @actor_user_id = SYSTEM
            cs.setString(4, "SYSTEM");     // @actor_role_name

            cs.registerOutParameter(5, Types.INTEGER); // @audit_id OUTPUT
            cs.registerOutParameter(6, Types.CHAR);    // @chain_hash OUTPUT

            cs.execute();

            int auditId = cs.getInt(5);
            String chainHash = cs.getString(6);

            response.setStatus(200);
            response.getWriter().print(
                    "{\"status\":\"success\",\"audit_id\":" + auditId + ",\"chain_hash\":\"" + chainHash + "\"}"
            );
        } catch (Exception e) {
            e.printStackTrace();
            response.setStatus(500);
            response.getWriter().print("{\"status\":\"error\",\"message\":\"Health ingest failed\"}");
        }
    }
}
