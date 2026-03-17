package utils;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public class SecurityUtils {

    private static final String DEVICE_API_KEY = "ESP32_SECRET_2026";

    public static String hashPasswordSHA256(String input) {
        return sha256HexUtf16LE(input);
    }

    public static String sha256HexUtf16LE(String input) {
        if (input == null) {
            return null;
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] encodedhash = digest.digest(input.getBytes(StandardCharsets.UTF_16LE));
            return bytesToHex(encodedhash);
        } catch (Exception e) {
            throw new RuntimeException("Data hashing error", e);
        }
    }

    public static boolean isValidDeviceApiKey(String apiKey) {
        return apiKey != null && apiKey.equals(DEVICE_API_KEY);
    }

    private static String bytesToHex(byte[] hash) {
        StringBuilder hexString = new StringBuilder(2 * hash.length);
        for (int i = 0; i < hash.length; i++) {
            String hex = Integer.toHexString(0xff & hash[i]);
            if (hex.length() == 1) {
                hexString.append('0');
            }
            hexString.append(hex);
        }
        return hexString.toString();
    }
}
