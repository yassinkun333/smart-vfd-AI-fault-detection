"""Phase 2 : spectre d'enveloppe au carré (M1 brut, M2 prewhitening) + gate.

Usage:
    python phase2_ses_gate.py --work_dir work
Sorties:
    work/phase2/<file_id>.png   (SES M1 et M2 avec curseurs)
    work/phase2/gate.csv        (mesures en dB au-dessus du plancher)
    verdict PASS/FAIL dans la console
"""
import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.fft import next_fast_len
from scipy.signal import hilbert

from cwru_common import FS

# ---- seuils (choix arbitraires, à ajuster en regardant les figures) ----
THR_DB = 15.0   # pic "détecté" si >= 15 dB au-dessus de la médiane du spectre
SB_DB = 10.0    # bande latérale "présente"
THR_ABSENT = 25.0  # "pas de diagnostic clair" : les fichiers Y1 sont à 39-58 dB
TOL = 0.02      # +/-2 % autour de la fréquence théorique (glissement 1-2 %)
FMIN, FMAX = 20.0, 500.0

GATE_IR = [209, 210, 211, 212]   # attendu : BPFI + sidebands a +/-fr
GATE_OR = [130, 131, 132, 133]   # attendu : BPFO, peu de sidebands
GATE_BALL_N = [118, 119, 120]    # attendu : pas de signature de bille claire


def ses(x, fs=FS):
    """Spectre d'amplitude de l'enveloppe au carré."""
    x = x - x.mean()
    n = len(x)
    env = np.abs(hilbert(x, N=next_fast_len(n))[:n])
    sq = env ** 2
    sq -= sq.mean()
    w = np.hanning(n)
    S = np.abs(np.fft.rfft(sq * w)) * 2 / w.sum()
    f = np.fft.rfftfreq(n, 1 / fs)
    m = f <= FMAX
    return f[m], S[m]


def cpw(x):
    """Prewhitening : amplitude spectrale mise à 1, phase conservée.
    (version simplifiée du cepstrum editing de Sawalhi & Randall)"""
    X = np.fft.rfft(x - x.mean())
    return np.fft.irfft(X / (np.abs(X) + 1e-12), n=len(x))


def peak_db(f, S, f0, tol=TOL):
    """dB au-dessus de la médiane (20-500 Hz) du max dans f0*(1+/-tol)."""
    floor = np.median(S[(f >= FMIN) & (f <= FMAX)])
    m = (f >= f0 * (1 - tol)) & (f <= f0 * (1 + tol))
    if not m.any():
        return -np.inf, np.nan
    i = S[m].argmax()
    return 20 * np.log10(S[m][i] / floor), f[m][i]


def measure(f, S, r):
    fr, bpfi, bpfo, bsf, bsf2 = r.fr_hz, r.bpfi_hz, r.bpfo_hz, r.bsf_hz, r.bsf2_hz
    out = {
        "BPFI": peak_db(f, S, bpfi)[0],
        "BPFI_sb-": peak_db(f, S, bpfi - fr)[0],
        "BPFI_sb+": peak_db(f, S, bpfi + fr)[0],
        "BPFO": peak_db(f, S, bpfo)[0],
        "2xBPFO": peak_db(f, S, 2 * bpfo)[0],
        "BPFO_sb-": peak_db(f, S, bpfo - fr)[0],
        "BPFO_sb+": peak_db(f, S, bpfo + fr)[0],
        "BSF": peak_db(f, S, bsf)[0],
        "2xBSF": peak_db(f, S, bsf2)[0],
    }
    return {k: round(float(v), 1) for k, v in out.items()}


