"""XGBoost / ANN (MLP) / Random Forest + confusion, ROC, courbes train/validation, sélection MI optionnelle.
Usage:
    python p7_compare.py --work_dir workallfiles --win 4096 --overlap 0.75 --split file --repeats 10 --features ALL-rms
    python p7_compare.py --work_dir workallfiles --win 4096 --overlap 0.75 --split file --repeats 10 --features ALL-rms --mi_k 10
Sorties : <work_dir>/W<win>_ov<ov>/ml_W<win>_ov<ov>/
Courbes : une par répétition (train interne 80 % / validation 20 %), moyennées dans la figure.
"""
import argparse
import json
import warnings
from pathlib import Path
from sklearn.feature_selection import mutual_info_classif
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.feature_selection import mutual_info_classif
from sklearn.metrics import (accuracy_score, confusion_matrix, f1_score, log_loss,
                             recall_score, roc_auc_score)
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.utils.class_weight import compute_sample_weight
from xgboost import XGBClassifier

from p6_models import feature_sets, make_folds
from plots_common import plot_confusion, plot_curves, plot_roc
import matplotlib.pyplot as plt

warnings.filterwarnings("ignore")
EPOCHS = 100
HP = {
    "base": dict(
        xgb=dict(n_estimators=300, max_depth=4, learning_rate=0.1, subsample=0.8, colsample_bytree=0.8),
        rf=dict(n_estimators=300, max_depth=8),
        mlp=dict(hidden_layer_sizes=(64, 32), alpha=1e-4)),
    "reg": dict(
        xgb=dict(n_estimators=150, max_depth=3, learning_rate=0.05, subsample=0.6, colsample_bytree=0.5,
                 min_child_weight=10, reg_lambda=10, reg_alpha=1, gamma=1),
        rf=dict(n_estimators=300, max_depth=5, min_samples_leaf=50, max_features=0.3, max_samples=0.5),
        mlp=dict(hidden_layer_sizes=(32, 16), alpha=1e-1)),  
    "mid": dict(
        xgb=dict(n_estimators=200, max_depth=3, learning_rate=0.1, subsample=0.7, colsample_bytree=0.7,
                 min_child_weight=5, reg_lambda=5),
        rf=dict(n_estimators=300, max_depth=8, min_samples_leaf=20, max_features=0.5, max_samples=0.7),
        mlp=dict(hidden_layer_sizes=(64, 32), alpha=1e-2)),
}
ACTIVE = HP["base"]

def build_models(seed):
    h = ACTIVE
    return {
        "XGBoost": lambda: XGBClassifier(eval_metric="mlogloss", random_state=seed, n_jobs=-1, **h["xgb"]),
        "ANN (MLP)": lambda: make_pipeline(StandardScaler(), MLPClassifier(
            early_stopping=False, max_iter=EPOCHS, random_state=seed, **h["mlp"])),
        "Random Forest": lambda: RandomForestClassifier(
            class_weight="balanced", random_state=seed, n_jobs=-1, **h["rf"]),
    }


def fit_predict(name, mk, Xtr, ytr, Xte, n_cls):
    clf = mk()
    if name == "XGBoost":
        clf.fit(Xtr, ytr, sample_weight=compute_sample_weight("balanced", ytr))
    else:
        clf.fit(Xtr, ytr)
    proba = np.zeros((len(Xte), n_cls))
    proba[:, clf.classes_] = clf.predict_proba(Xte)
    return proba.argmax(axis=1), proba


def auc_macro_ovr(y, proba):
    present = np.unique(y)
    if len(present) < 2:
        return np.nan
    P = proba[:, present]
    P = P / np.maximum(P.sum(axis=1, keepdims=True), 1e-12)
    return roc_auc_score(y, P, multi_class="ovr", average="macro", labels=present)


def select_mi(tr, cols, ytr, k, seed):
    """Top-k features par information mutuelle, calculée sur le train uniquement."""
    mi = mutual_info_classif(tr[cols].to_numpy(), ytr, random_state=seed)
    order = np.argsort(mi)[::-1]
    return [cols[i] for i in order[:k]], dict(zip(cols, mi))


# ---------- courbes train / validation ----------
def _hist(x, xlabel, tl, vl, te, ve):
    return dict(x=np.asarray(x), xlabel=xlabel, tr_loss=tl, va_loss=vl, tr_err=te, va_err=ve)


def _ll(y, P, n_cls):
    return log_loss(y, np.clip(P, 1e-7, 1), labels=np.arange(n_cls))


