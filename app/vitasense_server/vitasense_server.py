"""
vitasense_server.py
────────────────────────────────────────────────────────────────
Main VitaSense kiosk backend.

Endpoints:
  GET  /health         → liveness check
  POST /analyze        → upload video, starts pipeline, returns job_id
  GET  /progress/{id} → SSE stream of pipeline progress + chunked results
  GET  /              → serve React UI

SSE event types:
  { type: "progress",        message: str }
  { type: "vitals_partial",  hr_bpm, spo2_pct }   ← fires as soon as MATLAB returns
  { type: "vitals_partial",  sbp_mean, sbp_std, dbp_mean, dbp_std } ← fires after BP server
  { type: "result",          data: { all four vitals } }  ← final complete payload
  { type: "error",           message: str }

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

executor = ThreadPoolExecutor(max_workers=1)

try:
    import local_config as _cfg
    FFMPEG_EXE = _cfg.FFMPEG_EXE
except (ImportError, AttributeError):
    FFMPEG_EXE = "ffmpeg"

# ── Job store ─────────────────────────────────────────────────────────────────
# job_id -> {
#   progress:  [str],
#   partials:  [dict],   ← list of partial vital chunks
#   result:    dict|None,
#   error:     str|None,
#   done:      bool
# }
_jobs: dict = {}
_jobs_lock  = threading.Lock()
# ─────────────────────────────────────────────────────────────────────────────

app = FastAPI(title="VitaSense Kiosk", version="2.1")


@app.on_event("startup")
def on_startup():
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
            "partials": [],
            "result":   None,
            "error":    None,
            "done":     False,
        }

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
    if job_id not in _jobs:
        raise HTTPException(status_code=404, detail="Job not found")

    async def event_stream():
        sent_progress = 0
        sent_partials = 0
        keepalive     = 0

        while True:
            with _jobs_lock:
                job      = _jobs.get(job_id, {})
                msgs     = list(job.get("progress", []))
                partials = list(job.get("partials", []))
                done     = job.get("done", False)
                err      = job.get("error")
                res      = job.get("result")

            # Progress messages
            while sent_progress < len(msgs):
                payload = json.dumps({"type": "progress", "message": msgs[sent_progress]})
                yield f"data: {payload}\n\n"
                sent_progress += 1

            # Partial vital chunks (hr/spo2 first, then bp)
            while sent_partials < len(partials):
                payload = json.dumps({"type": "vitals_partial", **partials[sent_partials]})
                yield f"data: {payload}\n\n"
                sent_partials += 1

            if done:
                if err:
                    payload = json.dumps({"type": "error", "message": err})
                else:
                    payload = json.dumps({"type": "result", "data": res or {}})
                yield f"data: {payload}\n\n"
                break

            keepalive += 1
            if keepalive % 10 == 0:
                yield f": keepalive\n\n"

            await asyncio.sleep(0.5)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":     "no-cache",
            "X-Accel-Buffering": "no",
            "Connection":        "keep-alive",
        },
    )


# ── Pipeline job (runs in background thread) ──────────────────────────────────
def _run_pipeline_job(job_id: str, webm_path: Path, mp4_path: Path):

    def push(msg: str):
        print(f"[job:{job_id[:8]}] {msg}")
        with _jobs_lock:
            if job_id in _jobs:
                _jobs[job_id]["progress"].append(msg)

    def push_partial(chunk: dict):
        """Push a partial vitals chunk — SSE will stream it immediately."""
        print(f"[job:{job_id[:8]}] partial: {chunk}")
        with _jobs_lock:
            if job_id in _jobs:
                _jobs[job_id]["partials"].append(chunk)

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
        # partial_callback fires as soon as MATLAB returns hr + spo2
        push("Starting MATLAB pipeline...")
        matlab_result = matlab_runner.run_pipeline(
            str(mp4_path),
            progress_callback=push,
            partial_callback=push_partial,   # ← streams hr/spo2 immediately
        )

        hr_bpm      = matlab_result.get("hr_bpm")
        spo2_pct    = matlab_result.get("spo2_pct")
        ippg_signal = matlab_result.get("ippg_signal", [])
        fs_hz       = matlab_result.get("fs_hz", 30.0)

        # 3. BP prediction — runs after MATLAB, result streamed as second partial
        bp_data = {}
        if ippg_signal and len(ippg_signal) >= 10 and bp_client.is_bp_server_alive():
            push("Estimating blood pressure...")
            try:
                bp_data = bp_client.predict_bp_from_array(ippg_signal, fs_hz)

                # Clamp BP to physiological limits
                sbp = bp_data.get("sbp_mean")
                dbp = bp_data.get("dbp_mean")

                if sbp is not None and (sbp < 70 or sbp > 180):
                    print(f"[job] SBP {sbp:.1f} outside limits, discarding BP")
                    bp_data = {}
                elif dbp is not None and (dbp < 40 or dbp > 120):
                    print(f"[job] DBP {dbp:.1f} outside limits, discarding BP")
                    bp_data = {}
                else:
                    # Stream BP as its own partial chunk
                    push_partial(bp_data)

            except Exception as e:
                print(f"[job:{job_id[:8]}] BP error: {e}")
                bp_data = {}
        else:
            if not ippg_signal or len(ippg_signal) < 10:
                print(f"[job:{job_id[:8]}] No signal for BP prediction.")
            if not bp_client.is_bp_server_alive():
                print(f"[job:{job_id[:8]}] BP server not alive, skipping.")

        push("Done!")
        finish(result={
            "hr_bpm":   hr_bpm,
            "spo2_pct": spo2_pct,
            **bp_data,
        })

    except TimeoutExpired:
        finish(error="MATLAB pipeline timed out.")
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