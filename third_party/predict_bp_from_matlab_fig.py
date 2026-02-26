#!/usr/bin/env python3
r"""
predict_bp_from_matlab_fig.py

Loads a MATLAB .fig containing an iPPG line plot, windows it into 7s segments,
resamples 30 Hz -> 125 Hz (875 samples), loads Fabian-Sc85 Slapnicar .h5 model,
and outputs SBP/DBP predictions to CSV.

Adds sanity checks:
- Prints mean/std of SBP/DBP across windows
- "Model prior" test: shuffle time within each window and compare predictions

Usage (PowerShell, one line):
  python predict_bp_from_matlab_fig.py --fig "C:\Users\avask\OneDrive\Desktop\bpSp02-estimation-ippg\third_party\matlab_data\subject1_AGRD_iPPG.fig" --model "C:\Users\avask\OneDrive\Desktop\bpSp02-estimation-ippg\models\alexnet_ppg_nonmixed.h5" --out "subject1_preds.csv" --stride_s 1.0

MAT support:
  python predict_bp_from_matlab_fig.py --mat "C:\path\to\signal.mat" --model "C:\path\to\model.h5" --out "preds.csv"

MAT file schema (deterministic):
  Must contain y (iPPG signal), and either:
    - t (seconds, same length as y), OR
    - fs_in (Hz, scalar)
"""

import argparse
import numpy as np
from scipy.io import loadmat
from scipy.signal import resample_poly, detrend

import tensorflow.keras as ks
from kapre import STFT, Magnitude, MagnitudeToDecibel


def _is_mat_struct(x) -> bool:
    return type(x).__name__ == "mat_struct"


def extract_lineseries_from_fig(fig_path: str):
    """
    Extract the first MATLAB line object (graph2d.lineseries) from a .fig file.
    Returns (t, y) as 1D numpy arrays.
    """
    mat = loadmat(fig_path, squeeze_me=True, struct_as_record=False)

    root = None
    for k in mat.keys():
        if k.startswith("hgS_"):
            root = mat[k]
            break
    if root is None:
        raise RuntimeError("Could not find hgS_* root in .fig file.")

    queue = [root]
    lines = []

    while queue:
        node = queue.pop(0)

        if _is_mat_struct(node) and hasattr(node, "type"):
            if getattr(node, "type", "") == "graph2d.lineseries":
                lines.append(node)

            ch = getattr(node, "children", None)
            if ch is None:
                continue

            if isinstance(ch, np.ndarray):
                for item in ch.ravel():
                    if _is_mat_struct(item):
                        queue.append(item)
            elif _is_mat_struct(ch):
                queue.append(ch)

    if not lines:
        raise RuntimeError("No graph2d.lineseries found in this .fig.")

    line = lines[0]
    props = line.properties

    t = np.asarray(props.XData, dtype=np.float64)
    y = np.asarray(props.YData, dtype=np.float64)

    if t.ndim != 1 or y.ndim != 1 or len(t) != len(y):
        raise RuntimeError("Unexpected XData/YData shape in .fig lineseries.")

    return t, y


def extract_timeseries_from_mat(mat_path: str):
    """
    Load iPPG time series from a .mat file.

    Required:
      - y : iPPG signal (1D or Nx1)

    Plus either:
      - t : time vector in seconds (same length as y), OR
      - fs_in : sampling frequency in Hz (scalar)

    Returns:
      y (np.ndarray float64 shape (N,))
      fs_in (float)
      t (np.ndarray float64 shape (N,)) or None
    """
    m = loadmat(mat_path, squeeze_me=True, struct_as_record=False)

    if "y" not in m:
        raise RuntimeError("MAT file must contain variable 'y' (iPPG signal).")

    y = np.asarray(m["y"], dtype=np.float64).reshape(-1)

    t = None
    if "t" in m and m["t"] is not None:
        t = np.asarray(m["t"], dtype=np.float64).reshape(-1)
        if t.shape[0] != y.shape[0]:
            raise RuntimeError("In MAT file, 't' and 'y' must have the same length.")
        dt = np.median(np.diff(t))
        if not np.isfinite(dt) or dt <= 0:
            raise RuntimeError("Invalid time axis in MAT: non-positive or non-finite dt.")
        fs_in = 1.0 / dt
        return y, float(fs_in), t

    if "fs_in" not in m:
        raise RuntimeError("MAT file must contain either ('t' and 'y') or ('y' and 'fs_in').")

    fs_in = float(np.asarray(m["fs_in"]).reshape(()))
    if not np.isfinite(fs_in) or fs_in <= 0:
        raise RuntimeError("Invalid 'fs_in' in MAT: must be positive finite scalar.")

    return y, fs_in, None