def curve_xgb(Xa, ya, Xb, yb, seed, n_cls):
    clf = XGBClassifier(eval_metric=["mlogloss", "merror"], random_state=seed, n_jobs=-1, **ACTIVE["xgb"])
    clf.fit(Xa, ya, sample_weight=compute_sample_weight("balanced", ya),
            eval_set=[(Xa, ya), (Xb, yb)], verbose=False)
    r = clf.evals_result()
    n = len(r["validation_0"]["mlogloss"])
    return _hist(np.arange(1, n + 1), "n_estimators (boosting rounds)",
                 r["validation_0"]["mlogloss"], r["validation_1"]["mlogloss"],
                 r["validation_0"]["merror"], r["validation_1"]["merror"])


def curve_mlp(Xa, ya, Xb, yb, seed, n_cls):
    sc = StandardScaler().fit(Xa)
    A, B = sc.transform(Xa), sc.transform(Xb)
    clf = MLPClassifier(random_state=seed, **ACTIVE["mlp"])
    labels = np.arange(n_cls)
    tl, vl, te, ve = [], [], [], []
    for _ in range(EPOCHS):
        clf.partial_fit(A, ya, classes=labels)
        pa, pb = clf.predict_proba(A), clf.predict_proba(B)
        tl.append(_ll(ya, pa, n_cls)); vl.append(_ll(yb, pb, n_cls))
        te.append(1 - (pa.argmax(1) == ya).mean()); ve.append(1 - (pb.argmax(1) == yb).mean())
    return _hist(np.arange(1, EPOCHS + 1), "epoch", tl, vl, te, ve)


def curve_rf(Xa, ya, Xb, yb, seed, n_cls):
    p = dict(ACTIVE["rf"])
    n_max = p.pop("n_estimators")
    clf = RandomForestClassifier(n_estimators=10, warm_start=True, class_weight="balanced",
                                 random_state=seed, n_jobs=-1, **p)
    xs, tl, vl, te, ve = [], [], [], [], []

    def full(X):
        P = np.zeros((len(X), n_cls)); P[:, clf.classes_] = clf.predict_proba(X); return P
    for n in range(10, n_max + 1, 10):
        clf.set_params(n_estimators=n).fit(Xa, ya)
        pa, pb = full(Xa), full(Xb)
        xs.append(n); tl.append(_ll(ya, pa, n_cls)); vl.append(_ll(yb, pb, n_cls))
        te.append(1 - (pa.argmax(1) == ya).mean()); ve.append(1 - (pb.argmax(1) == yb).mean())
    return _hist(xs, "n_estimators (arbres)", tl, vl, te, ve)


CURVES = {"XGBoost": curve_xgb, "ANN (MLP)": curve_mlp, "Random Forest": curve_rf}


