#!/usr/bin/env python3
"""
bp_server.py

HTTP server wrapper around third_party BP prediction logic.
"""

import os
import sys
import subprocess
import shlex
import json
from pathlib import Path
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

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


class PipelineRequest(BaseModel):
    video_path: str
    json_path: str | None = None
    do_popup: bool = False


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
        "input_path": req.input_path,
        "input_type": input_type,
        "model_path": req.model_path,
        "win_s": float(req.win_s),
        "stride_s": float(req.stride_s),
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


def _escape_matlab_string(value: str) -> str:
    return value.replace("'", "''")


def _build_matlab_command(video_path: str, json_path: str, do_popup: bool) -> str:
    esc_video = _escape_matlab_string(video_path)
    esc_json = _escape_matlab_string(json_path)
    popup = "true" if do_popup else "false"

    return (
        "try, "
        f"[hr_bpm, spo2_pct] = run_pipeline_on_video('{esc_video}', "
        f"'doPopup', {popup}, 'writeJson', true, 'jsonPath', '{esc_json}'); "
        "disp(jsonencode(struct('ok', true, 'hr_bpm', hr_bpm, 'spo2_pct', spo2_pct))); "
        "catch ME, "
        "disp(jsonencode(struct('ok', false, 'error', ME.message))); exit(1); "
        "end; exit(0);"
    )


@app.post("/run_pipeline")
def run_pipeline(req: PipelineRequest):
    if not os.path.isfile(req.video_path):
        raise HTTPException(status_code=400, detail=f"video_path not found: {req.video_path}")

    if req.json_path:
        json_path = req.json_path
    else:
        vp, vn = os.path.split(req.video_path)
        stem, _ = os.path.splitext(vn)
        json_path = os.path.join(vp, f"{stem}_vitals.json")

    matlab_expr = _build_matlab_command(req.video_path, json_path, req.do_popup)
    matlab_cmd = os.getenv("MATLAB_CMD", "matlab")
    command = f"{matlab_cmd} -batch {shlex.quote(matlab_expr)}"

    try:
        completed = subprocess.run(
            command,
            shell=True,
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise HTTPException(
            status_code=500,
            detail={
                "message": "MATLAB pipeline execution failed",
                "stdout": exc.stdout,
                "stderr": exc.stderr,
            },
        ) from exc

    if not os.path.isfile(json_path):
        raise HTTPException(
            status_code=500,
            detail={
                "message": "Pipeline completed but JSON was not written",
                "stdout": completed.stdout,
                "stderr": completed.stderr,
                "json_path": json_path,
            },
        )

    try:
        with open(json_path, "r", encoding="utf-8") as f:
            vitals = json.load(f)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to read JSON output: {exc}") from exc

    return {
        "ok": True,
        "json_path": json_path,
        "vitals": vitals,
    }