def window_and_resample(
    y: np.ndarray,
    fs_in: float,
    win_s: float = 7.0,
    stride_s: float = 1.0,
    fs_out: float = 125.0,
):
    """
    Window the signal and resample each window to match model expectations.

    For fs_in == 30 and fs_out == 125:
      - 7s window = 210 samples
      - resample_poly with up=25, down=6 (exact 125/30) -> 875 samples

    Returns:
      X: (num_windows, 875) float32
      centers_s: (num_windows,) float64
    """
    n_in = int(round(win_s * fs_in))
    hop = int(round(stride_s * fs_in))
    if n_in <= 0 or hop <= 0:
        raise ValueError("win_s and stride_s must be positive.")

    # Exact rational for 30 -> 125
    if abs(fs_in - 30.0) < 1e-3 and abs(fs_out - 125.0) < 1e-6:
        up, down = 25, 6
        n_out_expected = 875
    else:
        # Fallback (still deterministic): may need trim/pad
        up = int(round(fs_out * 1000))
        down = int(round(fs_in * 1000))
        n_out_expected = int(round(win_s * fs_out))

    X = []
    centers_s = []

    for start in range(0, len(y) - n_in + 1, hop):
        seg = y[start: start + n_in].astype(np.float64)

        # Minimal deterministic preprocessing
        seg = detrend(seg, type="constant")  # remove DC
        s = np.std(seg)
        if s > 1e-12:
            seg = seg / s

        seg_out = resample_poly(seg, up=up, down=down)

        # Enforce exact expected length
        if len(seg_out) > n_out_expected:
            seg_out = seg_out[:n_out_expected]
        elif len(seg_out) < n_out_expected:
            seg_out = np.pad(seg_out, (0, n_out_expected - len(seg_out)))

        X.append(seg_out.astype(np.float32))
        centers_s.append((start + n_in / 2) / fs_in)

    if not X:
        raise RuntimeError("Signal too short to form even one 7s window.")

    return np.stack(X, axis=0), np.asarray(centers_s, dtype=np.float64)


def load_bp_model(model_path: str):
    deps = {
        "ReLU": ks.layers.ReLU,
        "STFT": STFT,
        "Magnitude": Magnitude,
        "MagnitudeToDecibel": MagnitudeToDecibel,
    }
    return ks.models.load_model(model_path, custom_objects=deps)


