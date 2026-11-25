"""Sélection des fichiers diagnosticables (plus de splits ici : le split aléatoire est dans p6).
Usage: python p3_splits.py --work_dir work [--cats Y1 Y2] [--classes Normal IR OR]
Sortie: work/diag_files.json
"""
import argparse
import json
from pathlib import Path

import pandas as pd


def main(work_dir, cats, classes):
    work = Path(work_dir)
    meta = pd.read_csv(work / "metadata.csv")
    meta = meta[meta.classe.isin(classes)]
    keep = meta[(meta.classe == "Normal") | meta.sr_cat_best.isin(cats)]
    ids = sorted(int(i) for i in keep.file_id)
    (work / "diag_files.json").write_text(json.dumps(dict(cats=cats, classes=classes, file_ids=ids), indent=1))
    print(f"{len(ids)} fichiers retenus -> {work / 'diag_files.json'}")
    print(keep.groupby(["classe", "taille_in"]).file_id.apply(list).to_string())


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--work_dir", default="work")
    ap.add_argument("--cats", nargs="+", default=["Y1", "Y2"])
    ap.add_argument("--classes", nargs="+", default=["Normal", "IR", "OR"])
    a = ap.parse_args()
    main(a.work_dir, a.cats, a.classes)