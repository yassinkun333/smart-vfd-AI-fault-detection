"""Kurtogramme par banc de filtres (arbre 1/3-binaire, type Antoni) - données 12 kHz.
Usage: python kurtogram.py --data_dir /chemin/vers/mat --out_dir work/kurtogram [--ids 105 130 209]
Sorties : <out_dir>/<file_id>.png + kurtogram_summary.csv
Le Normal (disponible uniquement à 48 kHz) est rééchantillonné à 12 kHz comme en phase 1.
"""
import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.signal import resample_poly

from cwru_common import GROUPS, FS, find_mat, load_de

# nombre de bandes par niveau : 1, 2, 3, 4, 6, 8, ... 128 (niveaux 0, 1, 1.6, 2, 2.6, ... 7)
NB = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128]
FMAX = FS / 2


def kurtogram_fb(x, fs=FS, nbs=NB):
    """Pour chaque niveau, kurtosis du signal analytique filtré dans chacune des nb bandes
    contiguës [b*Bw, (b+1)*Bw], Bw = fs/2/nb. Retourne une liste de tableaux (un par niveau).
    K = <|z|^4> / <|z|^2>^2 - 2  (0 pour un bruit gaussien)."""
    x = np.asarray(x, dtype=np.float64)
    x = x - x.mean()
    n = len(x)
    Z = np.fft.rfft(x)
    Z[0] = 0                      # pas de continu
    if n % 2 == 0:
        Z[-1] = 0                 # bin de Nyquist (réel) retiré
    df = fs / n
    half = n // 2
    rows = []
    for nb in nbs:
        edges = np.round(np.linspace(0, fs / 2, nb + 1) / df).astype(int)
        edges[-1] = min(edges[-1], half)
        K = np.full(nb, np.nan)
        for b in range(nb):
            S = Z[edges[b]:edges[b + 1]]
            if len(S) < 32:
                continue
            a2 = np.abs(np.fft.ifft(S)) ** 2      # enveloppe au carré, décimée à la largeur de bande
            m2 = a2.mean()
            if m2 > 0:
                K[b] = (a2 ** 2).mean() / m2 ** 2 - 2.0
        rows.append(K)
    return rows


def best_band(rows, fs=FS, nbs=NB):
    r, b = max(((r, int(np.nanargmax(K))) for r, K in enumerate(rows) if not np.all(np.isnan(K))),
               key=lambda t: rows[t[0]][t[1]])
    bw = fs / 2 / nbs[r]
    return rows[r][b], r, b, bw, b * bw, (b + 1) * bw


def to_image(rows, nbs=NB, ngrid=1200):
    """Matrice (niveaux x fréquence) pour l'affichage : lignes du haut = bandes étroites."""
    fgrid = (np.arange(ngrid) + 0.5) * FMAX / ngrid
    M = np.zeros((len(rows), ngrid))
    for r, (K, nb) in enumerate(zip(rows, nbs)):
        idx = np.minimum((fgrid // (FMAX / nb)).astype(int), nb - 1)
        M[r] = K[idx]
    return M[::-1]


def main(data_dir, out_dir, ids):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rows_csv = []
    for cls, size, fids in GROUPS:
        for load, fid in enumerate(fids):
            if ids and fid not in ids:
                continue
            p = find_mat(data_dir, fid)
            if p is None:
                print(f"!! {fid} introuvable")
                continue
            x, _ = load_de(p)
            if cls == "Normal":
                x = resample_poly(x, 1, 4)
            rows = kurtogram_fb(x)
            kmax, r, b, bw, flo, fhi = best_band(rows)
            fc = (flo + fhi) / 2
            rows_csv.append(dict(file_id=fid, classe=cls, taille_in=size, charge_hp=load,
                                 K_max=round(float(kmax), 2), fc_hz=round(fc, 1), bw_hz=round(bw, 1),
                                 f_lo_hz=round(flo, 1), f_hi_hz=round(fhi, 1), nb_bandes=NB[r]))

            M = to_image(rows)
            fig, ax = plt.subplots(figsize=(8.5, 4.8))
            im = ax.imshow(M, aspect="auto", origin="upper", cmap="jet", interpolation="nearest",
                           extent=[0, FMAX, len(NB), 0])
            ax.set_yticks(np.arange(len(NB)) + 0.5)
            ax.set_yticklabels([f"{FMAX / nb:.0f} Hz" for nb in NB[::-1]], fontsize=7)
            ax.set_xlabel("Fréquence centrale (Hz)")
            ax.set_ylabel("Largeur de bande (Δf)")
            ax.plot(fc, len(NB) - r - 0.5, "w*", ms=12, mec="k")
            fig.colorbar(im, label="Kurtosis spectral")
            ax.set_title(f"Kurtogramme - fichier {fid} - {cls} {size:.3f}\" - {load} hp "
                         f"(max {kmax:.1f} @ {fc:.0f} Hz, Δf={bw:.0f} Hz)")
            fig.tight_layout()
            fig.savefig(out / f"{fid}.png", dpi=110)
            plt.close(fig)
            print(f"{fid:>4} {cls:<6} K={kmax:.1f}  fc={fc:.0f} Hz  Δf={bw:.0f} Hz  "
                  f"bande {flo:.0f}-{fhi:.0f} Hz")

    pd.DataFrame(rows_csv).to_csv(out / "kurtogram_summary.csv", index=False)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data_dir", required=True)
    ap.add_argument("--out_dir", default="work/kurtogram")
    ap.add_argument("--ids", type=int, nargs="*", default=None)
    a = ap.parse_args()
    main(a.data_dir, a.out_dir, a.ids)