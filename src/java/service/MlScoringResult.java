package service;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public class MlScoringResult {

    private final double championScore;
    private final String championModelName;
    private final String reasonJson;
    private final Map<String, Double> shadowScores;
    private final boolean usedSimulation;

    public MlScoringResult(double championScore,
                           String championModelName,
                           String reasonJson,
                           Map<String, Double> shadowScores,
                           boolean usedSimulation) {
        this.championScore = championScore;
        this.championModelName = championModelName;
        this.reasonJson = reasonJson;
        this.shadowScores = shadowScores == null
                ? Collections.emptyMap()
                : Collections.unmodifiableMap(new LinkedHashMap<>(shadowScores));
        this.usedSimulation = usedSimulation;
    }

    public double getChampionScore() {
        return championScore;
    }

    public String getChampionModelName() {
        return championModelName;
    }

    public String getReasonJson() {
        return reasonJson;
    }

    public Map<String, Double> getShadowScores() {
        return shadowScores;
    }

    public boolean isUsedSimulation() {
        return usedSimulation;
    }

    public String toDebugString() {
        StringBuilder sb = new StringBuilder();
        sb.append("champion=").append(championModelName)
          .append(", score=").append(championScore)
          .append(", usedSimulation=").append(usedSimulation);

        if (!shadowScores.isEmpty()) {
            sb.append(", shadow=").append(shadowScores.toString());
        }
        return sb.toString();
    }
}