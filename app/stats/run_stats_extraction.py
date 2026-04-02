import pandas as pd
import numpy as np 
from scipy import stats
from scipy.stats import shapiro, friedmanchisquare, wilcoxon
from itertools import combinations

# Load from excep
df = pd.read_excel(r'C:\Users\avask\OneDrive\Desktop\bpSp02-estimation-ippg\app\stats\MAE_Summary_All_Trials.xlsx', sheet_name="MAE Summary")
methods = df['Extraction Method'].unique()
trials = sorted(df['Trial'].unique())

# Test for normality per method 
print("Shapiro-Wilk Test for Normality:")

normality_results = {}
all_normal = True

for method in methods:
    values = df[df['Extraction Method']== method]['MAE (bpm)'].values
    stat, p = shapiro(values)
    normality_results[method] = (stat, p)
    print(f"{method}: W={stat:.4f}, p={p:.4f}")
    flag = "Normal" if p > 0.05 else "Not Normal"
    print(f"  => {flag}")
    if p <= 0.05:
        all_normal = False
#Friedman Test 

print("\nFriedman Test for Differences Among Methods:")

# Pivot: rows = trials, columns = methods
pivot = df.pivot(index="Trial", columns="Extraction Method", values="MAE (bpm)")
groups = [pivot[m].values for m in pivot.columns]

stat_f, p_f = friedmanchisquare(*groups)
print(f"Friedman χ² = {stat_f:.4f},  p = {p_f:.4f}")
if p_f < 0.05:
    print("→ Significant difference found. Run post-hoc tests.\n")
else:
    print("→ No significant difference between methods.\n")

# ── 2b. One-way ANOVA (parametric, only if all normal) ──────────────────────
print("=" * 50)
print("ONE-WAY ANOVA (parametric)")
print("=" * 50)

f_stat, p_anova = stats.f_oneway(*groups)
print(f"F = {f_stat:.4f},  p = {p_anova:.4f}")
if p_anova < 0.05:
    print("→ Significant. Run post-hoc Tukey HSD.\n")
else:
    print("→ No significant difference.\n")

# ── 3a. Post-hoc: Wilcoxon signed-rank + Bonferroni (for Friedman) ──────────
print("=" * 50)
print("POST-HOC: WILCOXON SIGNED-RANK + BONFERRONI")
print("=" * 50)

method_names = list(pivot.columns)
pairs = list(combinations(method_names, 2))
n_comparisons = len(pairs)

posthoc_rows = []
for m1, m2 in pairs:
    a = pivot[m1].values
    b = pivot[m2].values
    if np.all(a == b):           # identical — wilcoxon will error
        stat_w, p_w = np.nan, 1.0
    else:
        stat_w, p_w = wilcoxon(a, b, zero_method="wilcox")
    p_adj = min(p_w * n_comparisons, 1.0)   # Bonferroni correction
    sig = "*" if p_adj < 0.05 else "ns"
    posthoc_rows.append({
        "Method 1": m1, "Method 2": m2,
        "W": round(stat_w, 4) if not np.isnan(stat_w) else "—",
        "p (raw)": round(p_w, 4),
        "p (Bonferroni)": round(p_adj, 4),
        "Sig": sig
    })

ph_df = pd.DataFrame(posthoc_rows)
print(ph_df.to_string(index=False))

# ── 4. Summary table ─────────────────────────────────────────────────────────
print("\n" + "=" * 50)
print("MAE SUMMARY BY METHOD")
print("=" * 50)
summary = df.groupby("Extraction Method")["MAE (bpm)"].agg(
    Mean="mean", Std="std", Min="min", Max="max"
).round(4)
print(summary)

