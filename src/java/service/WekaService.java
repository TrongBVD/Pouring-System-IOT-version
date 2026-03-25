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

    // Champion model chính
    private static final String CHAMPION_MODEL = "Logistics.model";

    // Shadow models
    private static final String[] MODEL_FILES = new String[]{
        "Logistics.model",
        "NaivesBayes.model",
        "RandomTree.model",
        "Hoeffding.model"
    };

    /**
     * Schema đúng theo dataset train: 1) target_ml 2) actual_ml 3) duration_s
     * 4) peak_flow 5) avg_flow 6) class = {0,1}
     */
    private Instances dataStructure;

    private final Map<String, Classifier> loadedModels = new LinkedHashMap<>();
    private boolean championLoaded = false;

    public WekaService(String webInfPath) {
        buildDataStructure();
        loadModels(webInfPath);
    }

    private void buildDataStructure() {
        ArrayList<Attribute> attributes = new ArrayList<>();

        attributes.add(new Attribute("target_ml"));
        attributes.add(new Attribute("actual_ml"));
        attributes.add(new Attribute("duration_s"));
        attributes.add(new Attribute("peak_flow"));
        attributes.add(new Attribute("avg_flow"));

        ArrayList<String> classValues = new ArrayList<>();
        classValues.add("0"); // NORMAL
        classValues.add("1"); // ANOMALY

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

        System.out.println("WEKA webInfPath = " + webInfPath);
    }

    private String resolveModelPath(String webInfPath, String fileName) {
        if (webInfPath == null || webInfPath.trim().isEmpty()) {
            return null;
        }

        // Workaround nếu caller lỡ truyền ...\WEB-INF\model.model
        if (webInfPath.endsWith(".model")) {
            webInfPath = webInfPath.substring(0, webInfPath.length() - 6);
        }

        File direct = new File(webInfPath, fileName);
        if (direct.exists() && direct.isFile()) {
            return direct.getAbsolutePath();
        }

        File underModels = new File(new File(webInfPath, "models"), fileName);
        if (underModels.exists() && underModels.isFile()) {
            return underModels.getAbsolutePath();
        }

        File underModel = new File(new File(webInfPath, "model"), fileName);
        if (underModel.exists() && underModel.isFile()) {
            return underModel.getAbsolutePath();
        }

        System.out.println("WEKA checking: " + direct.getAbsolutePath());
        System.out.println("WEKA checking: " + underModels.getAbsolutePath());
        System.out.println("WEKA checking: " + underModel.getAbsolutePath());

        return null;
    }

    public double analyzeSessionRisk(PourSession session) {
        MlScoringResult result = scoreSession(session);
        if (result == null) {
            return 0.0;
        }
        return result.getChampionScore();
    }

    public String analyzeReasonJson(PourSession session) {
        MlScoringResult result = scoreSession(session);
        if (result == null) {
            return null;
        }
        return result.getReasonJson();
    }

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

        instance.setValue(0, safe(session.getTargetMl()));
        instance.setValue(1, safe(session.getActualMl()));
        instance.setValue(2, safe(session.getDuration()));
        instance.setValue(3, safe(session.getPeakFlow()));
        instance.setValue(4, safe(session.getAvgFlow()));

        instance.setMissing(dataStructure.classIndex());

        double[] probabilities = model.distributionForInstance(instance);

        int positiveIndex = getPositiveClassIndex();

        if (probabilities == null || positiveIndex < 0 || positiveIndex >= probabilities.length) {
            return 0.0;
        }

        System.out.println("WEKA input:"
                + " target_ml=" + safe(session.getTargetMl())
                + ", actual_ml=" + safe(session.getActualMl())
                + ", duration_s=" + safe(session.getDuration())
                + ", peak_flow=" + safe(session.getPeakFlow())
                + ", avg_flow=" + safe(session.getAvgFlow()));

        System.out.println("WEKA probabilities = " + java.util.Arrays.toString(probabilities));
        System.out.println("WEKA positiveIndex = " + positiveIndex);

        return clamp01(probabilities[positiveIndex]);
    }

    /**
     * Class của bạn là 0/1, trong đó: 0 = bình thường 1 = bất thường
     */
    private int getPositiveClassIndex() {
        Attribute cls = dataStructure.classAttribute();

        for (int i = 0; i < cls.numValues(); i++) {
            if ("1".equals(cls.value(i))) {
                return i;
            }
        }

        // fallback: class cuối
        return Math.max(0, cls.numValues() - 1);
    }

    /**
     * Fallback khi model lỗi hoặc chưa load được.
     */
    private double simulateRisk(PourSession session) {
        double target = safe(session.getTargetMl());
        double actual = safe(session.getActualMl());
        double duration = safe(session.getDuration());
        double peakFlow = safe(session.getPeakFlow());
        double avgFlow = safe(session.getAvgFlow());

        if (target > 0 && actual > target * 1.15) {
            return 0.90;
        }

        if (duration > 25.0 && actual < 0.80 * Math.max(target, 1.0)) {
            return 0.85;
        }

        if (peakFlow > 65.0) {
            return 0.80;
        }

        if (avgFlow > 25.0) {
            return 0.75;
        }

        return 0.15;
    }

    /**
     * reason_json heuristic để app/DB log giải thích.
     */
    private String buildReasonJson(PourSession session, double riskScore) {
        JsonArray arr = new JsonArray();

        addReason(arr, "WEKA_CHAMPION_SCORE", clamp01(riskScore), 1);

        double target = safe(session.getTargetMl());
        double actual = safe(session.getActualMl());
        double duration = safe(session.getDuration());
        double peakFlow = safe(session.getPeakFlow());
        double avgFlow = safe(session.getAvgFlow());

        double overTargetSignal = 0.0;
        if (target > 0.0) {
            overTargetSignal = clamp01(actual / target);
        }

        double durationSignal = clamp01(duration / 25.0);
        double peakFlowSignal = clamp01(peakFlow / 65.0);
        double avgFlowSignal = clamp01(avgFlow / 25.0);

        addReason(arr, "OVER_TARGET_SIGNAL", overTargetSignal, 2);
        addReason(arr, "PEAK_FLOW_SIGNAL", peakFlowSignal, 3);
        addReason(arr, "AVG_FLOW_SIGNAL", avgFlowSignal, 4);
        addReason(arr, "DURATION_SIGNAL", durationSignal, 5);

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
