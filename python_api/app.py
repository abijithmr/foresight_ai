# app.py
from flask import Flask, request, jsonify
from flask_cors import CORS
import pandas as pd
import joblib
import numpy as np
import os
from typing import Dict, Union
from flask_host_restrict import host_restrict

# --- CONFIGURATION (Paths updated to load models from the 'models' subdirectory) ---
MODEL_DIR = "models"
SALARY_MODEL_FILE = os.path.join(MODEL_DIR, "salary_predictor_model.joblib")
SALARY_FEATURE_FILE = os.path.join(MODEL_DIR, "salary_model_features.joblib")
JOB_MODEL_FILE = os.path.join(MODEL_DIR, "job_classifier_model.joblib")
JOB_FEATURE_FILE = os.path.join(MODEL_DIR, "job_model_features.joblib")
# ----------------------------------------------------------------------------------


# --- 1. HEALTH HEURISTIC FUNCTION ---
def predict_health_increase(avg_sleep_hours: float) -> float:
    """
    Simple rule-based heuristic for health increase factor based on sleep hours.
    Returns a factor (e.g., 1.10 for 10% increase).
    """
    base_factor = 1.0
    optimal_sleep_min = 7.0
    optimal_sleep_max = 8.5
    max_increase_percent = 10.0 # Max health boost set to 10%

    if optimal_sleep_min <= avg_sleep_hours <= optimal_sleep_max:
        increase = max_increase_percent
    elif avg_sleep_hours < optimal_sleep_min:
        # Penalty for lack of sleep
        deviation = optimal_sleep_min - avg_sleep_hours
        increase = max(0, max_increase_percent - (deviation * 5))
    else:
        # Penalty for oversleeping
        deviation = avg_sleep_hours - optimal_sleep_max
        increase = max(0, max_increase_percent - (deviation * 2))

    return base_factor + (increase / 100.0)

# --- 2. INTEGRATED PREDICTION FUNCTION ---
def predict_future_twin(user_input_data: Dict[str, Union[int, float, str]], projection_months: int) -> Dict:
    """
    Core logic to predict the future state of the Digital Twin.
    """

    # --- Time Projection ---
    age_increase_years = projection_months // 12
    projected_age = user_input_data['age'] + age_increase_years
    projected_tenure = user_input_data['tenure_months'] + projection_months

    # --- Health Prediction ---
    # Use .get with a default value to safely access sleep hours
    sleep_factor = predict_health_increase(user_input_data.get('avg_sleep_hours', 7.5))
    health_percent_increase = (sleep_factor - 1.0) * 100

    # --- Setup DataFrame for ML Models ---
    # Create a DataFrame with the user's current data (features)
    twin_df = pd.DataFrame([{
        **user_input_data, # Includes original categorical features
        'age': projected_age,
        'tenure_months': projected_tenure
    }])

    # --- Career Prediction (Salary and Job) ---
    predicted_salary = None
    recommended_jobs = None

    # Salary Prediction
    try:
        # Load the entire pipeline (preprocessor + model)
        salary_pipeline = joblib.load(SALARY_MODEL_FILE)

        # NOTE: We load the feature list but the pipeline handles selection and encoding
        # We ensure the input DataFrame has all necessary columns defined in train_models.py

        # Prepare data by explicitly selecting necessary columns used in the training script
        X_salary = twin_df[['education', 'location', 'title', 'industry', 'age', 'tenure_months', 'remote_flag']]

        # Predict uses the pipeline to preprocess and then predict
        predicted_salary = salary_pipeline.predict(X_salary)[0]
    except Exception as e:
        print(f"Error in Salary Prediction: {e}. Ensure models are trained and saved correctly.")
        predicted_salary = -1.0

    # Job Classification (Next Job Title)
    try:
        # Load the entire pipeline (preprocessor + model)
        job_pipeline = joblib.load(JOB_MODEL_FILE)

        # Prepare data by explicitly selecting necessary columns used in the training script
        X_job = twin_df[['education', 'location', 'title', 'industry', 'age', 'tenure_months', 'remote_flag']]

        # Predict probabilities to get the top likely jobs
        probas = job_pipeline.predict_proba(X_job)[0]
        classes = job_pipeline.named_steps['classifier'].classes_

        top_indices = np.argsort(probas)[::-1][:3] # Get top 3 indices
        recommended_jobs = [classes[i] for i in top_indices]

    except Exception as e:
        print(f"Error in Job Classification: {e}. Ensure models are trained and saved correctly.")
        recommended_jobs = ["N/A"]

    # --- Final Results Package ---
    return {
        "projected_age": int(projected_age),
        "health_increase_percent": round(health_percent_increase, 1),
        # Convert prediction to float and format, handling the error case
        "predicted_salary": round(float(predicted_salary), 2) if isinstance(predicted_salary, (float, np.float64)) and predicted_salary != -1.0 else "N/A",
        "recommended_jobs": recommended_jobs,
        "time_projection_months": projection_months
    }

# --- 3. FLASK APP SETUP ---
app = Flask(__name__)
if not app.debug:
    host_restrict.HostRestrict(app,[
        "https://foresight-ai.onrender.com"

    ])
CORS(app) # Crucial for allowing Flutter (frontend) to connect

@app.route('/predict_twin', methods=['POST'])
def handle_prediction():
    """
    API endpoint that receives data from the Flutter app and returns predictions.
    """

    if not request.is_json:
        return jsonify({"error": "Request must be JSON"}), 400

    data = request.json

    # Validation
    if not all(key in data for key in ['user_data', 'projection_months']):
        return jsonify({"error": "Missing 'user_data' or 'projection_months'."}), 400

    user_data = data['user_data']
    projection_months = data['projection_months']

    if not isinstance(projection_months, int) or projection_months not in [6, 24, 60]:
        return jsonify({"error": "Invalid 'projection_months'. Must be 6, 24, or 60."}), 400

    try:
        # Run the core prediction logic
        prediction_result = predict_future_twin(user_data, projection_months)
        return jsonify(prediction_result)
    except Exception as e:
        print(f"Unhandled server error: {e}")
        return jsonify({"error": f"Internal server error: {e}"}), 500

# --- 4. RUN THE SERVER ---
if __name__ == '__main__':
    # Use 0.0.0.0 to make the server accessible from outside the local machine (like your phone/emulator)
    print("Starting Digital Twin Prediction API on port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=True)