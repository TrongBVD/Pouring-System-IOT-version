package model;

public class AccountAudit {

    private String time;
    private String creator;
    private String creatorRole;
    private String action;
    private String createdAccount;
    private String assignedRole;
    private String status;

    // Constructors
    public AccountAudit() {
    }

    public AccountAudit(String time, String creator, String creatorRole, String action, String createdAccount, String assignedRole, String status) {
        this.time = time;
        this.creator = creator;
        this.creatorRole = creatorRole;
        this.action = action;
        this.createdAccount = createdAccount;
        this.assignedRole = assignedRole;
        this.status = status;
    }

    // Getters
    public String getTime() {
        return time;
    }

    public String getCreator() {
        return creator;
    }

    public String getCreatorRole() {
        return creatorRole;
    }

    public String getAction() {
        return action;
    }

    public String getCreatedAccount() {
        return createdAccount;
    }

    public String getAssignedRole() {
        return assignedRole;
    }

    public String getStatus() {
        return status;
    }
}
