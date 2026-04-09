"""
figures.py
----------
Generates 4 publication-quality figures for the iPPG HR difference analysis.

  Fig 1 — Box plots by resolution
  Fig 2 — Box plots by distance
  Fig 3 — Grouped bar chart (mean HR error, resolution x distance)
  Fig 4 — Power curve (resolution effect)

Saves each figure as a high-res PNG in the same folder as this script.

Dependencies: pandas, numpy, matplotlib, scipy
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.lines import Line2D
import os

# ── Style ─────────────────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family":       "DejaVu Sans",
    "font.size":         11,
    "axes.spines.top":   False,
    "axes.spines.right": False,
    "axes.grid":         True,
    "axes.grid.axis":    "y",
    "grid.color":        "#e5e5e5",
    "grid.linewidth":    0.8,
    "axes.edgecolor":    "#cccccc",
    "axes.linewidth":    0.8,
    "xtick.bottom":      True,
    "ytick.left":        True,
    "xtick.color":       "#555555",
    "ytick.color":       "#555555",
    "figure.dpi":        150,
    "savefig.dpi":       300,
    "savefig.bbox":      "tight",
    "savefig.facecolor": "white",
})

RES_ORDER  = ["240p", "360p", "480p", "1080p"]
TRIAL_MAP  = {1: "Far", 2: "Mid", 3: "Near"}

# ── Load data ─────────────────────────────────────────────────────────────────
records = []
for res in RES_ORDER:
    fname = f"{res}.xlsx"
    if not os.path.isfile(fname):
        raise FileNotFoundError(f"Cannot find {fname} — run this script from the folder containing the xlsx files.")
    xl = pd.read_excel(fname, sheet_name=None)
    for trial_name, df_sheet in xl.items():
        trial_num = int(trial_name.split()[-1])
        diff_cols = [c for c in df_sheet.columns if str(c).strip() == "Difference HR"]
        if not diff_cols:
            continue
        for _, row in df_sheet.iterrows():
            val = row[diff_cols[0]]
            if pd.notna(val):
                records.append({"Resolution": res, "Trial": TRIAL_MAP[trial_num],
                                 "Diff_HR": float(val)})

df = pd.DataFrame(records)
df["Resolution"] = pd.Categorical(df["Resolution"], categories=RES_ORDER, ordered=True)

res_data   = [df.loc[df["Resolution"] == r,   "Diff_HR"].values for r in RES_ORDER]
trial_keys = ["Far", "Mid", "Near"]
trial_data = [df.loc[df["Trial"] == t, "Diff_HR"].values for t in trial_keys]

# ── Color palettes ────────────────────────────────────────────────────────────
res_colors   = ["#B5D4F4", "#85B7EB", "#378ADD", "#185FA5"]
res_medians  = ["#378ADD", "#185FA5", "#0C447C", "#042C53"]
trial_colors = ["#9FE1CB", "#1D9E75", "#085041"]
trial_medians= ["#1D9E75", "#085041", "#04342C"]


def styled_boxplot(ax, data, labels, face_colors, median_colors,
                   xlabel="", ylabel="HR difference (bpm)", title=""):
    bp = ax.boxplot(
        data,
        patch_artist=True,
        notch=False,
        widths=0.45,
        showfliers=True,
        showmeans=True,
        meanprops=dict(marker="D", markerfacecolor="white", markeredgewidth=1.5,
                       markersize=6),
        medianprops=dict(linewidth=2),
        whiskerprops=dict(linewidth=1.2, linestyle="--", color="#888888"),
        capprops=dict(linewidth=1.5, color="#888888"),
        flierprops=dict(marker="o", markersize=4, linestyle="none", alpha=0.6),
    )
    for i, (patch, fc, mc) in enumerate(zip(bp["boxes"], face_colors, median_colors)):
        patch.set_facecolor(fc)
        patch.set_edgecolor(mc)
        patch.set_linewidth(1.5)
        patch.set_alpha(0.85)
        bp["medians"][i].set_color(mc)
        bp["fliers"][i].set_markerfacecolor(mc)
        bp["fliers"][i].set_markeredgecolor(mc)

    ax.set_xticks(range(1, len(labels) + 1))
    ax.set_xticklabels(labels, fontsize=11)
    ax.set_xlabel(xlabel, fontsize=11, color="#555555")
    ax.set_ylabel(ylabel, fontsize=11, color="#555555")
    ax.set_title(title, fontsize=12, fontweight="normal", pad=10, color="#222222")
    ax.set_ylim(bottom=0)
    ax.yaxis.grid(True, color="#e5e5e5", linewidth=0.8, zorder=0)
    ax.set_axisbelow(True)

    n_labels = [f"n = {len(d)}" for d in data]
    for i, (nl, d) in enumerate(zip(n_labels, data)):
        ax.text(i + 1, -ax.get_ylim()[1] * 0.07, nl,
                ha="center", va="top", fontsize=9, color="#888888")


# ════════════════════════════════════════════════════════════════════════════
# Figure 1 — Box plots by resolution
# ════════════════════════════════════════════════════════════════════════════
fig1, ax1 = plt.subplots(figsize=(7, 4.8))
styled_boxplot(ax1, res_data, RES_ORDER, res_colors, res_medians,
               xlabel="Resolution",
               title="Figure 1 — HR error by resolution  (H(3) = 7.75, p = 0.052, ε² = 0.050)")

legend_handles = [
    mpatches.Patch(facecolor=c, edgecolor=e, label=lbl, alpha=0.85)
    for c, e, lbl in zip(res_colors, res_medians, RES_ORDER)
]
legend_handles.append(Line2D([0], [0], marker="D", color="w",
                              markerfacecolor="white", markeredgecolor="#555",
                              markeredgewidth=1.5, markersize=7, label="mean"))
ax1.legend(handles=legend_handles, loc="upper right", fontsize=9,
           framealpha=0.6, edgecolor="#cccccc")
plt.tight_layout()
fig1.savefig("figure1_resolution_boxplot.png")
print("Saved: figure1_resolution_boxplot.png")
plt.close(fig1)


# ════════════════════════════════════════════════════════════════════════════
# Figure 2 — Box plots by distance
# ════════════════════════════════════════════════════════════════════════════
fig2, ax2 = plt.subplots(figsize=(6.5, 4.8))
styled_boxplot(ax2, trial_data, trial_keys, trial_colors, trial_medians,
               xlabel="Camera distance",
               title="Figure 2 — HR error by distance  (H(2) = 8.10, p = 0.017, ε² = 0.064)")

ax2.annotate("*  Mid vs Near\np = 0.013",
             xy=(2.5, max(trial_data[1]) * 0.9),
             fontsize=9, color="#0F6E56", ha="center",
             bbox=dict(boxstyle="round,pad=0.3", fc="#E1F5EE", ec="#1D9E75", lw=0.8))

legend_handles2 = [
    mpatches.Patch(facecolor=c, edgecolor=e, label=lbl, alpha=0.85)
    for c, e, lbl in zip(trial_colors, trial_medians, trial_keys)
]
legend_handles2.append(Line2D([0], [0], marker="D", color="w",
                               markerfacecolor="white", markeredgecolor="#555",
                               markeredgewidth=1.5, markersize=7, label="mean"))
ax2.legend(handles=legend_handles2, loc="upper right", fontsize=9,
           framealpha=0.6, edgecolor="#cccccc")
plt.tight_layout()
fig2.savefig("figure2_distance_boxplot.png")
print("Saved: figure2_distance_boxplot.png")
plt.close(fig2)


# ════════════════════════════════════════════════════════════════════════════
# Figure 3 — Grouped bar chart (mean HR error, resolution x distance)
# ════════════════════════════════════════════════════════════════════════════
heatmap = {
    "240p":  {"Far": 7.86,  "Mid": 10.70, "Near": 6.84},
    "360p":  {"Far": 12.37, "Mid": 12.56, "Near": 3.44},
    "480p":  {"Far": 8.31,  "Mid": 4.99,  "Near": 3.61},
    "1080p": {"Far": 4.40,  "Mid": 4.31,  "Near": 4.20},
}

x     = np.arange(len(RES_ORDER))
width = 0.25
offsets = [-width, 0, width]

fig3, ax3 = plt.subplots(figsize=(8, 4.8))

for i, (dist, off, fc, ec) in enumerate(zip(trial_keys, offsets,
                                             trial_colors, trial_medians)):
    vals = [heatmap[r][dist] for r in RES_ORDER]
    bars = ax3.bar(x + off, vals, width=width * 0.92,
                   color=fc, edgecolor=ec, linewidth=1.0,
                   alpha=0.88, label=dist, zorder=3)
    for bar, v in zip(bars, vals):
        ax3.text(bar.get_x() + bar.get_width() / 2,
                 bar.get_height() + 0.25,
                 f"{v:.1f}", ha="center", va="bottom",
                 fontsize=8, color="#444444")

ax3.set_xticks(x)
ax3.set_xticklabels(RES_ORDER, fontsize=11)
ax3.set_xlabel("Resolution", fontsize=11, color="#555555")
ax3.set_ylabel("Mean HR difference (bpm)", fontsize=11, color="#555555")
ax3.set_title("Figure 3 — Mean error by resolution × distance", fontsize=12,
              fontweight="normal", pad=10, color="#222222")
ax3.set_ylim(0, 16)
ax3.yaxis.grid(True, color="#e5e5e5", linewidth=0.8, zorder=0)
ax3.set_axisbelow(True)
ax3.legend(title="Distance", fontsize=9, title_fontsize=9,
           framealpha=0.6, edgecolor="#cccccc")
plt.tight_layout()
fig3.savefig("figure3_heatmap_bars.png")
print("Saved: figure3_heatmap_bars.png")
plt.close(fig3)


# ════════════════════════════════════════════════════════════════════════════
# Figure 4 — Power curve
# ════════════════════════════════════════════════════════════════════════════
power_curve = [
    (5,  0.120), (10, 0.263), (15, 0.405), (20, 0.558),
    (25, 0.661), (30, 0.761), (35, 0.816), (40, 0.875),
    (45, 0.911), (50, 0.945), (55, 0.964), (60, 0.982),
    (65, 0.986), (70, 0.993), (75, 0.991), (80, 0.996),
]
ns, pws = zip(*power_curve)

fig4, ax4 = plt.subplots(figsize=(7, 4.8))

ax4.fill_between(ns, pws, alpha=0.12, color="#378ADD", zorder=2)
ax4.plot(ns, pws, color="#185FA5", linewidth=2.2, zorder=3, label="power")

ax4.axhline(0.80, color="#888888", linestyle="--", linewidth=1.4,
            zorder=2, label="80% target")

current_n, current_pwr = 25, 0.661
target_n,  target_pwr  = 35, 0.816

ax4.scatter([current_n], [current_pwr], color="#378ADD", s=80, zorder=5)
ax4.annotate(f"Current\nn = {current_n}/group\npower = {current_pwr:.0%}",
             xy=(current_n, current_pwr),
             xytext=(current_n + 7, current_pwr - 0.12),
             fontsize=9, color="#185FA5",
             arrowprops=dict(arrowstyle="->", color="#185FA5", lw=1.0),
             bbox=dict(boxstyle="round,pad=0.3", fc="#E6F1FB", ec="#378ADD", lw=0.8))

ax4.scatter([target_n], [target_pwr], color="#0C447C", s=80, zorder=5)
ax4.annotate(f"80% power\nn = {target_n}/group\n({target_n * 4} total)",
             xy=(target_n, target_pwr),
             xytext=(target_n + 7, target_pwr + 0.07),
             fontsize=9, color="#0C447C",
             arrowprops=dict(arrowstyle="->", color="#0C447C", lw=1.0),
             bbox=dict(boxstyle="round,pad=0.3", fc="#E6F1FB", ec="#0C447C", lw=0.8))

ax4.set_xlabel("n per resolution group", fontsize=11, color="#555555")
ax4.set_ylabel("Statistical power", fontsize=11, color="#555555")
ax4.set_title("Figure 4 — Power curve for resolution effect\n(Monte Carlo resampling, 3000 simulations)",
              fontsize=12, fontweight="normal", pad=10, color="#222222")
ax4.set_xlim(0, 85)
ax4.set_ylim(0, 1.05)
ax4.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:.0%}"))
ax4.yaxis.grid(True, color="#e5e5e5", linewidth=0.8, zorder=0)
ax4.set_axisbelow(True)
ax4.legend(fontsize=9, framealpha=0.6, edgecolor="#cccccc")
plt.tight_layout()
fig4.savefig("figure4_power_curve.png")
print("Saved: figure4_power_curve.png")
plt.close(fig4)

print("\nAll 4 figures saved.")