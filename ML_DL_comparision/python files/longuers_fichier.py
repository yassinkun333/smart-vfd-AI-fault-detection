
import re
import os
import scipy.io as sio
import matplotlib.pyplot as plt
import pandas as pd

from cwru_common import GROUPS, find_mat

# ============================================================
# CONFIGURATION
# ============================================================
DATA_DIR = r"C:\Users\admin\Desktop\mastere\matlab data12KHZ"

OUTPUT_PNG = os.path.join(DATA_DIR, "dataset_summary.png")
OUTPUT_CSV = os.path.join(DATA_DIR, "dataset_details.csv")


# ============================================================
# EXTRACTION DES INFORMATIONS
# ============================================================
rows = []
missing = []

for cls, size, ids in GROUPS:

    # Fréquences utilisées dans la configuration actuelle
    fs = 48_000 if cls == "Normal" else 12_000

    for load, fid in enumerate(ids):

        path = find_mat(DATA_DIR, fid)

        if path is None:
            missing.append(fid)
            continue

        try:
            info = {
                name: shape
                for name, shape, _ in sio.whosmat(str(path))
            }

            # Recherche du signal vibratoire Drive End
            key = next(
                k for k in info
                if re.fullmatch(r"X\d+_DE_time", k)
            )

            n_points = max(info[key])

            rows.append({
                "ID": fid,
                "Class": cls,
                "size (in)": size,
                "load": load,
                "N points": n_points,
                "Duration (s)": n_points / fs,
                "fs (kHz)": fs / 1000
            })

        except (StopIteration, ValueError, OSError) as error:
            print(f"Erreur fichier {fid}: {error}")


# ============================================================
# TABLEAU DETAILLE
# ============================================================
columns = [
    "ID", "Class", "size (in)", "load",
    "N points", "Duration (s)", "fs (kHz)"
]

df = pd.DataFrame(rows, columns=columns)

if df.empty:
    raise RuntimeError(
        "Aucun signal trouvé. Vérifiez DATA_DIR et GROUPS."
    )

print("\n========== DETAILS DES SIGNAUX CWRU ==========\n")
print(df.to_string(index=False))

print(f"\nFichiers trouvés : {len(df)}")
print("Fichiers manquants :", missing or "aucun")

# Export CSV de tous les fichiers trouvés
df.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")
print(f"Tableau détaillé enregistré : {OUTPUT_CSV}")


# ============================================================
# RESUME PAR CLASSE
# ============================================================
summary = (
    df.groupby("Class", sort=False)
    .agg(
        **{
            "files count": ("ID", "count"),
            "min size (in)": ("size (in)", "min"),
            "max size (in)": ("size (in)", "max"),
            "fs (kHz)": ("fs (kHz)", "first")
        }
    )
    .reset_index()
)

def format_size(row):
    if row["Class"] == "Normal":
        return "0"

    minimum = row["min size (in)"]
    maximum = row["max size (in)"]

    if minimum == maximum:
        return f"{minimum:.3f}"

    return f"{minimum:.3f}–{maximum:.3f}"


summary["Defect Size (in)"] = summary.apply(
    format_size, axis=1
)

summary = summary[
    [
        "Class",
        "Defect Size (in)",
        "files count",
        "fs (kHz)"
    ]
]

print("\n========== RESUME PAR CLASSE ==========\n")
print(summary.to_string(index=False))


# ============================================================
# GENERATION DE LA FIGURE PNG COMPACTE
# ============================================================
fig, ax = plt.subplots(figsize=(8, 2.5))
ax.axis("off")

ax.set_title(
    "CWRU Bearing Dataset — Summary",
    fontsize=13,
    fontweight="bold",
    pad=12
)

table = ax.table(
    cellText=summary.values,
    colLabels=summary.columns,
    cellLoc="center",
    colLoc="center",
    loc="center",
    colWidths=[0.22, 0.25, 0.30, 0.18]
)

table.auto_set_font_size(False)
table.set_fontsize(9)
table.scale(1, 1.5)

# Mise en forme du tableau
for (row, col), cell in table.get_celld().items():

    cell.set_edgecolor("#C5CDD5")
    cell.set_linewidth(0.6)

    if row == 0:
        cell.set_facecolor("#263D5A")
        cell.set_text_props(
            color="white",
            weight="bold"
        )
    else:
        cell.set_facecolor(
            "#EAF0F6" if row % 2 == 1 else "white"
        )

# Note sous le tableau
fig.text(
    0.5,
    0.025,
    f"Total: {len(df)} files found | "
    f"Missing: {len(missing)}",
    ha="center",
    fontsize=8,
    color="#555555"
)

plt.tight_layout(rect=[0, 0.08, 1, 1])

fig.savefig(
    OUTPUT_PNG,
    dpi=300,
    bbox_inches="tight",
    facecolor="white"
)

plt.close(fig)

print(f"\nFigure PNG enregistrée : {OUTPUT_PNG}")
print("\nTerminé.")
