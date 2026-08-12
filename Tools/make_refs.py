#!/usr/bin/env python3
"""
Calcule l'empreinte spectrale de chaque son de déploiement du jeu.

Le calcul reproduit EXACTEMENT celui de l'extension iOS : mêmes tailles de
fenêtre, mêmes bandes, même échelle en décibels. Toute divergence ici rendrait
la comparaison impossible côté app.

Usage : make_refs.py <dossier_sons> <sortie.swift>
"""

import os
import re
import sys
import wave
import subprocess
import tempfile
import numpy as np

RATE = 44100
FFT = 1024
HOP = 512            # chevauchement de moitié, comme l'extension
BANDS = 32
F_LOW, F_HIGH = 200.0, 11000.0
FRAMES = 40          # ~0,46 s : la partie caractéristique du son

DEPLOY_RE = re.compile(r"(^|[_\-\s])(dep|deploy|spawn|summon)", re.I)
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


def strip_prefix(folder):
    for p in ("card_champion_", "card_legendary_", "card_epic_",
              "card_rare_", "card_common_", "card_"):
        if folder.startswith(p):
            return folder[len(p):]
    return folder


def to_pcm(path):
    out = tempfile.mktemp(suffix=".wav")
    try:
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100",
                        "-c", "1", path, out], check=True, capture_output=True)
        return out
    except Exception:
        return None


def load(path):
    pcm = to_pcm(path)
    if not pcm:
        return None
    try:
        with wave.open(pcm, "rb") as w:
            raw = w.readframes(min(w.getnframes(), RATE * 3))
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


def fingerprint(samples):
    """Spectrogramme en dB, calé sur l'attaque, normalisé sur son pic."""
    if samples is None or len(samples) < FFT * 2:
        return None

    env = np.abs(samples)
    peak = env.max()
    if peak < 1e-4:
        return None

    # Début du son : premier dépassement de 15 % du maximum
    start = int(np.argmax(env > peak * 0.15))
    start = max(0, start - HOP)

    rows = []
    for k in range(FRAMES):
        i = start + k * HOP
        if i + FFT > len(samples):
            break
        chunk = samples[i:i + FFT] * WIN
        mags = np.abs(np.fft.rfft(chunk))
        row = []
        for (i0, i1) in EDGES:
            avg = mags[i0:i1].mean() if i1 > i0 else 0.0
            row.append(20 * np.log10(max(avg, 1e-6)))
        rows.append(row)

    if len(rows) < 20:
        return None
    a = np.array(rows, dtype=np.float32)

    # Normalisation sur le pic, puis seuil : on ne garde que le corps du son.
    a = a - a.max()                       # 0 dB au sommet
    a = np.clip((a + 40) / 40, 0, 1)      # 40 dB de dynamique
    a[a < 0.45] = 0                       # même seuil que côté app
    a = (a - 0.45) / 0.55
    a = np.clip(a, 0, 1)
    return (a * 255).astype(np.uint8)


def main():
    root, out_path = sys.argv[1], sys.argv[2]

    found = {}
    total = 0
    for dirpath, _, files in os.walk(root):
        folder = os.path.basename(dirpath)
        if not folder.startswith("card_"):
            continue
        for f in files:
            if not f.lower().endswith(AUDIO_EXT):
                continue
            total += 1
            if DEPLOY_RE.search(os.path.splitext(f)[0]):
                found.setdefault(folder, []).append(os.path.join(dirpath, f))

    print(f"{total} fichiers audio · {len(found)} cartes avec un déploiement")

    entries = []
    skipped = 0
    for folder in sorted(found):
        for path in sorted(found[folder])[:3]:
            fp = fingerprint(load(path))
            if fp is None:
                skipped += 1
                continue
            entries.append((strip_prefix(folder), os.path.basename(path), fp))

    print(f"{len(entries)} empreintes · {skipped} ignorées")

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("// Généré automatiquement à la compilation. Ne pas modifier.\n\n")
        fh.write("struct SoundRef {\n")
        fh.write("    let card: String\n")
        fh.write("    let file: String\n")
        fh.write("    let frames: [[UInt8]]\n")
        fh.write("}\n\n")
        fh.write("enum SoundRefs {\n")
        fh.write("    static let all: [SoundRef] = [\n")
        for card, name, fp in entries:
            rows = ", ".join("[" + ",".join(str(int(v)) for v in row) + "]"
                             for row in fp)
            fh.write(f'        SoundRef(card: "{card}", file: "{name}", '
                     f'frames: [{rows}]),\n')
        fh.write("    ]\n")
        fh.write("}\n")
    print("Écrit dans", out_path)


if __name__ == "__main__":
    main()
