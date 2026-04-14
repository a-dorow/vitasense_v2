"""
matlab_runner.py
────────────────────────────────────────────────────────────────
Runs iPPG_pipeline_kiosk via MATLAB Engine API for Python.
Engine starts once at server boot and stays alive between scans —
eliminates the 30-40s cold-start penalty on every scan.

Falls back to subprocess -batch if engine fails to start.

Machine-specific paths loaded from local_config.py (gitignored).
────────────────────────────────────────────────────────────────
"""

import subprocess
import glob
import os
import threading
import time
from pathlib import Path
from typing import Optional, Callable

# ── Load machine-specific config ─────────────────────────────────────────────
try:
    import local_config as _cfg
    MATLAB_EXE  = _cfg.MATLAB_EXE
    MATLAB_ROOT = _cfg.MATLAB_ROOT
except ImportError:
    raise RuntimeError(
        "[matlab_runner] local_config.py not found. "
        "Copy local_config.template.py → local_config.py and fill in your paths."
    )
except AttributeError as e:
    raise RuntimeError(
        f"[matlab_runner] local_config.py is missing a required field: {e}. "
        "Check local_config.template.py for all required keys."
    )
# ─────────────────────────────────────────────────────────────────────────────

_REPO       = Path(MATLAB_ROOT)
OUTPUT_FIGS = _REPO / "outputs" / "figs"
OUTPUT_LOGS = _REPO / "outputs" / "logs"

# ── MATLAB Engine state ───────────────────────────────────────────────────────
_engine       = None          # matlab.engine.MatlabEngine instance
_engine_ready = False         # True once addpath() has run
_engine_lock  = threading.Lock()
_engine_error = None          # set if engine failed to start

# Pre-import matlab.engine at module load time so it's available in threads
_matlab_engine_module = None
try:
    import matlab.engine as _matlab_engine_module
    print("[matlab_runner] matlab.engine imported successfully at module load.")
except ImportError as e:
    print(f"[matlab_runner] matlab.engine not available: {e}. Will use -batch fallback.")
# ─────────────────────────────────────────────────────────────────────────────


def start_engine_async():
    """
    Called once at server startup in a background thread.
    Starts the MATLAB engine and runs addpath so it's ready for scans.
    """
    t = threading.Thread(target=_init_engine, daemon=True)
    t.start()
    print("[matlab_runner] MATLAB engine warming up in background...")


def _init_engine():
    global _engine, _engine_ready, _engine_error
    import traceback
    try:
        print("[matlab_runner] Attempting matlab.engine import...")
        if _matlab_engine_module is None:
            raise ImportError("matlab.engine was not available at module load time.")
        print("[matlab_runner] Import OK. Calling start_matlab()...")
        eng = _matlab_engine_module.start_matlab()
        print("[matlab_runner] start_matlab() returned. Adding paths...")
        eng.addpath(eng.genpath(str(_REPO)), nargout=0)
        print(f"[matlab_runner] MATLAB engine ready. Paths added from: {_REPO}")
        with _engine_lock:
            _engine       = eng
            _engine_ready = True

    except ImportError as e:
        msg = (
            f"[matlab_runner] matlab.engine not found: {e}\n"
            "Install it with: cd 'C:\\Program Files\\MATLAB\\R2024a\\extern\\engines\\python' "
            "&& python setup.py install\n"
            "Falling back to -batch subprocess mode."
        )
        print(msg)
        with _engine_lock:
            _engine_error = f"matlab.engine not installed: {e}"

    except Exception as e:
        print(f"[matlab_runner] Engine startup failed: {e}")
        print(f"[matlab_runner] Traceback:\n{traceback.format_exc()}")
        print("[matlab_runner] Falling back to -batch subprocess mode.")
        with _engine_lock:
            _engine_error = str(e)


def engine_status() -> dict:
    """Returns engine readiness for the /health endpoint."""
    with _engine_lock:
        return {
            "ready": _engine_ready,
            "error": _engine_error,
            "mode":  "engine" if _engine_ready else "subprocess",
        }


# ── Main entry point ──────────────────────────────────────────────────────────
def run_pipeline(
    video_path: str,
    timeout: int = 300,
    progress_callback: Optional[Callable[[str], None]] = None,
) -> dict:
    """
    Runs run_pipeline_kiosk on video_path.
    Uses MATLAB engine if ready, otherwise falls back to -batch subprocess.
    """
    video_path = str(Path(video_path).resolve())

    OUTPUT_FIGS.mkdir(parents=True, exist_ok=True)
    OUTPUT_LOGS.mkdir(parents=True, exist_ok=True)

    if not Path(video_path).is_file():
        raise RuntimeError(f"Video file not found: {video_path}")

    with _engine_lock:
        use_engine = _engine_ready and _engine is not None

    if use_engine:
        print(f"[matlab_runner] Using MATLAB engine for: {video_path}")
        return _run_via_engine(video_path, timeout, progress_callback)
    else:
        print(f"[matlab_runner] Using -batch subprocess for: {video_path}")
        return _run_via_subprocess(video_path, timeout, progress_callback)


