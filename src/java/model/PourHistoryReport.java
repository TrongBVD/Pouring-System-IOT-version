package model;

public class PourHistoryReport {

    private int sessionId;
    private String startTime;
    private String user;
    private String location;
    private String profile;
    private String target;
    private String actual;
    private String duration;
    private String peakFlow;
    private String result;
    private String stopReason;

    public PourHistoryReport() {
    }

    public PourHistoryReport(int sessionId, String startTime, String user, String location, String profile, String target, String actual, String duration, String peakFlow, String result, String stopReason) {
        this.sessionId = sessionId;
        this.startTime = startTime;
        this.user = user;
        this.location = location;
        this.profile = profile;
        this.target = target;
        this.actual = actual;
        this.duration = duration;
        this.peakFlow = peakFlow;
        this.result = result;
        this.stopReason = stopReason;
    }

    // Getters
    public int getSessionId() {
        return sessionId;
    }

    public String getStartTime() {
        return startTime;
    }

    public String getUser() {
        return user;
    }

    public String getLocation() {
        return location;
    }

    public String getProfile() {
        return profile;
    }

    public String getTarget() {
        return target;
    }

    public String getActual() {
        return actual;
    }

    public String getDuration() {
        return duration;
    }

    public String getPeakFlow() {
        return peakFlow;
    }

    public String getResult() {
        return result;
    }

    public String getStopReason() {
        return stopReason;
    }
}
