"""
src/preprocessing.py
====================
Funciones reutilizables de feature engineering y encoding.

Replican la lógica del notebook 03_data_preparation.ipynb para que
cualquier nuevo dataset (e.g. datos del mes siguiente) pase exactamente
por el mismo pipeline de transformación que el modelo "vio" en
entrenamiento.

Uso típico:

    >>> from src.data_loader import load_raw_dataset
    >>> from src.preprocessing import add_engineered_features, prepare_features
    >>> df = load_raw_dataset()
    >>> df = add_engineered_features(df)
    >>> X, y = prepare_features(df, feature_names=feature_names_modelo)
"""
import pandas as pd
import numpy as np
from typing import Optional, List


# ------------------------------------------------------------
# Constantes del pipeline
# ------------------------------------------------------------
COLS_TO_DROP = [
    "customer_id",              # identificador, no es feature
    "as_of_date",               # constante en todo el dataset
    "churn_type",               # derivada del target → leakage
    "churn_probability_true",   # prob. real → leakage masivo
]

CATEGORICAL_COLS = [
    "region_name", "age_band", "marital_status",
    "policy_type", "payment_frequency",
]


def add_engineered_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Agrega las 5 features derivadas que el modelo espera.

    Features creadas
    ----------------
    - premium_shock        : 1 si premium_change_pct > 0.10
    - is_new_customer      : 1 si customer_tenure_months < 12
    - is_loyal_customer    : 1 si customer_tenure_months >= 60
    - rejected_claim_ratio : num_rejected_claims_12m / (num_claims_12m + 1)
    - risk_score           : suma de flags de riesgo (0-6)

    Parameters
    ----------
    df : pd.DataFrame
        Dataset crudo.

    Returns
    -------
    pd.DataFrame
        Dataset con las 5 columnas nuevas añadidas (copia).
    """
    df = df.copy()

    df["premium_shock"]        = (df["premium_change_pct"] > 0.10).astype(int)
    df["is_new_customer"]      = (df["customer_tenure_months"] < 12).astype(int)
    df["is_loyal_customer"]    = (df["customer_tenure_months"] >= 60).astype(int)
    df["rejected_claim_ratio"] = (
        df["num_rejected_claims_12m"] / (df["num_claims_12m"] + 1)
    ).round(4)
    df["risk_score"] = (
        df["missed_payment_flag"]
        + df["complaint_flag"]
        + df["coverage_downgrade_flag"]
        + df["quote_requested_flag"]
        + df["premium_shock"]
        + (df["late_payment_count_12m"] >= 2).astype(int)
    )

    return df


def encode_categoricals(
    df: pd.DataFrame,
    columns: List[str] = None,
    drop_first: bool = True,
) -> pd.DataFrame:
    """
    Aplica One-Hot Encoding con drop_first para evitar la trampa dummy.

    Parameters
    ----------
    df : pd.DataFrame
        Dataset con columnas categóricas.
    columns : list, opcional
        Lista de columnas a encodear. Si None, usa CATEGORICAL_COLS.
    drop_first : bool
        Si True (recomendado), descarta la primera dummy para evitar
        multicolinealidad perfecta.

    Returns
    -------
    pd.DataFrame
        Dataset con dummies en lugar de las columnas categóricas.
    """
    if columns is None:
        columns = [c for c in CATEGORICAL_COLS if c in df.columns]

    return pd.get_dummies(df, columns=columns, drop_first=drop_first, dtype=int)


def prepare_features(
    df: pd.DataFrame,
    feature_names: Optional[List[str]] = None,
    target_col: str = "churn_flag",
) -> tuple:
    """
    Pipeline completo de preparación: feature engineering + drop leakage + encoding.

    Si se provee `feature_names` (orden del modelo entrenado), garantiza
    que el output tenga las mismas columnas en el mismo orden — crítico
    para scoring en producción.

    Parameters
    ----------
    df : pd.DataFrame
        Dataset crudo.
    feature_names : list, opcional
        Lista de features que el modelo conoce (típicamente cargada con
        joblib.load("models/feature_names.pkl")).
    target_col : str
        Nombre de la variable objetivo (None si no hay target — caso scoring).

    Returns
    -------
    tuple
        (X, y) si target_col existe en df; (X, None) en caso contrario.
    """
    # 1) Feature engineering
    df_fe = add_engineered_features(df)

    # 2) Separar target si existe
    y = df_fe[target_col].copy() if target_col in df_fe.columns else None

    # 3) Excluir leakage + target
    cols_drop = [c for c in COLS_TO_DROP + [target_col] if c in df_fe.columns]
    X = df_fe.drop(columns=cols_drop)

    # 4) Encoding
    X_enc = encode_categoricals(X)

    # 5) Alinear con feature_names del modelo (si se proveyó)
    if feature_names is not None:
        X_enc = X_enc.reindex(columns=feature_names, fill_value=0)

    return X_enc, y
