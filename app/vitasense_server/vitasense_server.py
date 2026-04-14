"""
vitasense_server.py
────────────────────────────────────────────────────────────────
Main VitaSense kiosk backend.

Endpoints:
  GET  /health         → liveness check
  POST /analyze        → upload video, starts pipeline, returns job_id
  GET  /progress/{id} → SSE stream of pipeline progress + final result
  GET  /              → serve React UI

Run from app/vitasense_server/:
  uvicorn vitasense_server:app --host 0.0.0.0 --port 6767 --reload
────────────────────────────────────────────────────────────────
"""

import os
import uuid
import asyncio
import tempfile
import subprocess
import threading
import json
from pathlib import Path
from subprocess import TimeoutExpired
from concurrent.futures import ThreadPoolExecutor
from typing import Optional

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse

import matlab_runner
import bp_client

# ── Paths ─────────────────────────────────────────────────────────────────────
THIS_DIR   = Path(__file__).resolve().parent
APP_DIR    = THIS_DIR.parent
UI_DIST    = APP_DIR / "ui" / "dist"
UPLOAD_DIR = Path(tempfile.gettempdir()) / "vitasense_uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

# Single worker — MATLAB can only run one pipeline at a time anyway
executor = ThreadPoolExecutor(max_workers=1)

try:
    import local_config as _cfg
    FFMPEG_EXE = _cfg.FFMPEG_EXE
except (ImportError, AttributeError):
    FFMPEG_EXE = "ffmpeg"

# ── Job store ─────────────────────────────────────────────────────────────────
# job_id -> { progress: [str], result: dict|None, error: str|None, done: bool }
_jobs: dict = {}
_jobs_lock  = threading.Lock()
# ─────────────────────────────────────────────────────────────────────────────

app = FastAPI(title="VitaSense Kiosk", version="2.0")


@app.on_event("startup")
def on_startup():
    """Start MATLAB engine in background when server boots."""
    matlab_runner.start_engine_async()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health ────────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {
        "ok":        True,
        "bp_server": bp_client.is_bp_server_alive(),
        "ffmpeg":    _check_ffmpeg(),
        "matlab":    matlab_runner.engine_status(),
    }


# ── Upload → job_id ───────────────────────────────────────────────────────────
@app.post("/analyze")
async def analyze(video: UploadFile = File(...)):
    """
    Saves video, registers job, kicks off background thread, returns job_id.
    Client connects to /progress/{job_id} for SSE updates.
    """
    uid         = uuid.uuid4().hex
    subject_tag = f"subject_1_{uid[:8]}"
    webm_path   = UPLOAD_DIR / f"{subject_tag}.webm"
    mp4_path    = UPLOAD_DIR / f"{subject_tag}.mp4"

    try:
        webm_path.write_bytes(await video.read())
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save upload: {e}")

    job_id = uid
    with _jobs_lock:
        _jobs[job_id] = {
            "progress": [],
            "result":   None,
            "error":    None,
            "done":     False,
        }

    # Start pipeline in a real background thread (not awaited)
    t = threading.Thread(
        target=_run_pipeline_job,
        args=(job_id, webm_path, mp4_path),
        daemon=True,
    )
    t.start()

    print(f"[server] Job {job_id} started, thread alive: {t.is_alive()}")
    return JSONResponse({"job_id": job_id})


# ── SSE progress stream ───────────────────────────────────────────────────────
@app.get("/progress/{job_id}")
async def progress_stream(job_id: str):
    """
    SSE stream — stays open until pipeline finishes.
    Sends keepalive comments every 5s so the connection doesn't drop.
    """
    if job_id not in _jobs:
        raise HTTPException(status_code=404, detail="Job not found")

    async def event_stream():
        sent = 0
        keepalive = 0

        while True:
            with _jobs_lock:
                job  = _jobs.get(job_id, {})
                msgs = list(job.get("progress", []))
                done = job.get("done", False)
                err  = job.get("error")
                res  = job.get("result")

            # Send any new progress messages
            while sent < len(msgs):
                payload = json.dumps({"type": "progress", "message": msgs[sent]})
                yield f"data: {payload}\n\n"
                sent += 1

            if done:
                if err:
                    payload = json.dumps({"type": "error", "message": err})
                else:
                    payload = json.dumps({"type": "result", "data": res or {}})
                yield f"data: {payload}\n\n"
                break

            # Keepalive comment every ~5s so browser doesn't close connection
            keepalive += 1
            if keepalive % 10 == 0:
                yield f": keepalive\n\n"

            await asyncio.sleep(0.5)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":      "no-cache",
            "X-Accel-Buffering":  "no",
            "Connection":         "keep-alive",
        },
    )


