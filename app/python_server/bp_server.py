#!/usr/bin/env python3
"""
bp_server.py

HTTP server wrapper around third_party BP prediction logic.
"""

import os
import sys
from pathlib import Path
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent              # ...\app\python_server
REPO_ROOT = THIS_DIR.parents[1]                         # ...\bpSp02-estimation-ippg
THIRD_PARTY_DIR = REPO_ROOT / "third_party"

if str(THIRD_PARTY_DIR) not in sys.path:
    sys.path.insert(0, str(THIRD_PARTY_DIR))
# ---------------------------------------------------------
# Add third_party folder to Python path 
# ---------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent
THIRD_PARTY_DIR = BASE_DIR / "third_party"

if str(THIRD_PARTY_DIR) not in sys.path:
    sys.path.insert(0, str(THIRD_PARTY_DIR))

import predict_bp_from_matlab_fig as pred  

# ----------------------------
# Model cache (deterministic)
# ----------------------------
_MODEL_CACHE = {}  # model_path -> keras model


def _get_model_cached(model_path: str):
    m = _MODEL_CACHE.get(model_path)
    if m is None:
        m = pred.load_bp_model(model_path)
        _MODEL_CACHE[model_path] = m
    return m

# ---------------------------------------------------------

app = FastAPI(title="VitaSense BP Server", version="1.0")


class PredictRequest(BaseModel):
    input_path: str
    input_type: str  # "fig" or "mat"
    model_path: str
    win_s: float = 7.0
    stride_s: float = 1.0
    shuffle_test: bool = False
    shuffle_seed: int = 0


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/predict")
def predict(req: PredictRequest):
    input_type = req.input_type.strip().lower()

    if input_type not in ("fig", "mat"):
        raise HTTPException(status_code=400, detail="input_type must be 'fig' or 'mat'.")

    if not os.path.isfile(req.input_path):
        raise HTTPException(status_code=400, detail=f"input_path not found: {req.input_path}")

    if not os.path.isfile(req.model_path):
        raise HTTPException(status_code=400, detail=f"model_path not found: {req.model_path}")

    # ---------------------------------------------------------
    # Load signal
    # ---------------------------------------------------------
    if input_type == "fig":
        t, y = pred.extract_lineseries_from_fig(req.input_path)
        dt = float(pred.np.median(pred.np.diff(t)))
        if dt <= 0:
            raise HTTPException(status_code=400, detail="Invalid time axis in fig.")
        fs_in = 1.0 / dt
    else:
        y, fs_in, _ = pred.extract_timeseries_from_mat(req.input_path)

    # Window + resample
    # ---------------------------------------------------------
    X, centers_s = pred.window_and_resample(
        y=y,
        fs_in=fs_in,
        win_s=req.win_s,
        stride_s=req.stride_s,
        fs_out=125.0,
    )

    X_in = X[:, :, None]

    # ---------------------------------------------------------
    # Predict
    # ---------------------------------------------------------
    model = _get_model_cached(req.model_path)
    sbp, dbp = pred.predict_sbp_dbp(model, X_in)

    return {
        "fs_in": float(fs_in),
        "num_samples": int(len(y)),
        "duration_s": float(len(y) / fs_in),
        "num_windows": int(len(centers_s)),
        "centers_s": centers_s.astype(float).tolist(),
        "sbp": sbp.astype(float).tolist(),
        "dbp": dbp.astype(float).tolist(),
        "sbp_mean": float(pred.np.mean(sbp)),
        "sbp_std": float(pred.np.std(sbp)),
        "dbp_mean": float(pred.np.mean(dbp)),
        "dbp_std": float(pred.np.std(dbp)),
    }
    
@app.post("/predict_summary")
def predict_summary(req: PredictRequest):
    out = predict(req)  # reuse existing logic deterministically

    # Mirror-focused compact payload
    return {
        "input_path": out.get("input_path"),
        "input_type": out.get("input_type"),
        "model_path": out.get("model_path"),
        "fs_in": out.get("fs_in"),
        "duration_s": out.get("duration_s"),
        "win_s": out.get("win_s"),
        "stride_s": out.get("stride_s"),
        "num_windows": out.get("num_windows"),
        "sbp_mean": out.get("sbp_mean"),
        "sbp_std": out.get("sbp_std"),
        "dbp_mean": out.get("dbp_mean"),
        "dbp_std": out.get("dbp_std"),
    }