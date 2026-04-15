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
_engine       = None
_engine_ready = False
_engine_lock  = threading.Lock()
_engine_error = None

_matlab_engine_module = None
try:
    import matlab.engine as _matlab_engine_module
    print("[matlab_runner] matlab.engine imported successfully at module load.")
except ImportError as e:
    print(f"[matlab_runner] matlab.engine not available: {e}. Will use -batch fallback.")
# ─────────────────────────────────────────────────────────────────────────────


def start_engine_async():
    """Called once at server startup in a background thread."""
    t = threading.Thread(target=_init_engine, daemon=True)
    t.start()
    print("[matlab_runner] MATLAB engine warming up in background...")


def _init_engine():
    global _engine, _engine_ready, _engine_error
    import traceback
    try:
        if _matlab_engine_module is None:
            raise ImportError("matlab.engine was not available at module load time.")
        print("[matlab_runner] Calling start_matlab()...")
        eng = _matlab_engine_module.start_matlab()
        eng.addpath(eng.genpath(str(_REPO)), nargout=0)
        print(f"[matlab_runner] MATLAB engine ready. Paths added from: {_REPO}")
        with _engine_lock:
            _engine       = eng
            _engine_ready = True
    except ImportError as e:
        print(f"[matlab_runner] matlab.engine not found: {e}. Falling back to -batch.")
        with _engine_lock:
            _engine_error = f"matlab.engine not installed: {e}"
    except Exception as e:
        print(f"[matlab_runner] Engine startup failed: {e}\n{traceback.format_exc()}")
        with _engine_lock:
            _engine_error = str(e)