# ── Pipeline job (runs in background thread) ──────────────────────────────────
def _run_pipeline_job(job_id: str, webm_path: Path, mp4_path: Path):

    def push(msg: str):
        print(f"[job:{job_id[:8]}] {msg}")
        with _jobs_lock:
            if job_id in _jobs:
                _jobs[job_id]["progress"].append(msg)

    def finish(result: Optional[dict] = None, error: Optional[str] = None):
        print(f"[job:{job_id[:8]}] {'DONE' if result else 'ERROR'}: {result or error}")
        with _jobs_lock:
            if job_id in _jobs:
                _jobs[job_id]["result"] = result
                _jobs[job_id]["error"]  = error
                _jobs[job_id]["done"]   = True

    try:
        # 1. Convert webm → mp4
        push("Converting video...")
        _convert_to_mp4(webm_path, mp4_path)
        push("Video ready.")

        # 2. MATLAB pipeline
        push("Starting MATLAB (this takes ~30s to launch)...")
        matlab_result = matlab_runner.run_pipeline(
            str(mp4_path),
            progress_callback=push,
        )

        hr_bpm   = matlab_result.get("hr_bpm")
        spo2_pct = matlab_result.get("spo2_pct")
        fig_path = matlab_result.get("fig_path")

        # 3. BP prediction
        bp_data = {}
        if fig_path and bp_client.is_bp_server_alive():
            push("Estimating blood pressure...")
            try:
                bp_data = bp_client.predict_bp(fig_path)
            except Exception as e:
                print(f"[job:{job_id[:8]}] BP error: {e}")
                bp_data = {}

        # Clamp BP to physiological limits
        if bp_data.get("sbp_mean") is not None:
            sbp = bp_data["sbp_mean"]
            if sbp < 70 or sbp > 180:
                print(f"[job] SBP {sbp:.1f} outside limits, discarding BP")
                bp_data = {}
        if bp_data.get("dbp_mean") is not None:
            dbp = bp_data["dbp_mean"]
            if dbp < 40 or dbp > 120:
                print(f"[job] DBP {dbp:.1f} outside limits, discarding BP")
                bp_data = {}

        push("Done!")
        finish(result={
            "hr_bpm":   hr_bpm,
            "spo2_pct": spo2_pct,
            **bp_data,
        })

    except TimeoutExpired:
        finish(error="MATLAB pipeline timed out. Try increasing timeout in matlab_runner.py.")
    except RuntimeError as e:
        finish(error=str(e))
    except Exception as e:
        finish(error=f"Unexpected error: {e}")
    finally:
        _cleanup(webm_path, mp4_path)


# ── Serve React UI ────────────────────────────────────────────────────────────
if UI_DIST.exists():
    app.mount("/assets", StaticFiles(directory=UI_DIST / "assets"), name="assets")

    @app.get("/")
    def root():
        return FileResponse(UI_DIST / "index.html")

    @app.get("/{full_path:path}")
    def spa_fallback(full_path: str):
        candidate = UI_DIST / full_path
        if candidate.exists() and candidate.is_file():
            return FileResponse(candidate)
        return FileResponse(UI_DIST / "index.html")
else:
    @app.get("/")
    def no_build():
        return {"message": "UI not built yet. Run: cd app/ui && npm install && npm run build"}


# ── Helpers ───────────────────────────────────────────────────────────────────
def _convert_to_mp4(webm_path: Path, mp4_path: Path) -> None:
    cmd = [
        FFMPEG_EXE, "-y",
        "-i",       str(webm_path),
        "-c:v",     "libx264",
        "-preset",  "fast",
        "-crf",     "18",
        "-pix_fmt", "yuv420p",
        "-an",
        str(mp4_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr[-500:]}")
    if not mp4_path.exists() or mp4_path.stat().st_size == 0:
        raise RuntimeError("ffmpeg produced empty output.")


def _check_ffmpeg() -> bool:
    try:
        r = subprocess.run([FFMPEG_EXE, "-version"], capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False


def _cleanup(*paths: Path) -> None:
    for p in paths:
        try:
            p.unlink(missing_ok=True)
        except Exception:
            pass