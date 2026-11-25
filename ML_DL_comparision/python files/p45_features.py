"""Phases 4+5 : fenêtrage (longueur dynamique) + features.
Usage:
    python p45_features.py --work_dir work --win 1024
    python p45_features.py --work_dir work --win 512 1024 2048 --overlap 0.75
    python p45_features.py --work_dir work --win 1024 --bands raw      # sans banc de filtres
Sortie : work/features_W<win>_ov<overlap%>.csv + work/feature_groups.json
"""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from numpy.lib.stride_tricks import sliding_window_view
from scipy.signal import butter, hilbert, sosfiltfilt
from scipy.stats import kurtosis, skew

FMIN, FMAX = 10.0, 600.0
TOL = 0.02       # +/-2 % autour des fréquences de défaut
LOCAL = 0.15     # demi-largeur relative du plancher local
DEFAULT_BANDS = ["1000-3000", "2000-4000", "3000-5000", "4000-5800"]

TD = ["rms", "kurtosis", "skewness", "crest", "shape", "impulse"]
BAND_KURT = None  # défini selon --bands
ENV_PEAK = ["BPFO_h1", "BPFO_h2", "BPFO_h3", "BPFI_h1", "BPFI_h2", "BPFI_h3",
            "BSF2_h1", "BSF2_h2", "BPFI_sb", "BPFO_sb"]
ENV_BAND = ["e_BPFO", "e_BPFI", "e_BSF2", "log_e_BPFI_over_BPFO"]
ENV_ENT = ["spec_entropy"]


def tag(win, ov):
    return f"W{win}_ov{int(round(ov * 100))}"


def make_bands(specs, fs):
    bands = []
    for s in specs:
        if s == "raw":
            bands.append(("raw", None))
            continue
        lo, hi = (float(v) for v in s.split("-"))
        if hi >= fs / 2:
            hi = 0.97 * fs / 2
        sos = butter(4, [lo, hi], btype="band", fs=fs, output="sos")
        bands.append((f"{int(lo)}_{int(hi)}", sos))
    return bands


def windows(x, N, hop):
    W = sliding_window_view(x, N)[::hop]
    return W - W.mean(axis=1, keepdims=True)


def ses_batch(W, fs, nfft):
    env = np.abs(hilbert(W, axis=1))
    sq = env ** 2
    sq -= sq.mean(axis=1, keepdims=True)
    w = np.hanning(W.shape[1])
    S = np.abs(np.fft.rfft(sq * w, n=nfft, axis=1)) * 2 / w.sum()
    f = np.fft.rfftfreq(nfft, 1 / fs)
    m = f <= FMAX
    return f[m], S[:, m]


def peak_ratio_db(f, S, f0, res):
    hw = max(TOL * f0, res)
    inb = (f >= f0 - hw) & (f <= f0 + hw)
    if not inb.any():
        return np.zeros(len(S))
    lw = max(LOCAL * f0, 4 * res)
    loc = (f >= f0 - lw) & (f <= f0 + lw) & ~inb
    floor = np.median(S[:, loc], axis=1) + 1e-18
    return 20 * np.log10(S[:, inb].max(axis=1) / floor + 1e-12)


def env_features(W, r, fs, nfft):
    f, S = ses_batch(W, fs, nfft)
    res = fs / W.shape[1]
    fr, bpfo, bpfi, bsf2 = r.fr_hz, r.bpfo_hz, r.bpfi_hz, r.bsf2_hz
    out = {}
    for h in (1, 2, 3):
        out[f"BPFO_h{h}"] = peak_ratio_db(f, S, h * bpfo, res)
        out[f"BPFI_h{h}"] = peak_ratio_db(f, S, h * bpfi, res)
    for h in (1, 2):
        out[f"BSF2_h{h}"] = peak_ratio_db(f, S, h * bsf2, res)
    out["BPFI_sb"] = np.maximum(peak_ratio_db(f, S, bpfi - fr, res), peak_ratio_db(f, S, bpfi + fr, res))
    out["BPFO_sb"] = np.maximum(peak_ratio_db(f, S, bpfo - fr, res), peak_ratio_db(f, S, bpfo + fr, res))

    P = S ** 2
    use = (f >= FMIN) & (f <= FMAX)
    total = P[:, use].sum(axis=1) + 1e-30

    def frac(f0, hs):
        m = np.zeros_like(f, dtype=bool)
        for h in hs:
            hw = max(TOL * h * f0, res)
            m |= (f >= h * f0 - hw) & (f <= h * f0 + hw)
        return P[:, m & use].sum(axis=1) / total

    out["e_BPFO"] = frac(bpfo, (1, 2, 3))
    out["e_BPFI"] = frac(bpfi, (1, 2, 3))
    out["e_BSF2"] = frac(bsf2, (1, 2))
    out["log_e_BPFI_over_BPFO"] = np.log10((out["e_BPFI"] + 1e-6) / (out["e_BPFO"] + 1e-6))
    p = P[:, use] / total[:, None]
    out["spec_entropy"] = -(p * np.log(p + 1e-30)).sum(axis=1) / np.log(p.shape[1])
    return out