def predict_sbp_dbp(model, X_in: np.ndarray):
    """
    Runs prediction and returns (sbp, dbp) as 1D arrays of length N windows.
    Supports multi-output ([SBP, DBP]) and Nx2 outputs.
    """
    preds = model.predict(X_in, verbose=0)

    # Multi-output model: returns [SBP_pred, DBP_pred]
    if isinstance(preds, (list, tuple)) and len(preds) == 2:
        sbp = np.asarray(preds[0]).reshape(-1)
        dbp = np.asarray(preds[1]).reshape(-1)
        return sbp, dbp

    # Some formats could return Nx2
    if isinstance(preds, np.ndarray) and preds.ndim == 2 and preds.shape[1] == 2:
        return preds[:, 0], preds[:, 1]

    raise RuntimeError(
        f"Unexpected prediction output type/shape: {type(preds)} {getattr(preds,'shape',None)}"
    )


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--fig", help="Path to MATLAB .fig containing iPPG line")
    g.add_argument("--mat", help="Path to MATLAB .mat containing iPPG timeseries (y + (t or fs_in))")
    ap.add_argument("--model", required=True, help="Path to trained .h5 model (alexnet_ppg_nonmixed.h5)")
    ap.add_argument("--out", default="preds.csv", help="Output CSV path")
    ap.add_argument("--win_s", type=float, default=7.0, help="Window length in seconds (default 7)")
    ap.add_argument("--stride_s", type=float, default=1.0, help="Stride in seconds (default 1)")
    ap.add_argument(
        "--shuffle_test",
        action="store_true",
        help="Run time-shuffle sanity test to detect model-prior behavior",
    )
    ap.add_argument("--shuffle_seed", type=int, default=0, help="RNG seed for shuffle test (default 0)")
    args = ap.parse_args()

    if args.fig is not None:
        t, y = extract_lineseries_from_fig(args.fig)

        dt = np.median(np.diff(t))
        if dt <= 0:
            raise RuntimeError("Invalid time axis: non-positive dt inferred from XData.")
        fs_in = 1.0 / dt

        print(f"Loaded fig: {args.fig}")
        print(f"Signal length: {len(y)} samples (~{len(y)/fs_in:.2f} s)")
        print(f"Inferred fs_in: {fs_in:.6f} Hz")

    else:
        y, fs_in, t = extract_timeseries_from_mat(args.mat)

        print(f"Loaded mat: {args.mat}")
        print(f"Signal length: {len(y)} samples (~{len(y)/fs_in:.2f} s)")
        if t is not None:
            print("fs_in inferred from 't'.")
        else:
            print("fs_in loaded from 'fs_in'.")
        print(f"fs_in: {fs_in:.6f} Hz")

    X, centers_s = window_and_resample(
        y=y,
        fs_in=fs_in,
        win_s=args.win_s,
        stride_s=args.stride_s,
        fs_out=125.0,
    )

    # Model expects (N, 875, 1)
    X_in = X[:, :, None]
    print(f"Windows: {X_in.shape[0]} | Model input shape: {X_in.shape}")

    model = load_bp_model(args.model)

    sbp, dbp = predict_sbp_dbp(model, X_in)

    # Save CSV
    data = np.column_stack([centers_s, sbp, dbp])
    np.savetxt(
        args.out,
        data,
        delimiter=",",
        header="center_time_s,sbp_pred,dbp_pred",
        comments="",
    )

    print(f"Saved predictions -> {args.out}")
    print("First 3 predictions (center_time_s, SBP, DBP):")
    for i in range(min(3, len(centers_s))):
        print(f"{centers_s[i]:.2f}, {sbp[i]:.2f}, {dbp[i]:.2f}")

    # Summary stats
    print("\nSummary over all windows:")
    print(f"SBP mean ± std: {np.mean(sbp):.2f} ± {np.std(sbp):.2f}")
    print(f"DBP mean ± std: {np.mean(dbp):.2f} ± {np.std(dbp):.2f}")

    # Model-prior sanity test (time-shuffle within each window)
    if args.shuffle_test:
        rng = np.random.default_rng(args.shuffle_seed)
        X_shuf = X_in.copy()
        for i in range(X_shuf.shape[0]):
            rng.shuffle(X_shuf[i, :, 0])

        sbp_shuf, dbp_shuf = predict_sbp_dbp(model, X_shuf)

        mad_sbp = float(np.mean(np.abs(sbp_shuf - sbp)))
        mad_dbp = float(np.mean(np.abs(dbp_shuf - dbp)))

        print("\nTime-shuffle sanity test (destroys physiology, keeps value distribution):")
        print(f"Mean |ΔSBP| vs original: {mad_sbp:.2f} mmHg")
        print(f"Mean |ΔDBP| vs original: {mad_dbp:.2f} mmHg")
        print("Interpretation:")
        print("- If these deltas are very small (~<2–3 mmHg), the model may be defaulting to a prior (not using temporal structure).")
        print("- If these deltas are meaningfully larger, the model is sensitive to time structure (a necessary, not sufficient, condition).")


if __name__ == "__main__":
    main()