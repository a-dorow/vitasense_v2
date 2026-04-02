import pandas as pd
import numpy as np
from scipy import stats
from scipy.stats import shapiro, friedmanchisquare, wilcoxon
from itertools import combinations

df = pd.read_excel(r'C:\Users\avask\OneDrive\Desktop\bpSp02-estimation-ippg\app\stats\MAE_Summary_All_Trials.xlsx', sheet_name="MAE Summary")

trials = sorted(df["Trial"].unique())
methods = df["Extraction Method"].unique()

# ── 1. Shapiro-Wilk per trial ────────────────────────────────────────────────
print("=" * 50)
print("SHAPIRO-WILK NORMALITY TEST (by trial)")
print("=" * 50)

for trial in trials:
    values = df[df["Trial"] == trial]["MAE (bpm)"].values
    stat, p = shapiro(values)
    flag = "=> Normal" if p > 0.05 else "=> NOT normal"
    print(f"Trial {trial}: W={stat:.4f}, p={p:.4f}  {flag}")

# ── 2. Friedman test (rows = methods, columns = trials) ─────────────────────
print("\n" + "=" * 50)
print("FRIEDMAN TEST (comparing trials)")
print("=" * 50)

pivot = df.pivot(index="Extraction Method", columns="Trial", values="MAE (bpm)")
groups = [pivot[t].values for t in pivot.columns]

stat_f, p_f = friedmanchisquare(*groups)
print(f"Friedman χ² = {stat_f:.4f},  p = {p_f:.4f}")
if p_f < 0.05:
    print("→ Significant difference found between trials. Run post-hoc.\n")
else:
    print("→ No significant difference between trials.\n")

# ── 3. One-way ANOVA ─────────────────────────────────────────────────────────
print("=" * 50)
print("ONE-WAY ANOVA (by trial)")
print("=" * 50)

f_stat, p_anova = stats.f_oneway(*groups)
print(f"F = {f_stat:.4f},  p = {p_anova:.4f}")
if p_anova < 0.05:
    print("→ Significant. Run post-hoc Tukey HSD.\n")
else:
    print("→ No significant difference.\n")

# ── 4. Post-hoc: Wilcoxon + Bonferroni ──────────────────────────────────────
print("=" * 50)
print("POST-HOC: WILCOXON SIGNED-RANK + BONFERRONI")
print("=" * 50)

trial_pairs = list(combinations(pivot.columns, 2))
n_comparisons = len(trial_pairs)

rows = []
for t1, t2 in trial_pairs:
    a = pivot[t1].values
    b = pivot[t2].values
    if np.all(a == b):
        stat_w, p_w = np.nan, 1.0
    else:
        stat_w, p_w = wilcoxon(a, b, zero_method="wilcox")
    p_adj = min(p_w * n_comparisons, 1.0)
    sig = "*" if p_adj < 0.05 else "ns"
    rows.append({
        "Trial 1": t1, "Trial 2": t2,
        "W": round(stat_w, 4) if not np.isnan(stat_w) else "—",
        "p (raw)": round(p_w, 4),
        "p (Bonferroni)": round(p_adj, 4),
        "Sig": sig
    })

print(pd.DataFrame(rows).to_string(index=False))

# ── 5. Summary by trial ───────────────────────────────────────────────────────
print("\n" + "=" * 50)
print("MAE SUMMARY BY TRIAL")
print("=" * 50)
summary = df.groupby("Trial")["MAE (bpm)"].agg(
    Mean="mean", Std="std", Min="min", Max="max"
).round(4)
print(summary)