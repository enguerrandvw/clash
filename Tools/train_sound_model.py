#!/usr/bin/env python3
"""
Entraîne un classificateur de sons de déploiement Clash Royale.

Principe : on ne compare plus des empreintes. On fabrique des dizaines de
milliers d'exemples réalistes en mélangeant chaque son de déploiement avec
du bruit d'arène à des volumes variables, puis on entraîne un petit réseau
à les reconnaître malgré ce bruit.

Le réseau est exporté en Swift : pas de CoreML, pas de fichier modèle.

Usage : train_sound_model.py <dossier_sons> <sortie.swift>
"""

import os
import re
import sys
import wave
import subprocess
import tempfile
import numpy as np

# --- Paramètres, identiques à ceux de l'extension iOS ---
RATE = 44100
FFT = 1024
HOP = 512
BANDS = 32
F_LOW, F_HIGH = 200.0, 11000.0
WINDOW_FRAMES = 26          # fenêtre captée après une impulsion
POOL = 2                    # regroupement temporel
IN_DIM = BANDS * (WINDOW_FRAMES // POOL)
HIDDEN = 96

# Cartes visées : le méta courant. En viser 120 serait hors de portée.
META = [
    "knight", "archer", "musketeer", "hog_rider", "mini_pekka", "valkyrie",
    "wizard", "baby_dragon", "skeleton_army", "goblin_gang", "giant",
    "balloon", "mega_knight", "prince", "bomber", "fireball", "zap",
    "the_log", "arrow", "cannon", "tesla", "witch", "electro_wizard",
    "ice_spirit", "skeleton", "bat", "firecracker", "dart_goblin",
]

DEPLOY_RE = re.compile(r"(^|[_\-\s])(dep|deploy|spawn|summon|cast|throw)", re.I)


def strip_prefix(folder):
    for p in ("card_champion_", "card_legendary_", "card_epic_",
              "card_rare_", "card_common_", "card_"):
        if folder.startswith(p):
            return folder[len(p):]
    return folder


def match_meta(folder):
    """Retrouve la carte visée malgré les pluriels et variantes de nommage."""
    plain = strip_prefix(folder)
    flat = plain.replace("_", "")
    for m in META:
        mf = m.replace("_", "")
        if flat == mf or flat == mf + "s" or flat + "s" == mf:
            return m
        # Le dossier peut porter un nom plus long : "pekka_mini", "log_the"
        if mf in flat and abs(len(flat) - len(mf)) <= 3:
            return m
    return None
AUDIO_EXT = (".wav", ".ogg", ".mp3", ".m4a", ".caf")

WIN = np.hanning(FFT).astype(np.float32)


def band_edges():
    edges, bin_hz = [], RATE / FFT
    for b in range(BANDS):
        f0 = F_LOW * (F_HIGH / F_LOW) ** (b / BANDS)
        f1 = F_LOW * (F_HIGH / F_LOW) ** ((b + 1) / BANDS)
        i0 = max(1, int(f0 / bin_hz))
        i1 = min(FFT // 2 - 1, max(i0 + 1, int(f1 / bin_hz)))
        edges.append((i0, i1))
    return edges


EDGES = band_edges()


def to_pcm(path):
    out = tempfile.mktemp(suffix=".wav")
    try:
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100",
                        "-c", "1", path, out], check=True, capture_output=True)
        return out
    except Exception:
        return None


def load(path, max_sec=4):
    pcm = to_pcm(path)
    if not pcm:
        return None
    try:
        with wave.open(pcm, "rb") as w:
            raw = w.readframes(min(w.getnframes(), RATE * max_sec))
            data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            if w.getnchannels() > 1:
                data = data[::w.getnchannels()]
        return data
    except Exception:
        return None
    finally:
        try:
            os.remove(pcm)
        except OSError:
            pass


