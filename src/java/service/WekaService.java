package service;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import model.PourSession;
import weka.classifiers.Classifier;
import weka.core.Attribute;
import weka.core.DenseInstance;
import weka.core.Instance;
import weka.core.Instances;
import weka.core.SerializationHelper;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;

public class WekaService {

    // Chọn champion model chính thức
    private static final String CHAMPION_MODEL = "Logistics.model";

    // Chạy shadow để log so sánh
    private static final String[] MODEL_FILES = new String[]{
        "Logistics.model",
        "NaivesBayes.model",
        "RandomTree.model",
        "Hoeffding.model"
    };

    // Schema feature hiện tại:
    // actual_ml, duration_s, avg_flow
    private Instances dataStructure;

    private final Map<String, Classifier> loadedModels = new LinkedHashMap<>();
    private boolean championLoaded = false;

    public WekaService(String webInfPath) {
        buildDataStructure();
        loadModels(webInfPath);
    }

    private void buildDataStructure() {
        ArrayList<Attribute> attributes = new ArrayList<>();
        attributes.add(new Attribute("actual_ml"));
        attributes.add(new Attribute("duration_s"));
        attributes.add(new Attribute("avg_flow"));

        ArrayList<String> classValues = new ArrayList<>();
        classValues.add("NORMAL");
        classValues.add("ANOMALY");

        attributes.add(new Attribute("class", classValues));

        dataStructure = new Instances("PourSessionRisk", attributes, 0);
        dataStructure.setClassIndex(attributes.size() - 1);
    }

    private void loadModels(String webInfPath) {
        for (String modelFile : MODEL_FILES) {
            try {
                String modelPath = resolveModelPath(webInfPath, modelFile);
                if (modelPath == null) {
                    System.err.println("WEKA: Model not found -> " + modelFile);
                    continue;
                }

                Classifier classifier = (Classifier) SerializationHelper.read(modelPath);
                loadedModels.put(modelFile, classifier);

                System.out.println("WEKA: Loaded model -> " + modelFile);

                if (CHAMPION_MODEL.equalsIgnoreCase(modelFile)) {
                    championLoaded = true;
                }
            } catch (Exception e) {
                System.err.println("WEKA: Failed to load model " + modelFile + " -> " + e.getMessage());
            }
        }

        if (!championLoaded) {
            System.err.println("WEKA: Champion model not loaded. Service will run in Simulation Mode.");
        }
    }

    private String resolveModelPath(String webInfPath, String fileName) {
        if (webInfPath == null || webInfPath.trim().isEmpty()) {
            return null;
        }

        File direct = new File(webInfPath, fileName);
        if (direct.exists() && direct.isFile()) {
            return direct.getAbsolutePath();
        }

        File underModels = new File(new File(webInfPath, "models"), fileName);
        if (underModels.exists() && underModels.isFile()) {
            return underModels.getAbsolutePath();
        }

        return null;
    }

    /**
     * Hàm wrapper trả về điểm risk duy nhất cho chỗ gọi cũ.
     */
    public double analyzeSessionRisk(PourSession session) {
        MlScoringResult result = scoreSession(session);
        if (result == null) {
            return 0.0;
        }
        return result.getChampionScore();
    }

    /**
     * Hàm wrapper lấy reason_json cho AlertReason / log giải thích.
     */
    public String analyzeReasonJson(PourSession session) {
        MlScoringResult result = scoreSession(session);
        if (result == null) {
            return null;
        }
        return result.getReasonJson();
    }

    /**
     * Hàm đầy đủ: trả về cả champion score, reasonJson, shadow scores...
     */
    public MlScoringResult scoreSession(PourSession session) {
        Map<String, Double> shadowScores = new LinkedHashMap<>();

        if (session == null) {
            return new MlScoringResult(
                    0.0,
                    "INVALID_SESSION",
                    "[]",
                    shadowScores,
                    true
            );
        }

        if (!championLoaded || !loadedModels.containsKey(CHAMPION_MODEL)) {
            double simulated = simulateRisk(session);
            String reasonJson = buildReasonJson(session, simulated);

            return new MlScoringResult(
                    simulated,
                    "SIMULATION",
                    reasonJson,
                    shadowScores,
                    true
            );
        }

        try {
            double championScore = scoreWithModel(loadedModels.get(CHAMPION_MODEL), session);

            for (Map.Entry<String, Classifier> entry : loadedModels.entrySet()) {
                String modelName = entry.getKey();
                if (CHAMPION_MODEL.equalsIgnoreCase(modelName)) {
                    continue;
                }

                try {
                    double score = scoreWithModel(entry.getValue(), session);
                    shadowScores.put(modelName, score);
                } catch (Exception shadowEx) {
                    System.err.println("WEKA: Shadow scoring failed for " + modelName + " -> " + shadowEx.getMessage());
                }
            }

            String reasonJson = buildReasonJson(session, championScore);

            return new MlScoringResult(
                    championScore,
                    CHAMPION_MODEL,
                    reasonJson,
                    shadowScores,
                    false
            );

        } catch (Exception e) {
            e.printStackTrace();

            double simulated = simulateRisk(session);
            String reasonJson = buildReasonJson(session, simulated);

            return new MlScoringResult(
                    simulated,
                    "SIMULATION_AFTER_ERROR",
                    reasonJson,
                    shadowScores,
                    true
            );
        }
    }

