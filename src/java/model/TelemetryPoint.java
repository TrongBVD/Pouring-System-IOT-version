package model;

public class TelemetryPoint {

    private String sensor_name;
    private double value;
    private long t_offset_ms;

    public TelemetryPoint() {
    }

    public String getSensor_name() {
        return sensor_name;
    }

    public void setSensor_name(String sensor_name) {
        this.sensor_name = sensor_name;
    }

    public double getValue() {
        return value;
    }

    public void setValue(double value) {
        this.value = value;
    }

    public long getT_offset_ms() {
        return t_offset_ms;
    }

    public void setT_offset_ms(long t_offset_ms) {
        this.t_offset_ms = t_offset_ms;
    }
}