def spectro(samples):
    """Reproduit exactement le calcul de l'extension iOS."""
    n = WINDOW_FRAMES
    need = FFT + HOP * (n - 1)
    if len(samples) < need:
        samples = np.pad(samples, (0, need - len(samples)))

    rows = []
    for k in range(n):
        i = k * HOP
        chunk = samples[i:i + FFT] * WIN
        mags = np.abs(np.fft.rfft(chunk))
        dbs = []
        for (i0, i1) in EDGES:
            avg = mags[i0:i1].mean() if i1 > i0 else 0.0
            dbs.append(20 * np.log10(max(avg, 1e-6)))
        peak = max(dbs)
        rows.append([np.clip((d - peak + 48) / 48, 0, 1) for d in dbs])

    a = np.array(rows, dtype=np.float32)          # (26, BANDS)
    a = a.reshape(n // POOL, POOL, BANDS).mean(axis=1)   # (13, BANDS)
    return a.flatten()


def main():
    root, out_path = sys.argv[1], sys.argv[2]

    deploys, noises = {}, []
    for dirpath, _, files in os.walk(root):
        folder = os.path.basename(dirpath)
        for f in files:
            if not f.lower().endswith(AUDIO_EXT):
                continue
            path = os.path.join(dirpath, f)
            is_card = folder.startswith("card_")
            if is_card and DEPLOY_RE.search(os.path.splitext(f)[0]):
                key = match_meta(folder)
                if key:
                    deploys.setdefault(key, []).append(path)
            else:
                # Tout le reste sert de bruit : musique, ambiance, attaques,
                # interface. C'est ce qui apprendra au réseau à ignorer
                # les pas d'un géant ou un tir de tour.
                noises.append(path)

    classes = sorted(deploys)
    print(f"{len(classes)} cartes retenues sur {len(META)} demandées")
    for c in classes:
        print(f"   {c:20s} {len(deploys[c])} son(s)")
    manquantes = [m for m in META if m not in deploys]
    if manquantes:
        print("Introuvables :", manquantes)
    print(f"{len(noises)} fichiers utilisables comme bruit")

    if len(classes) < 4:
        print("Pas assez de classes, abandon.")
        sys.exit(1)

    # --- Chargement en mémoire ---
    print("\nChargement des sons…")
    clean = {}
    for c in classes:
        arrs = [load(p, 2) for p in deploys[c][:4]]
        arrs = [a for a in arrs if a is not None and len(a) > FFT]
        if arrs:
            clean[c] = arrs
    classes = [c for c in classes if c in clean]

    rng = np.random.default_rng(0)
    noise_pool = []
    for p in rng.choice(noises, size=min(120, len(noises)), replace=False):
        a = load(p, 4)
        if a is not None and len(a) > RATE // 2:
            noise_pool.append(a)
    print(f"{len(noise_pool)} extraits de bruit chargés")

    need = FFT + HOP * (WINDOW_FRAMES - 1)

    def random_noise():
        if not noise_pool:
            return np.zeros(need, dtype=np.float32)
        a = noise_pool[rng.integers(len(noise_pool))]
        if len(a) <= need:
            return np.pad(a, (0, need - len(a)))
        s = rng.integers(0, len(a) - need)
        return a[s:s + need]

    # --- Génération des exemples ---
    PER_CLASS = 260
    labels = classes + ["__fond__"]      # dernière classe : aucun déploiement
    X, Y = [], []

    print("\nGénération des exemples…")
    for ci, c in enumerate(labels):
        for _ in range(PER_CLASS):
            bg = random_noise() * rng.uniform(0.05, 0.8)
            if c == "__fond__":
                mix = bg
            else:
                snd = clean[c][rng.integers(len(clean[c]))]
                snd = snd * rng.uniform(0.3, 1.0)
                # Décalage : le son arrive après le tintement d'élixir
                off = int(rng.integers(0, HOP * 8))
                buf = np.zeros(need, dtype=np.float32)
                end = min(need, off + len(snd))
                if end > off:
                    buf[off:end] = snd[:end - off]
                mix = buf + bg
            mix = np.clip(mix, -1, 1)
            X.append(spectro(mix))
            Y.append(ci)
        print(f"   {c}")

    X = np.array(X, dtype=np.float32)
    Y = np.array(Y)
    mu, sd = X.mean(0), X.std(0) + 1e-6
    X = (X - mu) / sd
    print(f"\n{X.shape[0]} exemples, {X.shape[1]} entrées, {len(labels)} classes")

    # --- Petit réseau, entraîné en numpy ---
    n_out = len(labels)
    W1 = rng.normal(0, np.sqrt(2 / IN_DIM), (IN_DIM, HIDDEN)).astype(np.float32)
    b1 = np.zeros(HIDDEN, dtype=np.float32)
    W2 = rng.normal(0, np.sqrt(2 / HIDDEN), (HIDDEN, n_out)).astype(np.float32)
    b2 = np.zeros(n_out, dtype=np.float32)

    idx = rng.permutation(len(X))
    cut = int(len(X) * 0.85)
    tr, va = idx[:cut], idx[cut:]
    lr, batch = 0.02, 128
    m = [np.zeros_like(p) for p in (W1, b1, W2, b2)]
    v = [np.zeros_like(p) for p in (W1, b1, W2, b2)]

    print("\nEntraînement…")
    for step in range(4000):
        b = rng.choice(tr, batch, replace=False)
        x, y = X[b], Y[b]

        h = np.maximum(0, x @ W1 + b1)
        o = h @ W2 + b2
        o -= o.max(1, keepdims=True)
        p = np.exp(o); p /= p.sum(1, keepdims=True)

        d = p.copy(); d[np.arange(batch), y] -= 1; d /= batch
        gW2 = h.T @ d; gb2 = d.sum(0)
        dh = (d @ W2.T) * (h > 0)
        gW1 = x.T @ dh; gb1 = dh.sum(0)

        for i, (par, g) in enumerate([(W1, gW1), (b1, gb1), (W2, gW2), (b2, gb2)]):
            m[i] = 0.9 * m[i] + 0.1 * g
            v[i] = 0.999 * v[i] + 0.001 * g * g
            par -= lr * m[i] / (np.sqrt(v[i]) + 1e-8)

        if step % 800 == 0 or step == 3999:
            hv = np.maximum(0, X[va] @ W1 + b1)
            acc = (np.argmax(hv @ W2 + b2, 1) == Y[va]).mean()
            print(f"   étape {step:4d} — précision validation {acc*100:.1f} %")

    hv = np.maximum(0, X[va] @ W1 + b1)
    pred = np.argmax(hv @ W2 + b2, 1)
    acc = (pred == Y[va]).mean()
    print(f"\nPRÉCISION FINALE : {acc*100:.1f} %")
    print("(hasard = %.1f %%)" % (100 / n_out))

    def arr(a):
        return "[" + ",".join(f"{x:.4f}" for x in np.asarray(a).flatten()) + "]"

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("// Généré automatiquement à la compilation. Ne pas modifier.\n\n")
        f.write("enum SoundModel {\n")
        f.write(f"    static let inputDim = {IN_DIM}\n")
        f.write(f"    static let hidden = {HIDDEN}\n")
        f.write(f"    static let bands = {BANDS}\n")
        f.write(f"    static let windowFrames = {WINDOW_FRAMES}\n")
        f.write(f"    static let pool = {POOL}\n")
        f.write(f"    static let accuracy = {acc:.3f}\n")
        f.write("    static let labels: [String] = [")
        f.write(", ".join(f'"{l}"' for l in labels))
        f.write("]\n")
        f.write(f"    static let mu: [Float] = {arr(mu)}\n")
        f.write(f"    static let sd: [Float] = {arr(sd)}\n")
        f.write(f"    static let w1: [Float] = {arr(W1)}\n")
        f.write(f"    static let b1: [Float] = {arr(b1)}\n")
        f.write(f"    static let w2: [Float] = {arr(W2)}\n")
        f.write(f"    static let b2: [Float] = {arr(b2)}\n")
        f.write("}\n")
    print("Écrit dans", out_path)


if __name__ == "__main__":
    main()
