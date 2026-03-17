// File: model/AuditChainRow.java
package model;

import java.time.LocalDateTime;

public class AuditChainRow {

    // Các trường dữ liệu map trực tiếp từ Database View
    private int anchorId;
    private int auditId;
    private String prevHash;   // Có thể null nếu là dòng đầu tiên (Genesis)
    private String rowHash;
    private String chainHash;

    private LocalDateTime auditTimestampUtc;
    private int actorUserId;
    private String actorRoleName;
    private String action;
    private String objectType;
    private int objectId;
    private String diffJson;   // Có thể chứa "<NULL>"

    // --- CÁC TRƯỜNG PHỤC VỤ HIỂN THỊ UI ---
    private boolean valid;
    private String tamperReason;

    public AuditChainRow() {
    }

    // ==========================================
    // GETTERS & SETTERS
    // ==========================================
    public int getAnchorId() {
        return anchorId;
    }

    public void setAnchorId(int anchorId) {
        this.anchorId = anchorId;
    }

    public int getAuditId() {
        return auditId;
    }

    public void setAuditId(int auditId) {
        this.auditId = auditId;
    }

    public String getPrevHash() {
        return prevHash;
    }

    public void setPrevHash(String prevHash) {
        this.prevHash = prevHash;
    }

    public String getRowHash() {
        return rowHash;
    }

    public void setRowHash(String rowHash) {
        this.rowHash = rowHash;
    }

    public String getChainHash() {
        return chainHash;
    }

    public void setChainHash(String chainHash) {
        this.chainHash = chainHash;
    }

    public LocalDateTime getAuditTimestampUtc() {
        return auditTimestampUtc;
    }

    public void setAuditTimestampUtc(LocalDateTime auditTimestampUtc) {
        this.auditTimestampUtc = auditTimestampUtc;
    }

    public int getActorUserId() {
        return actorUserId;
    }

    public void setActorUserId(int actorUserId) {
        this.actorUserId = actorUserId;
    }

    public String getActorRoleName() {
        return actorRoleName;
    }

    public void setActorRoleName(String actorRoleName) {
        this.actorRoleName = actorRoleName;
    }

    public String getAction() {
        return action;
    }

    public void setAction(String action) {
        this.action = action;
    }

    public String getObjectType() {
        return objectType;
    }

    public void setObjectType(String objectType) {
        this.objectType = objectType;
    }

    public int getObjectId() {
        return objectId;
    }

    public void setObjectId(int objectId) {
        this.objectId = objectId;
    }

    public String getDiffJson() {
        return diffJson;
    }

    public void setDiffJson(String diffJson) {
        this.diffJson = diffJson;
    }

    public boolean isValid() {
        return valid;
    }

    public void setValid(boolean valid) {
        this.valid = valid;
    }

    public String getTamperReason() {
        return tamperReason;
    }

    public void setTamperReason(String tamperReason) {
        this.tamperReason = tamperReason;
    }
}