# ── Engine mode ───────────────────────────────────────────────────────────────
def _run_via_engine(
    video_path: str,
    timeout: int,
    progress_callback: Optional[Callable[[str], None]],
) -> dict:
    """
    Calls run_pipeline_kiosk directly via the live MATLAB engine.
    Since the engine doesn't stream stdout, we emit synthetic progress events.
    """
    import matlab

    steps = [
        "Configuring pipeline...",
        "Extracting facial signal...",
        "Computing SpO2...",
        "Running CHROM extraction...",
        "Computing heart rate...",
        "Finalising results...",
    ]

    # Emit progress steps on a timer while MATLAB runs
    step_idx   = [0]
    step_done  = [False]

    def _progress_ticker():
        while not step_done[0]:
            if step_idx[0] < len(steps):
                if progress_callback:
                    progress_callback(steps[step_idx[0]])
                step_idx[0] += 1
            time.sleep(8)   # emit a new step ~every 8s

    ticker = threading.Thread(target=_progress_ticker, daemon=True)
    ticker.start()

    try:
        with _engine_lock:
            eng = _engine

        hr_result, spo2_result = eng.run_pipeline_kiosk(
            video_path,
            'writeJson', True,
            nargout=2,
        )

        hr_bpm   = float(hr_result)   if hr_result   is not None else None
        spo2_pct = float(spo2_result) if spo2_result is not None else None

    finally:
        step_done[0] = True

    if progress_callback:
        progress_callback("Finalising results...")

    fig_path = _find_best_fig()

    print(f"[matlab_runner] Engine result — hr={hr_bpm}, spo2={spo2_pct}, fig={fig_path}")

    return {
        "hr_bpm":   hr_bpm,
        "spo2_pct": spo2_pct,
        "fig_path": fig_path,
    }


# ── Subprocess -batch fallback ────────────────────────────────────────────────
def _run_via_subprocess(
    video_path: str,
    timeout: int,
    progress_callback: Optional[Callable[[str], None]],
) -> dict:

    print(f"[matlab_runner] ── Starting -batch pipeline ──")
    print(f"[matlab_runner] MATLAB_EXE  : {MATLAB_EXE}")
    print(f"[matlab_runner] MATLAB_ROOT : {MATLAB_ROOT}")
    print(f"[matlab_runner] video_path  : {video_path}")

    if not Path(MATLAB_EXE).is_file():
        raise RuntimeError(f"MATLAB executable not found: {MATLAB_EXE}")

    matlab_cmd = (
        f"addpath(genpath('{MATLAB_ROOT}')); "
        f"try, "
        f"  [hr, spo2] = run_pipeline_kiosk("
        f"    '{video_path}', "
        f"    'writeJson', true"
        f"  ); "
        f"  fprintf('VITASENSE_HR=%.6f\\n',   hr); "
        f"  fprintf('VITASENSE_SPO2=%.6f\\n', spo2); "
        f"catch ME, "
        f"  fprintf('VITASENSE_ERROR=%s\\n', ME.message); "
        f"  fprintf('VITASENSE_STACK=%s\\n', ME.getReport('extended')); "
        f"end; "
        f"exit;"
    )

    proc = subprocess.Popen(
        [MATLAB_EXE, "-batch", matlab_cmd],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    all_output = []
    try:
        for line in proc.stdout:
            line = line.rstrip()
            all_output.append(line)
            print(f"[MATLAB] {line}")

            if line.startswith("VITASENSE_PROGRESS="):
                msg = line.split("=", 1)[1].strip()
                if progress_callback:
                    progress_callback(msg)

        proc.wait(timeout=timeout)

    except subprocess.TimeoutExpired:
        proc.kill()
        print(f"[matlab_runner] ERROR: MATLAB timed out after {timeout}s")
        raise

    stdout = "\n".join(all_output)
    print(f"[matlab_runner] ── MATLAB finished (return code {proc.returncode}) ──")

    error = _parse_str(stdout, "VITASENSE_ERROR")
    if error:
        print(f"[matlab_runner] VITASENSE_ERROR: {error}")
        raise RuntimeError(f"MATLAB pipeline error: {error}")

    hr_bpm   = _parse_float(stdout, "VITASENSE_HR")
    spo2_pct = _parse_float(stdout, "VITASENSE_SPO2")
    fig_path = _find_best_fig()

    print(f"[matlab_runner] hr_bpm={hr_bpm}, spo2_pct={spo2_pct}, fig_path={fig_path}")

    if hr_bpm   is None: print(f"[matlab_runner] WARNING: VITASENSE_HR not found.")
    if spo2_pct is None: print(f"[matlab_runner] WARNING: VITASENSE_SPO2 not found.")
    if fig_path is None:
        all_figs = glob.glob(str(_REPO / "**" / "*.fig"), recursive=True)
        print(f"[matlab_runner] WARNING: No .fig found. All figs: {all_figs}")

    return {
        "hr_bpm":   hr_bpm,
        "spo2_pct": spo2_pct,
        "fig_path": fig_path,
    }


# ── Helpers ───────────────────────────────────────────────────────────────────
def _parse_float(text: str, key: str) -> Optional[float]:
    for line in text.splitlines():
        if line.strip().startswith(f"{key}="):
            try:
                return float(line.split("=", 1)[1].strip())
            except ValueError:
                pass
    return None


def _parse_str(text: str, key: str) -> Optional[str]:
    for line in text.splitlines():
        if line.strip().startswith(f"{key}="):
            return line.split("=", 1)[1].strip()
    return None


def _find_best_fig() -> Optional[str]:
    search_patterns = [
        str(OUTPUT_FIGS / "**" / "*.fig"),
        str(_REPO / "**" / "*CHROM*iPPG*.fig"),
        str(_REPO / "**" / "*.fig"),
    ]
    for pattern in search_patterns:
        figs = glob.glob(pattern, recursive=True)
        if not figs:
            continue
        chrom_ippg = [f for f in figs
                      if "chrom" in os.path.basename(f).lower()
                      and "ippg"  in os.path.basename(f).lower()
                      and "psd"   not in os.path.basename(f).lower()]
        candidates = chrom_ippg if chrom_ippg else figs
        subj1 = [f for f in candidates if "subject_1" in os.path.basename(f).lower()]
        if subj1:
            candidates = subj1
        return max(candidates, key=os.path.getmtime)
    return None