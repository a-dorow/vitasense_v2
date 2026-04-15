#!/usr/bin/env python3
"""
bp_server_patched.py

HTTP server wrapper around third_party BP prediction logic.
Supports input_type: "fig", "mat", or "array".
"""

import os
import sys
from pathlib import Path
from typing import List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

THIS_DIR        = Path(__file__).resolve().parent
REPO_ROOT       = THIS_DIR.parents[1]
THIRD_PARTY_DIR = REPO_ROOT / "third_party"

if str(THIRD_PARTY_DIR) not in sys.path:
    sys.path.insert(0, str(THIRD_PARTY_DIR))

BASE_DIR        = Path(__file__).resolve().parent.parent
THIRD_PARTY_DIR = BASE_DIR / "third_party"

if str(THIRD_PARTY_DIR) not in sys.path:
    sys.path.insert(0, str(THIRD_PARTY_DIR))

import predict_bp_from_matlab_fig as pred
import numpy as np

# ── Model cache ───────────────────────────────────────────────────────────────
_MODEL_CACHE = {}

def _get_model_cached(model_path: str):
    m = _MODEL_CACHE.get(model_path)
    if m is None:
        m = pred.load_bp_model(model_path)
        _MODEL_CACHE[model_path] = m
    return m

# ─────────────────────────────────────────────────────────────────────────────

app = FastAPI(title="VitaSense BP Server", version="1.1")


class PredictRequest(BaseModel):
    # File-based inputs (fig / mat)
    input_path:   Optional[str]        = None
    input_type:   str                  = "fig"   # "fig" | "mat" | "array"
    # Array-based input
    signal:       Optional[List[float]] = None
    fs_hz:        Optional[float]       = None
    # Shared
    model_path:   str
    win_s:        float = 7.0
    stride_s:     float = 1.0
    shuffle_test: bool  = False
    shuffle_seed: int   = 0


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/predict")
def predict(req: PredictRequest):
    print("[bp_server] /predict called")
    input_type = req.input_type.strip().lower()

    if not os.path.isfile(req.model_path):
        raise HTTPException(status_code=400, detail=f"model_path not found: {req.model_path}")

    # ── Load signal ───────────────────────────────────────────────────────────
    if input_type == "array":
        # Signal arrives directly as a JSON list — no file needed
        if not req.signal or len(req.signal) < 10:
            raise HTTPException(status_code=400, detail="signal is empty or too short.")
        if not req.fs_hz or req.fs_hz <= 0:
            raise HTTPException(status_code=400, detail="fs_hz must be a positive number.")

        y     = np.array(req.signal, dtype=np.float64)
        fs_in = float(req.fs_hz)

    elif input_type == "fig":
        if not req.input_path or not os.path.isfile(req.input_path):
            raise HTTPException(status_code=400, detail=f"input_path not found: {req.input_path}")
        t, y = pred.extract_lineseries_from_fig(req.input_path)
        dt = float(pred.np.median(pred.np.diff(t)))
        if dt <= 0:
            raise HTTPException(status_code=400, detail="Invalid time axis in fig.")
        fs_in = 1.0 / dt

    elif input_type == "mat":
        if not req.input_path or not os.path.isfile(req.input_path):
            raise HTTPException(status_code=400, detail=f"input_path not found: {req.input_path}")
        y, fs_in, _ = pred.extract_timeseries_from_mat(req.input_path)

    else:
        raise HTTPException(status_code=400, detail="input_type must be 'fig', 'mat', or 'array'.")

    # ── Window + resample ─────────────────────────────────────────────────────
    X, centers_s = pred.window_and_resample(
        y=y,
        fs_in=fs_in,
        win_s=req.win_s,
        stride_s=req.stride_s,
        fs_out=125.0,
    )

    X_in = X[:, :, None]

    # ── Predict ───────────────────────────────────────────────────────────────
    model = _get_model_cached(req.model_path)
    sbp, dbp = pred.predict_sbp_dbp(model, X_in)

    return {
        "fs_in":       float(fs_in),
        "num_samples": int(len(y)),
        "duration_s":  float(len(y) / fs_in),
        "num_windows": int(len(centers_s)),
        "centers_s":   centers_s.astype(float).tolist(),
        "sbp":         sbp.astype(float).tolist(),
        "dbp":         dbp.astype(float).tolist(),
        "sbp_mean":    float(np.mean(sbp)),
        "sbp_std":     float(np.std(sbp)),
        "dbp_mean":    float(np.mean(dbp)),
        "dbp_std":     float(np.std(dbp)),
    }


@app.post("/predict_summary")
def predict_summary(req: PredictRequest):
    print("[bp_server] /predict_summary called")
    out = predict(req)
    return {
        "input_path":  req.input_path,
        "input_type":  req.input_type,
        "model_path":  req.model_path,
        "fs_in":       out.get("fs_in"),
        "duration_s":  out.get("duration_s"),
        "win_s":       req.win_s,
        "stride_s":    req.stride_s,
        "num_windows": out.get("num_windows"),
        "sbp_mean":    out.get("sbp_mean"),
        "sbp_std":     out.get("sbp_std"),
        "dbp_mean":    out.get("dbp_mean"),
        "dbp_std":     out.get("dbp_std"),
    }