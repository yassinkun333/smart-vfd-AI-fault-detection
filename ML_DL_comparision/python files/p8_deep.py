"""Deep learning sur signaux bruts : MLP, CNN 1D, GRU, LSTM (PyTorch).
Usage:
    python p8_deep.py --work_dir workallfiles --win 4096 --overlap 0.75 --split file --repeats 10 --models cnn \
        --lr 1e-4 --aug --dropout 0.5 --weight_decay 1e-2 --suffix _cnnA
Sorties : <work_dir>/W<win>_ov<ov>/dl_W<win>_ov<ov><suffix>/ (CSV + PNG)
"""
import argparse
import json
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from numpy.lib.stride_tricks import sliding_window_view
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, recall_score, roc_auc_score
from sklearn.preprocessing import LabelEncoder

from p6_models import make_folds
from plots_common import plot_confusion, plot_curves, plot_roc

warnings.filterwarnings("ignore")
NAMES = {"mlp": "MLP", "cnn": "CNN 1D", "gru": "GRU", "lstm": "LSTM"}


# ---------------- données ----------------
def build_windows(work, sig_dir, win, ov, ids, norm):
    meta = pd.read_csv(work / "metadata.csv")
    meta = meta[meta.file_id.isin(ids)]
    hop = max(1, int(round(win * (1 - ov))))
    Xs, rows = [], []
    for _, r in meta.iterrows():
        x = np.load(work / sig_dir / f"{int(r.file_id)}.npy").astype(np.float32)
        x -= x.mean()
        if len(x) < win:
            continue
        W = sliding_window_view(x, win)[::hop]
        W = W - W.mean(axis=1, keepdims=True)
        Xs.append(W.copy())
        rows += [dict(file_id=int(r.file_id), classe=r.classe, win_idx=i) for i in range(len(W))]
    X = np.concatenate(Xs).astype(np.float32)
    X = X / (X.std(axis=1, keepdims=True) + 1e-8) if norm == "window" else X / X.std()
    return X, pd.DataFrame(rows)


# ---------------- modèles ----------------
class MLP(nn.Module):
    def __init__(s, L, C, dropout=0.3, **_):
        super().__init__()
        s.net = nn.Sequential(nn.Flatten(), nn.Linear(L, 256), nn.ReLU(), nn.Dropout(dropout),
                              nn.Linear(256, 64), nn.ReLU(), nn.Dropout(dropout), nn.Linear(64, C))

    def forward(s, x):
        return s.net(x)