def main(work_dir, win, ov, split, test_frac, repeats, seed, fs_name, no_curves, mi_k, reg):
    work = Path(work_dir)
    base = f"W{win}_ov{int(round(ov * 100))}"
    global ACTIVE
    ACTIVE = HP[reg]
    tag = f"{base}_{split}" + (f"_mi{mi_k}" if mi_k else "") + ("" if reg == "base" else f"_{reg}")
    outdir = work / base / f"ml_{base}"
    outdir.mkdir(parents=True, exist_ok=True)
    F = pd.read_csv(work / f"features_{base}.csv")
    ids = set(json.loads((work / "diag_files.json").read_text())["file_ids"])
    F = F[F.file_id.isin(ids)].reset_index(drop=True)
    cols = feature_sets(json.loads((work / "feature_groups.json").read_text()))[fs_name]
    le = LabelEncoder().fit(F.classe)
    C = len(le.classes_)
    folds = make_folds(F, split, test_frac, repeats, seed)
    print(f"{tag} | features={fs_name} ({len(cols)})" + (f" -> MI top-{mi_k}" if mi_k else "") +
          f" | test={test_frac} x{repeats} | classes {list(le.classes_)} | "
          f"{F.file_id.nunique()} fichiers | {len(F)} fenêtres")

    rows, ys, Ps, mi_rows = [], {}, {}, []
    cms = {n: np.zeros((C, C), dtype=int) for n in build_models(seed)}
    for r, fold in enumerate(folds):
        tr, te = F.loc[fold["tr"]], F.loc[fold["te"]]
        ytr, yte = le.transform(tr.classe), le.transform(te.classe)
        fcols = cols
        if mi_k:
            fcols, mi = select_mi(tr, cols, ytr, mi_k, seed + r)
            mi_rows.append(mi)
        fold["cols"] = fcols
        for name, mk in build_models(seed).items():
            p, proba = fit_predict(name, mk, tr[fcols].to_numpy(), ytr, te[fcols].to_numpy(), C)
            cms[name] += confusion_matrix(yte, p, labels=np.arange(C))
            ys.setdefault(name, []).append(yte); Ps.setdefault(name, []).append(proba)
            rows.append(dict(model=name, fold=fold["name"], n=len(te),
                             accuracy=accuracy_score(yte, p),
                             macro_f1=f1_score(yte, p, average="macro", zero_division=0),
                             macro_recall=recall_score(yte, p, average="macro", zero_division=0),
                             auc_macro_ovr=auc_macro_ovr(yte, proba)))
    R = pd.DataFrame(rows)
    metrics = ["accuracy", "macro_f1", "macro_recall", "auc_macro_ovr"]
    mean = R.groupby("model", sort=False).agg(n=("n", "mean"), **{m: (m, "mean") for m in metrics})
    std = R.groupby("model", sort=False)[metrics].std().add_suffix("_std")
    out = pd.concat([mean, std], axis=1).reset_index()
    out["n"] = out.n.round().astype(int)
    out.round(3).to_csv(outdir / f"p7_compare_{tag}.csv", index=False)

    plot_confusion(cms, list(le.classes_), outdir / f"p7_confusion_{tag}.png")
    plot_roc(ys, Ps, list(le.classes_), outdir / f"p7_roc_{tag}.png")

    if not no_curves:
        curves = {n: [] for n in CURVES}
        for r, fold in enumerate(folds):
            inner = make_folds(F.loc[fold["tr"]], split, 0.2, 1, seed + r)[0]
            a, b = F.loc[inner["tr"]], F.loc[inner["te"]]
            fc = fold["cols"]
            Xa, ya = a[fc].to_numpy(), le.transform(a.classe)
            Xb, yb = b[fc].to_numpy(), le.transform(b.classe)
            for n, fn in CURVES.items():
                curves[n].append(fn(Xa, ya, Xb, yb, seed, C))
        plot_curves(curves, outdir / f"p7_curves_{tag}.png")

    if mi_rows:
        M = pd.DataFrame(mi_rows)
        freq = pd.Series({c: np.mean([c in f["cols"] for f in folds]) for c in cols})
        rep = pd.DataFrame({"mi_mean": M.mean(), "mi_std": M.std(), "freq_selection": freq}) \
            .sort_values("mi_mean", ascending=False)
        rep.round(3).to_csv(outdir / f"p7_mi_{tag}.csv")
        fig, ax = plt.subplots(figsize=(7, 0.32 * len(rep) + 1.5))
        yy = np.arange(len(rep))[::-1]
        ax.barh(yy, rep.mi_mean, xerr=rep.mi_std.fillna(0), capsize=2, color="tab:blue", alpha=0.85)
        ax.set_yticks(yy); ax.set_yticklabels(rep.index)
        ax.set_xlabel("Information mutuelle (moyenne ± écart-type sur les répétitions)")
        ax.set_title(f"MI par feature - top {mi_k} retenues")
        ax.grid(axis="x", alpha=0.3)
        fig.tight_layout(); fig.savefig(outdir / f"p7_mi_{tag}.png", dpi=120); plt.close(fig)
        print("\nClassement MI (moyenne sur les répétitions) :")
        print(rep.round(3).to_string())

    pd.set_option("display.width", 200)
    print()
    print(mean.reset_index().assign(n=lambda d: d.n.round().astype(int)).round(3).to_string(index=False))
    if repeats > 1:
        print("\nÉcart-type sur les répétitions :")
        print(std.round(3).to_string())
    print(f"\nRésultats et figures dans : {outdir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--work_dir", default="work")
    ap.add_argument("--win", type=int, default=1024)
    ap.add_argument("--overlap", type=float, default=0.5)
    ap.add_argument("--split", choices=["window", "file"], default="file")
    ap.add_argument("--test_frac", type=float, default=0.3)
    ap.add_argument("--repeats", type=int, default=10)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--features", default="ALL-rms",
                    choices=["RMS", "KURT", "TD", "BK", "ENV", "ALL", "ALL-rms"])
    ap.add_argument("--no_curves", action="store_true")
    ap.add_argument("--mi_k", type=int, default=0, help="garde les K meilleures features par information mutuelle (0 = toutes)")
    ap.add_argument("--reg", choices=["base", "mid", "reg"], default="base", help="jeu d'hyperparamètres régularisés")
    a = ap.parse_args()
    main(a.work_dir, a.win, a.overlap, a.split, a.test_frac, a.repeats, a.seed, a.features, a.no_curves, a.mi_k, a.reg)