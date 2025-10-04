# train_models.py
import pandas as pd
import joblib
import os
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import OneHotEncoder
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
import warnings

warnings.filterwarnings("ignore", category=UserWarning)

# --- Configuration ---
CSV_FILE = 'synthetic_career_data.csv'
MODEL_DIR = 'models'
# ---------------------

def create_and_save_models():
    """Reads data, trains, and saves the salary and job prediction models."""
    try:
        df = pd.read_csv(CSV_FILE)
    except FileNotFoundError:
        print(f"Error: {CSV_FILE} not found. Please place the CSV file in the {os.getcwd()} directory.")
        return

    # --- Data Preparation ---
    df.dropna(subset=['salary_max', 'title', 'age', 'tenure_months'], inplace=True)
    df['remote_flag'] = df['remote_flag'].astype(int)

    # Use the last recorded entry for each user as the profile to train on
    df_current = df.sort_values(by='start_date').groupby('user_id').last().reset_index()

    # Define features
    categorical_features = ['education', 'location', 'title', 'industry']
    numerical_features = ['age', 'tenure_months', 'remote_flag']
    all_features = numerical_features + categorical_features

    # --- Preprocessing Pipeline ---
    # This transformer handles the One-Hot Encoding of categorical features
    preprocessor = ColumnTransformer(
        transformers=[
            ('cat', OneHotEncoder(handle_unknown='ignore'), categorical_features)],
        remainder='passthrough' # Keep numerical features as is
    )

    # --- 1. SALARY PREDICTOR MODEL (Regression) ---
    X_salary = df_current[all_features]
    y_salary = df_current['salary_max']

    # Create the full prediction pipeline
    salary_pipeline = Pipeline(steps=[
        ('preprocessor', preprocessor),
        ('regressor', LinearRegression())
    ])

    salary_pipeline.fit(X_salary, y_salary)

    # --- 2. JOB CLASSIFIER MODEL (Classification) ---
    X_job = df_current[all_features]
    y_job = df_current['title']

    # Create the full classification pipeline
    job_pipeline = Pipeline(steps=[
        ('preprocessor', preprocessor),
        ('classifier', RandomForestClassifier(n_estimators=100, random_state=42))
    ])

    job_pipeline.fit(X_job, y_job)

    # --- Saving Models and Features ---
    os.makedirs(MODEL_DIR, exist_ok=True)

    # Saving the entire pipeline simplifies the app.py code as it includes preprocessing
    joblib.dump(salary_pipeline, os.path.join(MODEL_DIR, 'salary_predictor_model.joblib'))
    joblib.dump(job_pipeline, os.path.join(MODEL_DIR, 'job_classifier_model.joblib'))

    # NOTE: The features are now implicitly handled by the pipeline, but we will save a placeholder list
    # for compatibility, as the app.py still references the features list.
    joblib.dump(all_features, os.path.join(MODEL_DIR, 'salary_model_features.joblib'))
    joblib.dump(all_features, os.path.join(MODEL_DIR, 'job_model_features.joblib'))

    print("\n✅ Models trained and saved successfully into the 'models' directory.")
    print("You can now run 'python app.py'")

if __name__ == '__main__':
    create_and_save_models()