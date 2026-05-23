"""
src/modeling.py
===============
Helpers para entrenamiento, evaluación y persistencia de modelos.

Encapsula la lógica de los notebooks 04, 05 y 07.

Uso típico:

    >>> from src.modeling import evaluate_model, save_model, score_portfolio, assign_risk_bucket
    >>> metrics = evaluate_model(model, X_test, y_test, name="XGBoost mid")
    >>> save_model(model, "xgb_mid_final.pkl")
    >>> scoring = score_portfolio(model, X_full, feature_names, customer_ids)
"""
from pathlib import Path
from typing import Dict, List, Optional
import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, average_precision_score, confusion_matrix,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR   = PROJECT_ROOT / "models"


# ============================================================
# Evaluación
# ============================================================
def evaluate_model(
    model, X_test, y_test,
    name: str = "model",
    verbose: bool = True,
) -> Dict:
    """
    Calcula el set estándar de métricas de clasificación binaria.

    Returns
    -------
    dict con keys:
        name, accuracy, precision, recall, f1, roc_auc, pr_auc,
        confusion_matrix (np.ndarray), y_pred, y_proba.
    """
    y_pred  = model.predict(X_test)
    y_proba = model.predict_proba(X_test)[:, 1]

    metrics = {
        "name"             : name,
        "accuracy"         : accuracy_score(y_test, y_pred),
        "precision"        : precision_score(y_test, y_pred, zero_division=0),
        "recall"           : recall_score(y_test, y_pred),
        "f1"               : f1_score(y_test, y_pred),
        "roc_auc"          : roc_auc_score(y_test, y_proba),
        "pr_auc"           : average_precision_score(y_test, y_proba),
        "confusion_matrix" : confusion_matrix(y_test, y_pred),
        "y_pred"           : y_pred,
        "y_proba"          : y_proba,
    }

    if verbose:
        cm = metrics["confusion_matrix"]
        print(f"\n=== {name} ===")
        print(f"  Accuracy : {metrics['accuracy']:.4f}")
        print(f"  Precision: {metrics['precision']:.4f}")
        print(f"  Recall   : {metrics['recall']:.4f}")
        print(f"  F1       : {metrics['f1']:.4f}")
        print(f"  ROC-AUC  : {metrics['roc_auc']:.4f}")
        print(f"  PR-AUC   : {metrics['pr_auc']:.4f}")
        print(f"  CM: TN={cm[0,0]} FP={cm[0,1]} FN={cm[1,0]} TP={cm[1,1]}")

    return metrics


# ============================================================
# Persistencia
# ============================================================
def save_model(model, filename: str, feature_names: Optional[List[str]] = None):
    """
    Guarda el modelo (y opcionalmente las features) en models/.

    Parameters
    ----------
    model : objeto del modelo (sklearn, xgboost)
    filename : str
        Nombre del archivo, e.g. "xgb_mid_final.pkl".
    feature_names : list, opcional
        Lista de features en el orden que el modelo espera.
    """
    MODELS_DIR.mkdir(exist_ok=True, parents=True)
    path = MODELS_DIR / filename
    joblib.dump(model, path)
    if feature_names is not None:
        joblib.dump(feature_names, MODELS_DIR / "feature_names.pkl")
    print(f"✅ Modelo guardado en {path}")


def load_model(filename: str = "xgb_mid_final.pkl"):
    """Carga un modelo serializado de models/."""
    return joblib.load(MODELS_DIR / filename)


def load_feature_names() -> List[str]:
    """Carga la lista de features esperadas por el modelo."""
    return joblib.load(MODELS_DIR / "feature_names.pkl")


# ============================================================
# Scoring y bucketing
# ============================================================
def assign_risk_bucket(prob: float) -> str:
    """
    Convierte una probabilidad de churn en un bucket operativo.

    Thresholds alineados con el análisis del notebook 05.
    """
    if prob >= 0.70: return "1_Critico"
    if prob >= 0.50: return "2_Alto"
    if prob >= 0.35: return "3_Medio"
    return "4_Bajo"


def score_portfolio(
    model,
    X: pd.DataFrame,
    customer_ids: pd.Series,
    feature_names: Optional[List[str]] = None,
) -> pd.DataFrame:
    """
    Aplica el modelo a un conjunto de clientes y devuelve la tabla operativa.

    Parameters
    ----------
    model : modelo entrenado.
    X : pd.DataFrame
        Features ya preprocesadas (ver src.preprocessing.prepare_features).
    customer_ids : pd.Series
        Identificadores de los clientes (alineados con X).
    feature_names : list, opcional
        Si se provee, reordena X para coincidir.

    Returns
    -------
    pd.DataFrame con columnas:
        customer_id, predicted_churn_probability, risk_bucket
    """
    if feature_names is not None:
        X = X.reindex(columns=feature_names, fill_value=0)

    proba = model.predict_proba(X)[:, 1]

    scoring = pd.DataFrame({
        "customer_id"                 : customer_ids.values,
        "predicted_churn_probability" : proba.round(4),
    })
    scoring["risk_bucket"] = scoring["predicted_churn_probability"].apply(assign_risk_bucket)

    return scoring


# ============================================================
# Análisis de threshold (notebook 05)
# ============================================================
def threshold_sweep(
    y_true,
    y_proba,
    thresholds: Optional[np.ndarray] = None,
) -> pd.DataFrame:
    """
    Barrido de thresholds: devuelve métricas para cada valor de threshold.

    Parameters
    ----------
    y_true : array-like
        Etiquetas reales.
    y_proba : array-like
        Probabilidades predichas para la clase positiva.
    thresholds : np.ndarray, opcional
        Valores a probar. Por defecto: np.arange(0.20, 0.81, 0.05).

    Returns
    -------
    pd.DataFrame con columnas:
        threshold, precision, recall, f1, alertas, TP, FP, FN, TN
    """
    if thresholds is None:
        thresholds = np.arange(0.20, 0.81, 0.05)

    filas = []
    for t in thresholds:
        y_pred = (np.asarray(y_proba) >= t).astype(int)
        cm = confusion_matrix(y_true, y_pred)
        filas.append({
            "threshold": float(t),
            "precision": precision_score(y_true, y_pred, zero_division=0),
            "recall"   : recall_score(y_true, y_pred),
            "f1"       : f1_score(y_true, y_pred),
            "alertas"  : int(y_pred.sum()),
            "TP"       : int(cm[1, 1]),
            "FP"       : int(cm[0, 1]),
            "FN"       : int(cm[1, 0]),
            "TN"       : int(cm[0, 0]),
        })
    return pd.DataFrame(filas)
