package model;

public class PourProfile {

    private int profileId;
    private String name;
    private int targetMl;

    // Getters & Setters
    public int getProfileId() {
        return profileId;
    }

    public void setProfileId(int profileId) {
        this.profileId = profileId;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getTargetMl() {
        return targetMl;
    }

    public void setTargetMl(int targetMl) {
        this.targetMl = targetMl;
    }
}
