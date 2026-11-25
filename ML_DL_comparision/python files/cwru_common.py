"""Constantes et utilitaires communs (phases 1 et 2)."""
import re
from pathlib import Path

import numpy as np
import scipy.io as sio

FS = 12_000  # Hz, fréquence de travail après rééchantillonnage

# Multiples de f_r pour le roulement drive end 6205-2RS (Smith & Randall, Table 2)
FACTORS = dict(BPFI=5.415, BPFO=3.585, FTF=0.3983, BSF=2.357)

NOMINAL_RPM = {0: 1797, 1: 1772, 2: 1750, 3: 1730}  # selon la charge (hp)

# (classe, taille en pouces, [file_id par charge 0,1,2,3 hp])
GROUPS = [
    ("Normal", 0.000, [97, 98, 99, 100]),
    ("IR",   0.007, [105, 106, 107, 108]),
    ("IR",   0.014, [169, 170, 171, 172]),
    ("IR",   0.021, [209, 210, 211, 212]),
    ("Ball", 0.007, [118, 119, 120, 121]),
    ("Ball", 0.014, [185, 186, 187, 188]),
    ("Ball", 0.021, [222, 223, 224, 225]),
    ("OR",   0.007, [130, 131, 132, 133]),
    ("OR",   0.014, [197, 198, 199, 200]),
    ("OR",   0.021, [234, 235, 236, 237]),
]

# Kurtosis publié (Tables B1/B2, mesure DE)
SR_KURT = {
    97: 2.76, 98: 2.93, 99: 2.93, 100: 2.96,
    105: 5.40, 106: 5.54, 107: 5.56, 108: 5.29,
    169: 22.0, 170: 22.1, 171: 21.7, 172: 18.2,
    209: 7.45, 210: 7.67, 211: 8.06, 212: 8.35,
    118: 2.98, 119: 2.96, 120: 2.83, 121: 2.89,
    185: 17.8, 186: 8.84, 187: 9.75, 188: 14.9,
    222: 8.55, 223: 9.41, 224: 3.30, 225: 3.11,
    130: 7.65, 131: 7.60, 132: 7.85, 133: 7.96,
    197: 3.06, 198: 2.94, 199: 3.02, 200: 3.80,
    234: 21.0, 235: 22.0, 236: 23.2, 237: 23.5,
}

# Catégorie S&R, mesure DE : (M1 = signal brut, best = meilleure des 3 méthodes)
# Transcrit depuis les Tables B1/B2 : A VÉRIFIER contre le papier.
SR_CAT = {
    97: ("Normal", "Normal"), 98: ("Normal", "Normal"),
    99: ("Normal", "Normal"), 100: ("Normal", "Normal"),
    105: ("Y2", "Y2"), 106: ("Y2", "Y2"), 107: ("Y2", "Y2"), 108: ("Y2", "Y2"),
    169: ("Y2", "Y2"), 170: ("Y2", "Y2"), 171: ("P1", "Y2"), 172: ("Y2", "Y2"),
    209: ("Y1", "Y1"), 210: ("Y1", "Y1"), 211: ("Y1", "Y1"), 212: ("Y1", "Y1"),
    118: ("N1", "N1"), 119: ("N1", "N1"), 120: ("N1", "N1"), 121: ("N1", "Y2"),
    185: ("P2", "P2"), 186: ("P2", "P2"), 187: ("N1", "P2"), 188: ("P2", "P2"),
    222: ("P1", "Y2"), 223: ("Y2", "Y2"), 224: ("N1", "N1"), 225: ("N1", "N1"),
    130: ("Y1", "Y1"), 131: ("Y1", "Y1"), 132: ("Y1", "Y1"), 133: ("Y1", "Y1"),
    197: ("N1", "Y2"), 198: ("P2", "P2"), 199: ("P1", "P1"), 200: ("N1", "N1"),
    234: ("Y2", "Y2"), 235: ("Y2", "Y2"), 236: ("Y2", "Y2"), 237: ("Y2", "Y2"),
}


def fault_freqs(rpm):
    fr = rpm / 60.0
    return dict(
        fr=fr,
        BPFI=FACTORS["BPFI"] * fr,
        BPFO=FACTORS["BPFO"] * fr,
        FTF=FACTORS["FTF"] * fr,
        BSF=FACTORS["BSF"] * fr,
        BSF2=2 * FACTORS["BSF"] * fr,
    )


def find_mat(data_dir, fid):
    for pat in (f"{fid}.mat", f"{fid:03d}.mat"):
        hits = sorted(Path(data_dir).rglob(pat))
        if hits:
            return hits[0]
    return None


def load_de(path):
    """Retourne (signal DE 1D float64, rpm ou None)."""
    m = sio.loadmat(str(path))
    kde = [k for k in m if re.fullmatch(r"X\d+_DE_time", k)]
    if not kde:
        raise KeyError(f"Pas de variable *_DE_time dans {path}")
    x = np.asarray(m[kde[0]]).ravel().astype(np.float64)
    krpm = [k for k in m if re.fullmatch(r"X\d+RPM", k)]
    rpm = float(np.asarray(m[krpm[0]]).ravel()[0]) if krpm else None
    return x, rpm
