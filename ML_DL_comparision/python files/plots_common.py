import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from sklearn.metrics import auc, roc_curve


def plot_confusion(cms, classes, path):
    """cms: {nom_modèle: matrice (comptes)}."""
    n, k = len(cms), len(classes)
    fig, axs = plt.subplots(1, n, figsize=(5 * n, 4.6), squeeze=False)
    for ax, (name, cm) in zip(axs[0], cms.items()):
        cmn = cm / np.maximum(cm.sum(axis=1, keepdims=True), 1)
        ax.imshow(cmn, vmin=0, vmax=1, cmap="Blues")
        for i in range(k):
            for j in range(k):
                ax.text(j, i, f"{cm[i, j]}\n{cmn[i, j]:.0%}", ha="center", va="center", fontsize=9,
                        color="white" if cmn[i, j] > 0.5 else "black")
        ax.set_xticks(range(k)); ax.set_xticklabels(classes)
        ax.set_yticks(range(k)); ax.set_yticklabels(classes)
        ax.set_xlabel("Prédit"); ax.set_ylabel("Vrai"); ax.set_title(name)
    fig.tight_layout(); fig.savefig(path, dpi=120); plt.close(fig)


def plot_roc(ys, Ps, classes, path):
    """ys: {nom: [y_true par répétition]}, Ps: {nom: [proba (n, C) par répétition]}."""
    n = len(ys)
    grid = np.linspace(0, 1, 200)
    fig, axs = plt.subplots(1, n, figsize=(5 * n, 4.6), squeeze=False)
    for ax, name in zip(axs[0], ys):
        y, P = np.concatenate(ys[name]), np.vstack(Ps[name])
        tprs = []
        for c, cname in enumerate(classes):
            yb = (y == c).astype(int)
            if yb.sum() == 0 or yb.sum() == len(yb):
                continue
            fpr, tpr, _ = roc_curve(yb, P[:, c])
            ax.plot(fpr, tpr, lw=1.2, label=f"{cname} (AUC {auc(fpr, tpr):.2f})")
            tprs.append(np.interp(grid, fpr, tpr))
        m = np.mean(tprs, axis=0)
        ax.plot(grid, m, "k--", lw=1.5, label=f"macro (AUC {auc(grid, m):.2f})")
        ax.plot([0, 1], [0, 1], ":", color="gray")
        ax.set_xlabel("FPR"); ax.set_ylabel("TPR"); ax.set_title(f"ROC (OvR) - {name}")
        ax.legend(fontsize=8, loc="lower right"); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig(path, dpi=120); plt.close(fig)


def plot_curves(curves, path, mode="mean"):
    """curves: {nom: [hist, ...]}, un hist par répétition.
    mode: 'mean' = moyenne ± écart-type | 'all' = une courbe par répétition | 'both' = les deux."""
    n = len(curves)
    fig, axs = plt.subplots(2, n, figsize=(5 * n, 7), squeeze=False)
    specs = [("tr_loss", "va_loss", "Loss"), ("tr_err", "va_err", "Erreur (1 - accuracy)")]
    for j, (name, runs) in enumerate(curves.items()):
        x = np.asarray(runs[0]["x"])
        for i, (a, b, t) in enumerate(specs):
            ax = axs[i, j]
            for key, color, lab in ((a, "tab:blue", "entraînement"), (b, "tab:orange", "validation")):
                Y = np.array([np.asarray(h[key], dtype=float) for h in runs])
                if mode in ("all", "both"):
                    for k, y in enumerate(Y):
                        ax.plot(x, y, color=color, lw=0.8, alpha=0.35 if mode == "both" else 0.7,
                                label=lab if (mode == "all" and k == 0) else None)
                if mode in ("mean", "both"):
                    m = Y.mean(axis=0)
                    ax.plot(x, m, color=color, lw=2, label=f"{lab} (moyenne, {len(Y)} rép.)")
            ax.set_title(f"{name} - {t}")
            ax.set_xlabel(runs[0]["xlabel"])
            ax.set_ylabel(t)
            ax.grid(alpha=0.3)
            ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)