class CNN(nn.Module):
    def __init__(s, L, C, dropout=0.3, width=1.0, **_):
        super().__init__()
        c = [max(4, int(round(v * width))) for v in (16, 32, 64, 64)]
        blk = lambda i, o, k, st=1: nn.Sequential(nn.Conv1d(i, o, k, stride=st, padding=k // 2),
                                                  nn.BatchNorm1d(o), nn.ReLU(), nn.MaxPool1d(2))
        s.f = nn.Sequential(blk(1, c[0], 64, 8), blk(c[0], c[1], 3), blk(c[1], c[2], 3), blk(c[2], c[3], 3),
                            nn.AdaptiveAvgPool1d(1), nn.Flatten())
        s.h = nn.Sequential(nn.Dropout(dropout), nn.Linear(c[3], C))

    def forward(s, x):
        return s.h(s.f(x))


class RNN(nn.Module):
    def __init__(s, L, C, kind="gru", patch=16, dropout=0.3, **_):
        super().__init__()
        s.patch, s.T = patch, L // patch
        s.rnn = (nn.GRU if kind == "gru" else nn.LSTM)(patch, 64, batch_first=True)
        s.h = nn.Sequential(nn.Dropout(dropout), nn.Linear(64, C))

    def forward(s, x):
        B = x.shape[0]
        seq = x[:, 0, :s.T * s.patch].reshape(B, s.T, s.patch)
        o, _ = s.rnn(seq)
        return s.h(o.mean(dim=1))


def make_model(key, L, C, a):
    if key == "mlp":
        return MLP(L, C, dropout=a.dropout)
    if key == "cnn":
        return CNN(L, C, dropout=a.dropout, width=a.width)
    return RNN(L, C, kind=key, patch=a.patch, dropout=a.dropout)


# ---------------- entraînement ----------------
def augment(x, noise):
    """Décalage circulaire aléatoire + polarité aléatoire + bruit gaussien (entraînement seulement)."""
    B, _, L = x.shape
    shift = torch.randint(0, L, (B,), device=x.device)
    idx = (torch.arange(L, device=x.device)[None, :] + shift[:, None]) % L
    x = x.gather(2, idx[:, None, :])
    sign = (torch.randint(0, 2, (B, 1, 1), device=x.device) * 2 - 1).to(x.dtype)
    return x * sign + noise * torch.randn_like(x)


@torch.no_grad()
def predict_logits(model, X, bs=512):
    model.eval()
    return torch.cat([model(X[i:i + bs]) for i in range(0, len(X), bs)])


def train(model, Xa, ya, Xb, yb, C, a, dev):
    n = len(ya)
    cnt = np.bincount(ya.cpu().numpy(), minlength=C)
    w = torch.tensor(n / (C * np.maximum(cnt, 1)), dtype=torch.float32, device=dev)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=a.weight_decay)
    lw = nn.CrossEntropyLoss(weight=w, label_smoothing=a.label_smoothing)
    lsum = nn.CrossEntropyLoss(reduction="sum")          # loss rapportée : CE simple, sans lissage
    h = dict(x=np.arange(1, a.epochs + 1), xlabel="epoch", tr_loss=[], va_loss=[], tr_err=[], va_err=[])
    best, best_state = float("inf"), None
    for _ in range(a.epochs):
        model.train()
        perm = torch.randperm(n, device=dev)
        tl = te = m = 0
        for i in range(0, n, a.batch):
            idx = perm[i:i + a.batch]
            if len(idx) < 2:
                continue
            xi, yi = Xa[idx], ya[idx]
            if a.aug:
                xi = augment(xi, a.aug_noise)
            opt.zero_grad()
            out = model(xi)
            lw(out, yi).backward()
            opt.step()
            tl += lsum(out.detach(), yi).item()
            te += (out.argmax(1) != yi).sum().item()
            m += len(idx)
        lv = predict_logits(model, Xb)
        vl = lsum(lv, yb).item() / len(yb)
        h["tr_loss"].append(tl / m); h["tr_err"].append(te / m)
        h["va_loss"].append(vl); h["va_err"].append((lv.argmax(1) != yb).float().mean().item())
        if a.restore_best and vl < best:
            best = vl
            best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}
    if best_state is not None:
        model.load_state_dict(best_state)
    return h


def auc_macro_ovr(y, proba):
    present = np.unique(y)
    if len(present) < 2:
        return np.nan
    P = proba[:, present]
    P = P / np.maximum(P.sum(axis=1, keepdims=True), 1e-12)
    return roc_auc_score(y, P, multi_class="ovr", average="macro", labels=present)