def plot(fid, r, spectra, path):
    fig, axs = plt.subplots(2, 1, figsize=(11, 6), sharex=True)
    for ax, (name, (f, S)) in zip(axs, spectra.items()):
        ax.plot(f, S, lw=0.7, color="k")
        for h in (1, 2, 3):
            ax.axvline(h * r.bpfo_hz, color="tab:blue", ls="--", lw=0.9,
                       label="BPFO (x1,2,3)" if h == 1 else None)
            ax.axvline(h * r.bpfi_hz, color="tab:red", ls="-.", lw=0.9,
                       label="BPFI (x1,2,3)" if h == 1 else None)
        ax.axvline(r.bsf2_hz, color="tab:green", ls=":", lw=1.2, label="2xBSF")
        for k in range(1, 8):
            ax.axvline(k * r.fr_hz, color="gray", ls=":", lw=0.5,
                       label="k x fr" if k == 1 else None)
        ax.set_ylabel(f"SES {name}")
        ax.set_xlim(0, FMAX)
    axs[0].legend(ncol=5, fontsize=7, loc="upper right")
    axs[1].set_xlabel("Hz")
    fig.suptitle(f"Fichier {fid} - {r.classe} {r.taille_in:.3f}\" - {r.charge_hp} hp "
                 f"- rpm {r.rpm:.0f} - S&R {r.sr_cat_best}")
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def main(work_dir):
    work = Path(work_dir)
    out = work / "phase2"
    out.mkdir(exist_ok=True)
    meta = pd.read_csv(work / "metadata.csv").set_index("file_id")

    rows, verdicts = [], {}
    for fid in GATE_IR + GATE_OR + GATE_BALL_N:
        r = meta.loc[fid]
        r = r.rename(None)
        x = np.load(work / "signals_12k" / f"{fid}.npy")
        spectra = {"M1 (brut)": ses(x), "M2 (CPW)": ses(cpw(x))}
        plot(fid, r, spectra, out / f"{fid}.png")
        m1 = measure(*spectra["M1 (brut)"], r)
        m2 = measure(*spectra["M2 (CPW)"], r)
        rows.append({"file_id": fid, "classe": r.classe, **{f"M1_{k}": v for k, v in m1.items()},
                     **{f"M2_{k}": v for k, v in m2.items()}})

        # ---- critères du gate (M1 OU M2 suffit, comme dans le papier) ----
        def best(key):
            return max(m1[key], m2[key])

        if fid in GATE_IR:
            ok = best("BPFI") >= THR_DB and max(best("BPFI_sb-"), best("BPFI_sb+")) >= SB_DB
            why = f"BPFI={best('BPFI')} dB, sidebands={max(best('BPFI_sb-'), best('BPFI_sb+'))} dB"
        elif fid in GATE_OR:
            sb = max(best("BPFO_sb-"), best("BPFO_sb+"))
            ok = best("BPFO") >= THR_DB and sb <= best("BPFO") - 6
            why = f"BPFO={best('BPFO')} dB, 2xBPFO={best('2xBPFO')} dB, sidebands={sb} dB"
        else:  # Ball 0.007" (N1/N2 dans S&R)
            # M2 (CPW) : aucune signature de bille (S&R : N2 sur M2 et M3)
            # M1 : composantes à BPFO et BPFI présentes (défauts de bague
            # non intentionnels, cf. S&R Fig. 8). BSF (2.357 fr) est dans la
            # tolérance de 2.4 fr (harmonique de 0.2 fr), donc on ne juge PAS
            # la bille sur M1.
            c1 = max(m2["2xBSF"], m2["BSF"]) < THR_ABSENT
            c2 = m1["BPFO"] >= THR_DB and m1["BPFI"] >= THR_DB
            ok = c1 and c2
            why = (f"[M2 sans signature de bille < {THR_ABSENT}: {'ok' if c1 else 'ECHEC'}] "
                   f"M2: 2xBSF={m2['2xBSF']} BSF={m2['BSF']} | "
                   f"[M1 BPFO,BPFI >= {THR_DB}: {'ok' if c2 else 'ECHEC'}] "
                   f"M1: BPFO={m1['BPFO']} BPFI={m1['BPFI']}")
        verdicts[fid] = ok
        print(f"{fid:>4} {r.classe:<5} {'PASS' if ok else 'FAIL'}  {why}")

    pd.DataFrame(rows).to_csv(out / "gate.csv", index=False)

    n_ok = sum(verdicts.values())
    print(f"\nGATE : {n_ok}/{len(verdicts)} fichiers conformes")
    print("GATE PASSÉ" if n_ok == len(verdicts) else
          "GATE NON PASSÉ : regarder les PNG dans " + str(out))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--work_dir", default="work")
    main(ap.parse_args().work_dir)