"""Phase 1 : inventaire CWRU, rééchantillonnage du Normal 48k -> 12k, metadata.csv

Usage:
    python phase1_metadata.py --data_dir /chemin/vers/mat --out_dir work
Sorties:
    work/metadata.csv
    work/signals_12k/<file_id>.npy   (signal DE à 12 kHz)
"""
import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.signal import resample_poly
from scipy.stats import kurtosis

from cwru_common import (GROUPS, NOMINAL_RPM, SR_CAT, SR_KURT, fault_freqs,
                         find_mat, load_de)


def main(data_dir, out_dir):
    out_dir = Path(out_dir)
    sig_dir = out_dir / "signals_12k"
    sig_dir.mkdir(parents=True, exist_ok=True)

    rows, missing = [], []
    for cls, size, ids in GROUPS:
        for load, fid in enumerate(ids):
            path = find_mat(data_dir, fid)
            if path is None:
                missing.append(fid)
                continue
            x, rpm = load_de(path)
            fs_orig = 48_000 if cls == "Normal" else 12_000
            kurt_calc = float(kurtosis(x, fisher=False))  # Pearson, Gauss = 3

            # Normal : 48 kHz -> 12 kHz (filtre anti-repliement intégré, Kaiser)
            x12 = resample_poly(x, 1, 4) if fs_orig == 48_000 else x
            np.save(sig_dir / f"{fid}.npy", x12)

            rpm_source = "mat"
            if rpm is None:
                rpm, rpm_source = float(NOMINAL_RPM[load]), "nominal"
            ff = fault_freqs(rpm)
            sr_m1, sr_best = SR_CAT[fid]

            rows.append(dict(
                file_id=fid, classe=cls, taille_in=size, charge_hp=load,
                group=f"{cls}_{size:.3f}",  # unité d'assemblage pour les splits
                fs_orig=fs_orig, n_samples_12k=len(x12),
                duree_s=len(x12) / 12_000,
                rpm=rpm, rpm_source=rpm_source,
                fr_hz=ff["fr"], bpfi_hz=ff["BPFI"], bpfo_hz=ff["BPFO"],
                bsf_hz=ff["BSF"], bsf2_hz=ff["BSF2"], ftf_hz=ff["FTF"],
                sr_cat_m1=sr_m1, sr_cat_best=sr_best,
                sr_kurtosis=SR_KURT[fid], kurtosis_calc=round(kurt_calc, 2),
                # Normal sert de référence dans tous les sous-ensembles
                subset_A=(sr_best in ("Y1", "Y2", "Normal")),
                subset_B=True,
                subset_C=(sr_best in ("N1", "N2", "Normal")),
            ))

    df = pd.DataFrame(rows)
    df.to_csv(out_dir / "metadata.csv", index=False)

    # ---- contrôles de cohérence ----
    print(f"{len(df)} fichiers traités -> {out_dir / 'metadata.csv'}")
    if missing:
        print(f"!! Fichiers introuvables : {missing}")
    bad_rpm = df[(df.rpm / df.charge_hp.map(NOMINAL_RPM) - 1).abs() > 0.02]
    if len(bad_rpm):
        print("!! RPM s'écartant de >2 % du nominal :")
        print(bad_rpm[["file_id", "rpm", "rpm_source"]].to_string(index=False))
    kdiff = df[(df.kurtosis_calc - df.sr_kurtosis).abs() > 0.5]
    if len(kdiff):
        print("!! Kurtosis calculé vs S&R (écart > 0.5), à inspecter :")
        print(kdiff[["file_id", "kurtosis_calc", "sr_kurtosis"]].to_string(index=False))
    print("\nEffectifs par groupe (assemblage) :")
    print(df.groupby("group").size().to_string())
    print(f"\nSous-ensembles : A={df.subset_A.sum()}  B={df.subset_B.sum()}  C={df.subset_C.sum()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data_dir", required=True)
    ap.add_argument("--out_dir", default="work")
    a = ap.parse_args()
    main(a.data_dir, a.out_dir)
