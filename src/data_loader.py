"""
src/data_loader.py
==================
Funciones para cargar el dataset crudo y los datasets procesados.

Uso típico desde un notebook:

    >>> from src.data_loader import load_raw_dataset, load_processed_splits
    >>> df = load_raw_dataset()
    >>> X_train, X_test, y_train, y_test = load_processed_splits()
"""
from pathlib import Path
import pandas as pd

# ------------------------------------------------------------
# Rutas estándar del proyecto (relativas a la raíz del repo)
# ------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR       = PROJECT_ROOT / "data" / "raw"
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
RAW_CSV       = RAW_DIR / "insurance_policyholder_churn_synthetic.csv"


def load_raw_dataset(path: Path = RAW_CSV) -> pd.DataFrame:
    """
    Carga el dataset crudo desde data/raw/.

    Parameters
    ----------
    path : Path, opcional
        Ruta alternativa al CSV. Por defecto usa la ruta estándar del proyecto.

    Returns
    -------
    pd.DataFrame
        Dataset crudo con 50,000 filas × 40 columnas.

    Raises
    ------
    FileNotFoundError
        Si el archivo CSV no existe en la ruta esperada.
    """
    if not path.exists():
        raise FileNotFoundError(
            f"No se encontró el dataset crudo en: {path}\n"
            f"Verifica que el CSV esté en data/raw/."
        )
    return pd.read_csv(path)


def load_processed_splits(processed_dir: Path = PROCESSED_DIR):
    """
    Carga los splits train/test generados por el notebook 03.

    Parameters
    ----------
    processed_dir : Path, opcional
        Carpeta donde están los archivos parquet.

    Returns
    -------
    tuple
        (X_train, X_test, y_train, y_test) — todos como DataFrames/Series.
    """
    required = ["X_train.parquet", "X_test.parquet", "y_train.parquet", "y_test.parquet"]
    for f in required:
        if not (processed_dir / f).exists():
            raise FileNotFoundError(
                f"Falta {f} en {processed_dir}. "
                f"Ejecuta primero el notebook 03_data_preparation.ipynb."
            )

    X_train = pd.read_parquet(processed_dir / "X_train.parquet")
    X_test  = pd.read_parquet(processed_dir / "X_test.parquet")
    y_train = pd.read_parquet(processed_dir / "y_train.parquet")["churn_flag"]
    y_test  = pd.read_parquet(processed_dir / "y_test.parquet")["churn_flag"]

    return X_train, X_test, y_train, y_test


def get_data_dictionary() -> pd.DataFrame:
    """Carga el diccionario de datos desde data/."""
    path = PROJECT_ROOT / "data" / "data_dictionary.csv"
    if not path.exists():
        raise FileNotFoundError(f"No se encontró el diccionario en: {path}")
    return pd.read_csv(path)