def engine_status() -> dict:
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
    partial_callback: Optional[Callable[[dict], None]] = None,
) -> dict:
    """
    Runs run_pipeline_kiosk on video_path.

    partial_callback(dict) is called as soon as MATLAB returns with
    { hr_bpm, spo2_pct } so the server can stream a partial SSE event
    before BP is computed.

    Returns full dict: { hr_bpm, spo2_pct, ippg_signal, fs_hz }
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
        return _run_via_engine(video_path, timeout, progress_callback, partial_callback)
    else:
        print(f"[matlab_runner] Using -batch subprocess for: {video_path}")
        return _run_via_subprocess(video_path, timeout, progress_callback, partial_callback)


# ── Engine mode ───────────────────────────────────────────────────────────────
def _run_via_engine(
    video_path: str,
    timeout: int,
    progress_callback: Optional[Callable[[str], None]],
    partial_callback: Optional[Callable[[dict], None]],
) -> dict:
    import matlab

    steps = [
        "Configuring pipeline...",
        "Extracting facial signal...",
        "Computing SpO2...",
        "Running CHROM extraction...",
        "Computing heart rate...",
        "Finalising results...",
    ]

    step_idx  = [0]
    step_done = [False]

    def _progress_ticker():
        while not step_done[0]:
            if step_idx[0] < len(steps):
                if progress_callback:
                    progress_callback(steps[step_idx[0]])
                step_idx[0] += 1
            time.sleep(8)

    ticker = threading.Thread(target=_progress_ticker, daemon=True)
    ticker.start()

    try:
        with _engine_lock:
            eng = _engine

        # run_pipeline_kiosk now returns 4 values: hr, spo2, ippg_signal, Fs
        hr_result, spo2_result, ippg_matlab, fs_result = eng.run_pipeline_kiosk(
            video_path,
            'writeJson', False,
            nargout=4,
        )

        hr_bpm   = float(hr_result)   if hr_result   is not None else None
        spo2_pct = float(spo2_result) if spo2_result is not None else None
        fs_hz    = float(fs_result)   if fs_result   is not None else 30.0

        # Convert matlab double array → Python list
        try:
            ippg_signal = list(ippg_matlab[0]) if ippg_matlab is not None else []
        except Exception:
            ippg_signal = []

    finally:
        step_done[0] = True

    if progress_callback:
        progress_callback("Finalising results...")

    # Fire partial callback immediately — BP hasn't run yet
    if partial_callback:
        partial_callback({"hr_bpm": hr_bpm, "spo2_pct": spo2_pct})

    print(f"[matlab_runner] Engine result — hr={hr_bpm}, spo2={spo2_pct}, "
          f"signal_len={len(ippg_signal)}, fs={fs_hz}")

    return {
        "hr_bpm":      hr_bpm,
        "spo2_pct":    spo2_pct,
        "ippg_signal": ippg_signal,
        "fs_hz":       fs_hz,
    }


# ── Subprocess -batch fallback ────────────────────────────────────────────────
def _run_via_subprocess(
    video_path: str,
    timeout: int,
    progress_callback: Optional[Callable[[str], None]],
    partial_callback: Optional[Callable[[dict], None]],
) -> dict:

    print(f"[matlab_runner] ── Starting -batch pipeline ──")
    print(f"[matlab_runner] MATLAB_EXE  : {MATLAB_EXE}")
    print(f"[matlab_runner] MATLAB_ROOT : {MATLAB_ROOT}")
    print(f"[matlab_runner] video_path  : {video_path}")

    if not Path(MATLAB_EXE).is_file():
        raise RuntimeError(f"MATLAB executable not found: {MATLAB_EXE}")

    # Signal is printed as a comma-separated row on one line
    matlab_cmd = (
        f"addpath(genpath('{MATLAB_ROOT}')); "
        f"try, "
        f"  [hr, spo2, sig, fs] = run_pipeline_kiosk('{video_path}', 'writeJson', false); "
        f"  fprintf('VITASENSE_HR=%.6f\\n',   hr); "
        f"  fprintf('VITASENSE_SPO2=%.6f\\n', spo2); "
        f"  fprintf('VITASENSE_FS=%.6f\\n',   fs); "
        f"  fprintf('VITASENSE_SIGNAL=%s\\n', num2str(sig, '%.6f,')); "
        f"catch ME, "
        f"  fprintf('VITASENSE_ERROR=%s\\n', ME.message); "
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
    partial_fired = False

    try:
        for line in proc.stdout:
            line = line.rstrip()
            all_output.append(line)
            print(f"[MATLAB] {line}")

            if line.startswith("VITASENSE_PROGRESS="):
                msg = line.split("=", 1)[1].strip()
                if progress_callback:
                    progress_callback(msg)

            # Fire partial callback as soon as we see HR + SPO2 lines
            if not partial_fired and "VITASENSE_HR=" in "\n".join(all_output) \
                    and "VITASENSE_SPO2=" in "\n".join(all_output):
                hr_partial   = _parse_float("\n".join(all_output), "VITASENSE_HR")
                spo2_partial = _parse_float("\n".join(all_output), "VITASENSE_SPO2")
                if hr_partial is not None and spo2_partial is not None:
                    if partial_callback:
                        partial_callback({"hr_bpm": hr_partial, "spo2_pct": spo2_partial})
                    partial_fired = True

        proc.wait(timeout=timeout)

    except subprocess.TimeoutExpired:
        proc.kill()
        raise

    stdout = "\n".join(all_output)

    error = _parse_str(stdout, "VITASENSE_ERROR")
    if error:
        raise RuntimeError(f"MATLAB pipeline error: {error}")

    hr_bpm   = _parse_float(stdout, "VITASENSE_HR")
    spo2_pct = _parse_float(stdout, "VITASENSE_SPO2")
    fs_hz    = _parse_float(stdout, "VITASENSE_FS") or 30.0

    # Parse comma-separated signal
    ippg_signal = []
    sig_line = _parse_str(stdout, "VITASENSE_SIGNAL")
    if sig_line:
        try:
            ippg_signal = [float(x) for x in sig_line.split(",") if x.strip()]
        except Exception:
            ippg_signal = []

    if not partial_fired and partial_callback:
        partial_callback({"hr_bpm": hr_bpm, "spo2_pct": spo2_pct})

    print(f"[matlab_runner] hr_bpm={hr_bpm}, spo2_pct={spo2_pct}, "
          f"signal_len={len(ippg_signal)}, fs={fs_hz}")

    return {
        "hr_bpm":      hr_bpm,
        "spo2_pct":    spo2_pct,
        "ippg_signal": ippg_signal,
        "fs_hz":       fs_hz,
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