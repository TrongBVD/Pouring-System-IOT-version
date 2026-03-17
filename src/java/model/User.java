package model;

import java.util.ArrayList;
import java.util.List;

public class User {

    private int userId;
    private String username;
    private String status;
    private String role;

    // --- LIST QUYỀN HẠN (Ví dụ: ["DEVICE:READ", "USER:WRITE"]) ---
    private List<String> permissions = new ArrayList<>();

    public User() {
    }

    public User(int userId, String username, String status, String role) {
        this.userId = userId;
        this.username = username;
        this.status = status;
        this.role = role;
    }

    // Helper: Check quyền nhanh
    // Ví dụ gọi: user.hasPermission("DEVICE", "WRITE")
    public boolean hasPermission(String module, String action) {
        if ("ADMIN".equals(this.role)) {
            return true; // Admin chấp hết
        }
        return permissions.contains(module + ":" + action);
    }

    public int getUserId() {
        return userId;
    }

    public void setUserId(int userId) {
        this.userId = userId;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public List<String> getPermissions() {
        return permissions;
    }

    public void setPermissions(List<String> permissions) {
        this.permissions = permissions;
    }

    public void addPermission(String module, String action) {
        this.permissions.add(module + ":" + action);
    }
}
