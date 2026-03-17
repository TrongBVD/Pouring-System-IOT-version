package controller;

import dao.DeviceDAO;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import model.User;

@WebServlet(name = "PourController", urlPatterns = {"/PourController"})
public class PourController extends HttpServlet {

    private static final String ESP_IP = "http://192.168.4.1";

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException {
        String action = request.getParameter("action");
        if ("ping".equals(action)) {
            DeviceDAO dDao = new DeviceDAO();
            String dbStatus = dDao.getDeviceStatus(1);
            boolean isDbMaintenance = "MAINTENANCE".equals(dbStatus);

            try {
                URL url = new URL(ESP_IP + "/ping");
                HttpURLConnection con = (HttpURLConnection) url.openConnection();
                con.setRequestMethod("GET");
                con.setConnectTimeout(1500);
                con.setReadTimeout(1500);

                if (con.getResponseCode() == 200) {
                    BufferedReader in = new BufferedReader(new InputStreamReader(con.getInputStream()));
                    String espStatus = in.readLine();
                    in.close();

                    if (espStatus != null) {
                        espStatus = espStatus.trim();
                    }

                    if (isDbMaintenance && !"MAINTENANCE".equals(espStatus)) {
                        forceSyncEspStatus("MAINTENANCE");
                    } else if (!isDbMaintenance && "MAINTENANCE".equals(espStatus)) {
                        forceSyncEspStatus("ACTIVE");
                    }

                    response.getWriter().write(isDbMaintenance ? "OK_MAINTENANCE" : "OK_ACTIVE");
                    return;
                }
            } catch (Exception e) {
            }

            response.getWriter().write(isDbMaintenance ? "OFFLINE_BUT_MAINTENANCE" : "OFFLINE");
        }
    }

    private void forceSyncEspStatus(String status) {
        try {
            URL url = new URL(ESP_IP + "/set-status");
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setDoOutput(true);
            conn.setConnectTimeout(1500);
            conn.getOutputStream().write(("status=" + URLEncoder.encode(status, "UTF-8")).getBytes("UTF-8"));
            conn.getResponseCode();
        } catch (Exception ignored) {
        }
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws IOException {
        HttpSession session = request.getSession();
        User user = (User) session.getAttribute("LOGIN_USER");
        if (user == null || "AUDITOR".equals(user.getRole())) {
            response.getWriter().write("DENIED");
            return;
        }

        String action = request.getParameter("action");
        if ("start_pour".equals(action)) {
            try {
                URL url = new URL(ESP_IP + "/pour");
                HttpURLConnection con = (HttpURLConnection) url.openConnection();
                con.setRequestMethod("POST");
                con.setDoOutput(true);
                con.setConnectTimeout(2500);
                con.setReadTimeout(2500);
                con.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");

                String body = "user_id=" + URLEncoder.encode(String.valueOf(user.getUserId()), "UTF-8")
                        + "&username=" + URLEncoder.encode(user.getUsername() == null ? "" : user.getUsername(), "UTF-8")
                        + "&start_reason=" + URLEncoder.encode("REMOTE_APP", "UTF-8");
                con.getOutputStream().write(body.getBytes("UTF-8"));

                int code = con.getResponseCode();
                if (code == 200) {
                    response.getWriter().write("OK");
                } else if (code == 403) {
                    response.getWriter().write("MAINTENANCE");
                } else {
                    response.getWriter().write("FAIL_OR_BUSY");
                }
            } catch (Exception e) {
                response.getWriter().write("ERROR_CONNECTION");
            }
        }
    }
}
