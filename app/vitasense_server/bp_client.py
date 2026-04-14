"""
bp_client.py
────────────────────────────────────────────────────────────────
Calls bp_server_patched.py /predict endpoint.

Machine-specific paths are loaded from local_config.py (gitignored).
Copy local_config.template.py → local_config.py and fill in your values.
────────────────────────────────────────────────────────────────
"""

from typing import Optional
import httpx
from pathlib import Path

# ── Load machine-specific config ─────────────────────────────────────────────
try:
    import local_config as _cfg
    BP_SERVER_URL      = _cfg.BP_SERVER_URL
    DEFAULT_MODEL_PATH = _cfg.BP_MODEL_PATH
except ImportError:
    raise RuntimeError(
        "[bp_client] local_config.py not found. "
        "Copy local_config.template.py → local_config.py and fill in your paths."
    )
except AttributeError as e:
    raise RuntimeError(
        f"[bp_client] local_config.py is missing a required field: {e}. "
        f"Check local_config.template.py for all required keys."
    )
# ─────────────────────────────────────────────────────────────────────────────


def predict_bp(fig_path: str, model_path: str = DEFAULT_MODEL_PATH) -> dict:
    """
    Sends fig_path to bp_server_patched /predict.
    Returns { sbp_mean, sbp_std, dbp_mean, dbp_std }.
    """
    if not Path(fig_path).is_file():
        raise FileNotFoundError(f"fig not found: {fig_path}")

    payload = {
        "input_path": str(Path(fig_path).resolve()),
        "input_type": "fig",
        "model_path": str(Path(model_path).resolve()),
        "win_s":      7.0,
        "stride_s":   1.0,
    }

    with httpx.Client(timeout=60.0) as client:
        resp = client.post(f"{BP_SERVER_URL}/predict", json=payload)
        resp.raise_for_status()
        data = resp.json()

    return {
        "sbp_mean": data.get("sbp_mean"),
        "sbp_std":  data.get("sbp_std"),
        "dbp_mean": data.get("dbp_mean"),
        "dbp_std":  data.get("dbp_std"),
    }


def is_bp_server_alive() -> bool:
    try:
        with httpx.Client(timeout=3.0) as client:
            r = client.get(f"{BP_SERVER_URL}/health")
            return r.status_code == 200
    except Exception:
        return False