def main(a):
    work = Path(a.work_dir)
    base = f"W{a.win}_ov{int(round(a.overlap * 100))}"
    tag = f"{base}_{a.split}{a.suffix}"
    outdir = work / base / f"dl_{base}{a.suffix}"
    outdir.mkdir(parents=True, exist_ok=True)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    ids = set(json.loads((work / "diag_files.json").read_text())["file_ids"])
    X, F = build_windows(work, a.sig_dir, a.win, a.overlap, ids, a.norm)
    le = LabelEncoder().fit(F.classe)
    C, y_all = len(le.classes_), le.transform(F.classe)
    folds = make_folds(F, a.split, a.test_frac, a.repeats, a.seed)
    print(f"{tag} | device={dev} | norm={a.norm} | classes {list(le.classes_)} | "
          f"{F.file_id.nunique()} fichiers | {len(F)} fenêtres de {a.win} pts | epochs={a.epochs}")
    print(f"régularisation : dropout={a.dropout} wd={a.weight_decay} aug={a.aug} "
          f"label_smoothing={a.label_smoothing} width={a.width} restore_best={a.restore_best}")
    if a.win % a.patch:
        print(f"!! win non multiple de patch={a.patch} : la fin de la fenêtre est ignorée par GRU/LSTM")

    Xt = torch.from_numpy(X)[:, None, :].to(dev)
    yt = torch.from_numpy(y_all).long().to(dev)

    rows, ys, Ps, curves = [], {}, {}, {}
    cms = {NAMES[k]: np.zeros((C, C), dtype=int) for k in a.models}
    for r, fold in enumerate(folds):
        inner = make_folds(F.loc[fold["tr"]], a.split, 0.2, 1, a.seed + r)[0]
        ia, ib, ite = inner["tr"], inner["te"], fold["te"]
        for key in a.models:
            name = NAMES[key]
            torch.manual_seed(a.seed + r)
            model = make_model(key, a.win, C, a).to(dev)
            h = train(model, Xt[ia], yt[ia], Xt[ib], yt[ib], C, a, dev)
            proba = torch.softmax(predict_logits(model, Xt[ite]), 1).cpu().numpy()
            y_te, p = y_all[ite], proba.argmax(1)
            cms[name] += confusion_matrix(y_te, p, labels=np.arange(C))
            ys.setdefault(name, []).append(y_te); Ps.setdefault(name, []).append(proba)
            curves.setdefault(name, []).append(h)
            rows.append(dict(model=name, fold=fold["name"], n=len(ite),
                             accuracy=accuracy_score(y_te, p),
                             macro_f1=f1_score(y_te, p, average="macro", zero_division=0),
                             macro_recall=recall_score(y_te, p, average="macro", zero_division=0),
                             auc_macro_ovr=auc_macro_ovr(y_te, proba)))
            print(f"  rép {r + 1}/{len(folds)} {name:<7} acc={rows[-1]['accuracy']:.3f} "
                  f"f1={rows[-1]['macro_f1']:.3f} (val_loss finale {h['va_loss'][-1]:.3f})")

    R = pd.DataFrame(rows)
    metrics = ["accuracy", "macro_f1", "macro_recall", "auc_macro_ovr"]
    mean = R.groupby("model", sort=False).agg(n=("n", "mean"), **{m: (m, "mean") for m in metrics})
    std = R.groupby("model", sort=False)[metrics].std().add_suffix("_std")
    out = pd.concat([mean, std], axis=1).reset_index()
    out["n"] = out.n.round().astype(int)
    out["gap_loss"] = out.model.map({n: np.mean([h["va_loss"][-1] - h["tr_loss"][-1] for h in v])
                                     for n, v in curves.items()})
    out["gap_err"] = out.model.map({n: np.mean([h["va_err"][-1] - h["tr_err"][-1] for h in v])
                                    for n, v in curves.items()})
    out.round(3).to_csv(outdir / f"p8_deep_{tag}.csv", index=False)

    plot_confusion(cms, list(le.classes_), outdir / f"p8_confusion_{tag}.png")
    plot_roc(ys, Ps, list(le.classes_), outdir / f"p8_roc_{tag}.png")
    plot_curves(curves, outdir / f"p8_curves_{tag}.png")

    pd.set_option("display.width", 200)
    print()
    print(out[["model", "n"] + metrics].round(3).to_string(index=False))
    if a.repeats > 1:
        print("\nÉcart-type sur les répétitions :")
        print(std.round(3).to_string())
    print("\nÉcart validation - entraînement à la fin (overfitting) :")
    print(out[["model", "gap_loss", "gap_err"]].round(3).to_string(index=False))
    print(f"\nRésultats et figures dans : {outdir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--work_dir", default="work")
    ap.add_argument("--sig_dir", default="signals_12k")
    ap.add_argument("--win", type=int, default=1024)
    ap.add_argument("--overlap", type=float, default=0.5)
    ap.add_argument("--split", choices=["window", "file"], default="file")
    ap.add_argument("--test_frac", type=float, default=0.3)
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--models", nargs="+", default=["mlp", "cnn", "gru", "lstm"], choices=list(NAMES))
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--batch", type=int, default=128)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--patch", type=int, default=16)
    ap.add_argument("--norm", choices=["window", "global"], default="window")
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--weight_decay", type=float, default=1e-4)
    ap.add_argument("--width", type=float, default=1.0, help="multiplicateur de canaux du CNN")
    ap.add_argument("--label_smoothing", type=float, default=0.0)
    ap.add_argument("--aug", action="store_true", help="augmentation (shift, polarité, bruit)")
    ap.add_argument("--aug_noise", type=float, default=0.1)
    ap.add_argument("--restore_best", action="store_true", help="garde les poids de la meilleure val loss")
    ap.add_argument("--suffix", default="", help="ex. _cnnA : sépare les dossiers de sortie")
    main(ap.parse_args())