def td_features(W):
    rms = np.sqrt((W ** 2).mean(axis=1))
    ma = np.abs(W).mean(axis=1) + 1e-12
    pk = np.abs(W).max(axis=1)
    return dict(rms=rms, kurtosis=kurtosis(W, axis=1, fisher=False), skewness=skew(W, axis=1),
                crest=pk / (rms + 1e-12), shape=rms / ma, impulse=pk / ma)


def main(work_dir, wins, ov, band_specs, fs, sig_dir):
    work = Path(work_dir)
    meta = pd.read_csv(work / "metadata.csv").set_index("file_id")
    bands = make_bands(band_specs, fs)
    bk_cols = [f"bk_{n}" for n, _ in bands]
    groups = dict(TD=TD, BAND_KURT=bk_cols + ["bk_max"], ENV_PEAK=ENV_PEAK, ENV_BAND=ENV_BAND, ENV_ENT=ENV_ENT)
    (work / "feature_groups.json").write_text(json.dumps(groups, indent=1))
    env_names = ENV_PEAK + ENV_BAND + ENV_ENT

    for N in wins: 
        hop = max(1, int(round(N * (1 - ov))))
        nfft = 1 << int(np.ceil(np.log2(4 * N)))
        print(f"\nWIN={N} pts ({N / fs * 1000:.0f} ms), hop={hop}, résolution {fs / N:.1f} Hz, nfft={nfft}")
        if fs / N > 15:
            print("   !! résolution > 15 Hz : BPFO/BPFI/fr risquent d'être confondus")
        parts = []
        for fid, r in meta.iterrows():
            x = np.load(work / sig_dir / f"{fid}.npy").astype(np.float64)
            x -= x.mean()
            if len(x) < N:
                print(f"!! fichier {fid} trop court")
                continue
            filt = [x if sos is None else sosfiltfilt(sos, x) for _, sos in bands]
            Wraw = windows(x, N, hop)
            feats = td_features(Wraw)
            Wb = [windows(s, N, hop) for s in filt]
            bk = np.stack([kurtosis(W, axis=1, fisher=False) for W in Wb], axis=1)
            for j, c in enumerate(bk_cols):
                feats[c] = bk[:, j]
            feats["bk_max"] = bk.max(axis=1)
            best = bk.argmax(axis=1)          # bande la plus impulsive, sans labels
            per_band = [env_features(W, r, fs, nfft) for W in Wb]
            for k in env_names:
                stack = np.stack([d[k] for d in per_band], axis=1)
                feats[k] = np.take_along_axis(stack, best[:, None], axis=1)[:, 0]
            d = pd.DataFrame(feats)
            d.insert(0, "win_idx", np.arange(len(d)))
            d.insert(0, "file_id", int(fid))
            parts.append(d)
        F = pd.concat(parts, ignore_index=True)
        keep = ["classe", "group", "taille_in", "charge_hp", "sr_cat_best"]
        F = F.merge(meta[keep].reset_index(), on="file_id", how="left")
        out = work / f"features_{tag(N, ov)}.csv"
        F.to_csv(out, index=False)
        allcols = [c for g in groups.values() for c in g]
        print(f"{len(F)} fenêtres x {len(allcols)} features -> {out} | NaN : {F[allcols].isna().sum().sum()}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--work_dir", default="work")
    ap.add_argument("--win", type=int, nargs="+", default=[1024], help="longueur de fenêtre en points")
    ap.add_argument("--overlap", type=float, default=0.5)
    ap.add_argument("--bands", nargs="+", default=DEFAULT_BANDS, help="ex. 1000-3000 2000-4000, ou raw")
    ap.add_argument("--fs", type=float, default=12000)
    ap.add_argument("--sig_dir", default="signals_12k")
    a = ap.parse_args()
    main(a.work_dir, a.win, a.overlap, a.bands, a.fs, a.sig_dir)