    private double scoreWithModel(Classifier model, PourSession session) throws Exception {
        Instance instance = new DenseInstance(dataStructure.numAttributes());
        instance.setDataset(dataStructure);

        instance.setValue(0, safe(session.getActualMl()));
        instance.setValue(1, safe(session.getDuration()));
        instance.setValue(2, safe(session.getAvgFlow()));

        instance.setMissing(dataStructure.classIndex());

        double[] probabilities = model.distributionForInstance(instance);
        int positiveIndex = getPositiveClassIndex();

        if (probabilities == null || positiveIndex < 0 || positiveIndex >= probabilities.length) {
            return 0.0;
        }

        return clamp01(probabilities[positiveIndex]);
    }

    private int getPositiveClassIndex() {
        Attribute cls = dataStructure.classAttribute();

        String[] positiveCandidates = new String[]{
            "ANOMALY", "ABNORMAL", "POSITIVE", "YES", "TRUE", "1"
        };

        for (String candidate : positiveCandidates) {
            for (int i = 0; i < cls.numValues(); i++) {
                if (candidate.equalsIgnoreCase(cls.value(i))) {
                    return i;
                }
            }
        }

        // fallback: lấy class cuối cùng làm positive
        return Math.max(0, cls.numValues() - 1);
    }

    private double simulateRisk(PourSession session) {
        double actual = safe(session.getActualMl());
        double duration = safe(session.getDuration());
        double avgFlow = safe(session.getAvgFlow());

        if (duration > 25.0 && actual < 400.0) {
            return 0.90;
        }

        if (avgFlow > 25.0) {
            return 0.85;
        }

        if (actual > 300.0) {
            return 0.75;
        }

        return 0.15;
    }

    /**
     * reason_json này là heuristic explanation cho app/prototype, không phải
     * native feature importance của chính model Weka.
     */
    private String buildReasonJson(PourSession session, double riskScore) {
        JsonArray arr = new JsonArray();

        addReason(arr, "WEKA_CHAMPION_SCORE", clamp01(riskScore), 1);

        double durationSignal = clamp01(safe(session.getDuration()) / 25.0);
        double avgFlowSignal = clamp01(safe(session.getAvgFlow()) / 25.0);

        double actualVsExpectedSignal = 0.0;
        double actualMl = safe(session.getActualMl());
        double duration = safe(session.getDuration());
        double avgFlow = safe(session.getAvgFlow());

        if (actualMl > 0.0) {
            double expectedAvg = duration > 0.0 ? (actualMl / duration) : 0.0;
            if (expectedAvg > 0.0) {
                actualVsExpectedSignal = clamp01(avgFlow / expectedAvg);
            }
        }

        addReason(arr, "AVG_FLOW_SIGNAL", avgFlowSignal, 2);
        addReason(arr, "DURATION_SIGNAL", durationSignal, 3);
        addReason(arr, "SESSION_PATTERN_SIGNAL", actualVsExpectedSignal, 4);

        return arr.toString();
    }

    private void addReason(JsonArray arr, String featureName, double contribution, int rank) {
        JsonObject obj = new JsonObject();
        obj.addProperty("feature_name", featureName);
        obj.addProperty("contribution", round4(clamp01(contribution)));
        obj.addProperty("importance_rank", rank);
        arr.add(obj);
    }

    private double safe(double v) {
        if (Double.isNaN(v) || Double.isInfinite(v)) {
            return 0.0;
        }
        return v;
    }

    private double clamp01(double v) {
        if (Double.isNaN(v) || Double.isInfinite(v)) {
            return 0.0;
        }
        if (v < 0.0) {
            return 0.0;
        }
        if (v > 1.0) {
            return 1.0;
        }
        return v;
    }

    private double round4(double v) {
        return Math.round(v * 10000.0) / 10000.0;
    }
}
