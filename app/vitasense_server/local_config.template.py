# local_config.py
# ────────────────────────────────────────────────────────────────
# Copy this file to local_config.py and fill in your machine's
# values. local_config.py is gitignored and never committed.
#
# Usage:
#   cp local_config.template.py local_config.py
#   then edit local_config.py below
# ────────────────────────────────────────────────────────────────

# Full path to your MATLAB executable
MATLAB_EXE = r"C:\Program Files\MATLAB\R2024b\bin\matlab.exe"

# Root of the bpSp02-estimation-ippg repo on this machine
MATLAB_ROOT = r"C:\Users\yourname\path\to\bpSp02-estimation-ippg"

# Port that bp_server_patched.py is running on
BP_SERVER_URL = "http://localhost:8000"

# Full path to the trained Keras/H5 model file
BP_MODEL_PATH = r"C:\Users\yourname\path\to\models\bp_model.keras"

# Full path to ffmpeg executable (for video conversion)
FFMPEG_EXE = r"C:\path\to\ffmpeg.exe"  # run: where.exe ffmpeg