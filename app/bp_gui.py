from pathlib import Path

import json
import os
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from typing import List, Optional

import requests


DEFAULT_SERVER_URL = "http://127.0.0.1:8000"
DEFAULT_WIN_S = 7.0
DEFAULT_STRIDE_S = 1.0
MODEL_EXTENSIONS = {".h5", ".keras"}
INPUT_EXTENSIONS = {".mat", ".fig"}

PATH_FOR_MODELS = 'C:\\Users\\avask\\OneDrive\\Desktop\\bpSp02-estimation-ippg\\models'


class BPResearchGUI:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("VitaSense BP Research GUI")
        self.root.geometry("860x700")

        self.server_url_var = tk.StringVar(value=DEFAULT_SERVER_URL)
        self.models_dir_var = tk.StringVar(value=PATH_FOR_MODELS)
        self.model_var = tk.StringVar()
        self.input_path_var = tk.StringVar()
        self.input_type_var = tk.StringVar(value="auto")
        self.win_s_var = tk.StringVar(value=str(DEFAULT_WIN_S))
        self.stride_s_var = tk.StringVar(value=str(DEFAULT_STRIDE_S))
        self.status_var = tk.StringVar(value="Ready.")

        self.model_paths: List[Path] = []
        self.last_response: Optional[dict] = None

        self._build_ui()
        self.refresh_models()

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=12)
        outer.pack(fill="both", expand=True)

        title = ttk.Label(
            outer,
            text="VitaSense Blood Pressure Research GUI",
            font=("Segoe UI", 14, "bold"),
        )
        title.pack(anchor="w", pady=(0, 12))

        # Server frame
        server_frame = ttk.LabelFrame(outer, text="Server", padding=10)
        server_frame.pack(fill="x", pady=(0, 10))

        ttk.Label(server_frame, text="Server URL").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(server_frame, textvariable=self.server_url_var, width=55).grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Button(server_frame, text="Check Health", command=self.check_health).grid(row=0, column=2, padx=(8, 0), pady=4)

        server_frame.columnconfigure(1, weight=1)

        # Model frame
        model_frame = ttk.LabelFrame(outer, text="Model Selection", padding=10)
        model_frame.pack(fill="x", pady=(0, 10))

        ttk.Label(model_frame, text="Models folder").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(model_frame, textvariable=self.models_dir_var, width=55).grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Button(model_frame, text="Browse", command=self.browse_models_dir).grid(row=0, column=2, padx=(8, 0), pady=4)
        ttk.Button(model_frame, text="Refresh", command=self.refresh_models).grid(row=0, column=3, padx=(8, 0), pady=4)

        ttk.Label(model_frame, text="Model").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=4)
        self.model_combo = ttk.Combobox(model_frame, textvariable=self.model_var, state="readonly", width=65)
        self.model_combo.grid(row=1, column=1, columnspan=3, sticky="ew", pady=4)

        model_frame.columnconfigure(1, weight=1)

        # Input frame
        input_frame = ttk.LabelFrame(outer, text="Input Signal", padding=10)
        input_frame.pack(fill="x", pady=(0, 10))

        ttk.Label(input_frame, text="Input file").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(input_frame, textvariable=self.input_path_var, width=55).grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Button(input_frame, text="Browse", command=self.browse_input_file).grid(row=0, column=2, padx=(8, 0), pady=4)

        ttk.Label(input_frame, text="Input type").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=4)
        input_type_combo = ttk.Combobox(
            input_frame,
            textvariable=self.input_type_var,
            state="readonly",
            values=["auto", "mat", "fig"],
            width=12,
        )
        input_type_combo.grid(row=1, column=1, sticky="w", pady=4)

        input_frame.columnconfigure(1, weight=1)

        # Parameters frame
        params_frame = ttk.LabelFrame(outer, text="Prediction Parameters", padding=10)
        params_frame.pack(fill="x", pady=(0, 10))

        ttk.Label(params_frame, text="Window length (s)").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(params_frame, textvariable=self.win_s_var, width=12).grid(row=0, column=1, sticky="w", pady=4)

        ttk.Label(params_frame, text="Stride (s)").grid(row=0, column=2, sticky="w", padx=(18, 8), pady=4)
        ttk.Entry(params_frame, textvariable=self.stride_s_var, width=12).grid(row=0, column=3, sticky="w", pady=4)

        ttk.Button(params_frame, text="Run Prediction", command=self.run_prediction).grid(row=0, column=4, padx=(18, 0), pady=4)
        ttk.Button(params_frame, text="Save JSON", command=self.save_json).grid(row=0, column=5, padx=(8, 0), pady=4)

        # Results frame
        results_frame = ttk.LabelFrame(outer, text="Results", padding=10)
        results_frame.pack(fill="both", expand=True, pady=(0, 10))

        self.results_text = tk.Text(results_frame, wrap="word", height=20)
        self.results_text.pack(fill="both", expand=True)

        # Status
        status_bar = ttk.Label(outer, textvariable=self.status_var, anchor="w")
        status_bar.pack(fill="x")

    def browse_models_dir(self) -> None:
        folder = filedialog.askdirectory(title="Select models folder")
        if folder:
            self.models_dir_var.set(folder)
            self.refresh_models()

    def browse_input_file(self) -> None:
        path = filedialog.askopenfilename(
            title="Select .mat or .fig file",
            filetypes=[
                ("Supported files", "*.mat *.fig"),
                ("MAT files", "*.mat"),
                ("FIG files", "*.fig"),
                ("All files", "*.*"),
            ],
        )
        if path:
            self.input_path_var.set(path)

    def refresh_models(self) -> None:
        models_dir = Path(self.models_dir_var.get().strip())
        self.model_paths = []

        if models_dir.is_dir():
            self.model_paths = sorted(
                [p for p in models_dir.rglob("*") if p.is_file() and p.suffix.lower() in MODEL_EXTENSIONS],
                key=lambda p: p.name.lower(),
            )

        model_names = [p.name for p in self.model_paths]
        self.model_combo["values"] = model_names

        if model_names:
            if self.model_var.get() not in model_names:
                self.model_var.set(model_names[0])
            self.status_var.set(f"Loaded {len(model_names)} model(s).")
        else:
            self.model_var.set("")
            self.status_var.set("No models found. Point the GUI to your models folder.")

    def check_health(self) -> None:
        try:
            url = self.server_url_var.get().rstrip("/") + "/health"
            resp = requests.get(url, timeout=5)
            resp.raise_for_status()
            data = resp.json()
            if data.get("ok") is True:
                self.status_var.set("Server is healthy.")
                messagebox.showinfo("Health Check", "Server responded successfully.")
            else:
                self.status_var.set("Server responded, but payload was unexpected.")
                messagebox.showwarning("Health Check", f"Unexpected response: {data}")
        except Exception as exc:
            self.status_var.set("Health check failed.")
            messagebox.showerror("Health Check Failed", str(exc))

    def _get_selected_model_path(self) -> Path:
        selected_name = self.model_var.get().strip()
        for path in self.model_paths:
            if path.name == selected_name:
                return path
        raise ValueError("No model selected.")

    def _resolve_input_type(self, input_path: Path) -> str:
        chosen = self.input_type_var.get().strip().lower()
        if chosen in {"mat", "fig"}:
            return chosen

        ext = input_path.suffix.lower()
        if ext == ".mat":
            return "mat"
        if ext == ".fig":
            return "fig"

        raise ValueError("Input type could not be determined. Choose it manually.")

    def _validate_numeric(self, value: str, name: str) -> float:
        try:
            out = float(value)
        except ValueError as exc:
            raise ValueError(f"{name} must be numeric.") from exc

        if out <= 0:
            raise ValueError(f"{name} must be > 0.")
        return out

    def run_prediction(self) -> None:
        try:
            input_path = Path(self.input_path_var.get().strip())
            if not input_path.is_file():
                raise ValueError("Choose a valid input file.")

            if input_path.suffix.lower() not in INPUT_EXTENSIONS:
                raise ValueError("Input file must be .mat or .fig.")

            model_path = self._get_selected_model_path()
            input_type = self._resolve_input_type(input_path)
            win_s = self._validate_numeric(self.win_s_var.get(), "Window length")
            stride_s = self._validate_numeric(self.stride_s_var.get(), "Stride")

            payload = {
                "input_path": str(input_path),
                "input_type": input_type,
                "model_path": str(model_path),
                "win_s": win_s,
                "stride_s": stride_s,
                "shuffle_test": False,
                "shuffle_seed": 0,
            }

            self.status_var.set("Running prediction...")
            self.root.update_idletasks()

            url = self.server_url_var.get().rstrip("/") + "/predict"
            resp = requests.post(url, json=payload, timeout=300)

            if resp.status_code >= 400:
                try:
                    detail = resp.json()
                except Exception:
                    detail = resp.text
                raise RuntimeError(f"Server error ({resp.status_code}): {detail}")

            data = resp.json()
            self.last_response = data
            self._display_results(
                input_path=str(input_path),
                input_type=input_type,
                model_path=str(model_path),
                win_s=win_s,
                stride_s=stride_s,
                data=data,
            )
            self.status_var.set("Prediction complete.")

        except Exception as exc:
            self.status_var.set("Prediction failed.")
            messagebox.showerror("Prediction Failed", str(exc))

    def _display_results(
        self,
        input_path: str,
        input_type: str,
        model_path: str,
        win_s: float,
        stride_s: float,
        data: dict,
    ) -> None:
        lines = [
            "VitaSense BP Prediction Results",
            "=" * 34,
            "",
            f"Input file:   {input_path}",
            f"Input type:   {input_type}",
            f"Model path:   {model_path}",
            f"Window (s):   {win_s}",
            f"Stride (s):   {stride_s}",
            "",
            f"Sampling rate in:  {data.get('fs_in')}",
            f"Duration (s):      {data.get('duration_s')}",
            f"Num samples:       {data.get('num_samples')}",
            f"Num windows:       {data.get('num_windows')}",
            "",
            f"SBP mean: {data.get('sbp_mean'):.2f} mmHg",
            f"SBP std:  {data.get('sbp_std'):.2f} mmHg",
            f"DBP mean: {data.get('dbp_mean'):.2f} mmHg",
            f"DBP std:  {data.get('dbp_std'):.2f} mmHg",
            "",
        ]

        centers = data.get("centers_s", [])
        sbp = data.get("sbp", [])
        dbp = data.get("dbp", [])

        if centers and sbp and dbp:
            lines.append("Per-window predictions")
            lines.append("-" * 24)
            for idx, (c, s, d) in enumerate(zip(centers, sbp, dbp), start=1):
                lines.append(f"Window {idx:02d} | center={c:.2f} s | SBP={s:.2f} | DBP={d:.2f}")

        text = "\n".join(lines)
        self.results_text.delete("1.0", tk.END)
        self.results_text.insert(tk.END, text)

    def save_json(self) -> None:
        if not self.last_response:
            messagebox.showwarning("No Results", "Run a prediction first.")
            return

        path = filedialog.asksaveasfilename(
            title="Save prediction JSON",
            defaultextension=".json",
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")],
        )
        if not path:
            return

        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.last_response, f, indent=2)

        self.status_var.set(f"Saved JSON to: {path}")


def main() -> None:
    root = tk.Tk()
    app = BPResearchGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()

