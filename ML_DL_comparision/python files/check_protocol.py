"""Contrôle positif : le code est-il correct, ou est-ce le protocole qui est dur ?

Usage:
    python check_protocol.py --work_dir work --N 8192 --features ALL

Même modèle (XGBoost, mêmes hyperparamètres que la phase 6), trois protocoles de validation :
    1. fenêtres aléatoires (5 folds)        : protocole COURANT dans la littérature, avec fuite
                                              (des fenêtres d'un même fichier sont en train et en test)
    2. leave-one-load-out (par charge)      : fichiers jamais partagés, mais MÊME assemblage en train et en test
    3. leave-one-size-out (notre protocole) : assemblage jamais vu
Lecture : si 1 et 2 donnent des scores très élevés et 3 des scores plus bas, le code fonctionne et l'écart vient
du protocole (effet d'assemblage). Si même 1 est mauvais, il faut chercher un problème de code ou de features.
"""
import argparse
import json
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
from sklearn.model_selection import StratifiedKFold
from sklearn.utils.class_weight import compute_sample_weight
from xgboost import XGBClassifier

from phase6_supervised_ml import CLASSES, feature_sets

warnings.filterwarnings("ignore")


def fit_predict(Xtr, ytr, Xte):
    clf = XGBClassifier(n_estimators=100, max_depth=4, learning_rate=0.1, subsample=0.8, colsample_bytree=0.8,
                        objective="multi:softprob", tree_method="hist", random_state=0, n_jobs=-1)
    clf.fit(Xtr, ytr, sample_weight=compute_sample_weight("balanced", ytr))
    P = np.zeros((len(Xte), len(CLASSES)))
    P[:, clf.classes_] = clf.predict_proba(Xte)
    return P


def summarize(name, y, P):
    pred = P.argmax(1)
    det_true = (y != 0).astype(int)
    det_score = 1 - P[:, 0]
    return dict(protocole=name, n=len(y), accuracy=accuracy_score(y, pred),
                macro_f1=f1_score(y, pred, average="macro", zero_division=0),
                detection_acc=((pred != 0).astype(int) == det_true).mean(),
                detection_auc=roc_auc_score(det_true, det_score) if 0 < det_true.sum() < len(y) else np.nan)


def main(work_dir, N, features):
    work = Path(work_dir)
    F = pd.read_csv(work / f"features_N{N}.csv")
    cols = feature_sets(json.loads((work / "feature_groups.json").read_text()))[features]
    F["y"] = F.classe.map({c: i for i, c in enumerate(CLASSES)}).astype(int)
    X, y = F[cols].to_numpy(), F.y.to_numpy()
    rows = []

    # 1. fenêtres aléatoires
    P = np.zeros((len(F), len(CLASSES)))
    for tr, te in StratifiedKFold(5, shuffle=True, random_state=0).split(X, y):
        P[te] = fit_predict(X[tr], y[tr], X[te])
    rows.append(summarize("1. fenêtres aléatoires (avec fuite)", y, P))

    # 2. leave-one-load-out
    P = np.zeros((len(F), len(CLASSES)))
    for load in sorted(F.charge_hp.unique()):
        te = (F.charge_hp == load).to_numpy()
        P[te] = fit_predict(X[~te], y[~te], X[te])
    rows.append(summarize("2. leave-one-load-out (même assemblage)", y, P))

    # 3. leave-one-size-out (splits.json)
    folds = json.loads((work / "splits.json").read_text())
    P = np.zeros((len(F), len(CLASSES)))
    covered = np.zeros(len(F), dtype=bool)
    for fold in folds:
        te = F.file_id.isin(fold["test"]).to_numpy()
        tr = F.file_id.isin(fold["train"]).to_numpy()
        P[te] = fit_predict(X[tr], y[tr], X[te])
        covered |= te
    rows.append(summarize("3. leave-one-size-out (assemblage inconnu)", y[covered], P[covered]))

    pd.set_option("display.width", 200)
    print(f"features={features} ({len(cols)}), N={N}\n")
    print(pd.DataFrame(rows).round(3).to_string(index=False))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--work_dir", default="work")
    ap.add_argument("--N", type=int, default=8192)
    ap.add_argument("--features", default="ALL", choices=["TD", "ENV", "ALL", "ALL-rms"])
    a = ap.parse_args()
    main(a.work_dir, a.N, a.features)
