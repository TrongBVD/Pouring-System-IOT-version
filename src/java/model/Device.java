package model;

public class Device {

    private int deviceId;
    private String location;
    private String firmwareVer;
    private String status;
    private int targetMl;

    public int getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(int deviceId) {
        this.deviceId = deviceId;
    }

    public String getLocation() {
        return location;
    }

    public void setLocation(String location) {
        this.location = location;
    }

    public String getFirmwareVer() {
        return firmwareVer;
    }

    public void setFirmwareVer(String firmwareVer) {
        this.firmwareVer = firmwareVer;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public int getTargetMl() {
        return targetMl;
    }

    public void setTargetMl(int targetMl) {
        this.targetMl = targetMl;
    }
}
