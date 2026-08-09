#!/usr/bin/env python3
"""
Parcourt le dépôt de sons de Clash Royale, repère les sons de déploiement,
et calcule pour chacun une empreinte spectrale identique à celle produite
par l'extension de capture sur iPhone.

Usage : make_fingerprints.py <dossier_sons> <sortie.swift>
"""

import os
import re
import sys
import wave
import struct
import subprocess
import tempfile
from collections import defaultdict

import numpy as np

FFT_SIZE = 1024
HOP = 512
BANDS = 16
F_LOW, F_HIGH = 200.0, 11000.0
RATE = 44100
N_FRAMES = 8            # 8 trames ≈ 0,19 s : la signature d'attaque du son

# Noms de fichiers considérés comme des sons de déploiement
DEPLOY_RE = re.compile(r"(^|[_\-\s])(dep|deploy|spawn|summon)", re.I)


def to_pcm(path):
    """Convertit n'importe quel audio en WAV mono 16 bits via afconvert (macOS)."""
    out = tempfile.mktemp(suffix=".wav")
    try:
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", path, out],
            check=True, capture_output=True)
        return out
    except Exception:
        return None


def read_samples(path):
    try:
        with wave.open(path, "rb") as w:
            n = w.getnframes()
            raw = w.readframes(min(n, RATE * 3))       # 3 secondes maximum
            data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            if w.getnchannels() > 1:
                data = data[::w.getnchannels()]
            return data
    except Exception:
        return None


def band_edges():
    edges = []
    bin_hz = RATE / FFT_SIZE
    for b in range(BANDS):
        f0 = F_LOW * (F_HIGH / F_LOW) ** (b / BANDS)
        f1 = F_LOW * (F_HIGH / F_LOW) ** ((b + 1) / BANDS)
        i0 = max(1, int(f0 / bin_hz))
        i1 = min(FFT_SIZE // 2 - 1, max(i0 + 1, int(f1 / bin_hz)))
        edges.append((i0, i1))
    return edges


EDGES = band_edges()
WINDOW = np.hanning(FFT_SIZE).astype(np.float32)


def fingerprint(samples):
    """Retourne N_FRAMES x BANDS valeurs 0-255, à partir du début du son."""
    if samples is None or len(samples) < FFT_SIZE * 2:
        return None

    # On se cale sur l'attaque : première position dépassant 20 % du maximum
    env = np.abs(samples)
    peak = env.max()
    if peak < 1e-4:
        return None
    start = int(np.argmax(env > peak * 0.2))
    start = max(0, start - HOP)

    frames = []
    for k in range(N_FRAMES):
        i = start + k * HOP
        if i + FFT_SIZE > len(samples):
            break
        chunk = samples[i:i + FFT_SIZE] * WINDOW
        mags = np.abs(np.fft.rfft(chunk))
        dbs = []
        for (i0, i1) in EDGES:
            avg = mags[i0:i1].mean() if i1 > i0 else 0.0
            dbs.append(20 * np.log10(max(avg, 1e-6)))
        # Forme normalisée : identique au calcul de l'extension iOS
        peak_db = max(dbs)
        row = [int(np.clip((d - peak_db + 48) / 48 * 255, 0, 255)) for d in dbs]
        frames.append(row)

    if len(frames) < 4:
        return None
    while len(frames) < N_FRAMES:
        frames.append(frames[-1])
    return frames


def main():
    root, out_path = sys.argv[1], sys.argv[2]

    print("=== Exploration de l'arborescence ===")
    tops = sorted(d for d in os.listdir(root) if not d.startswith("."))
    print(f"{len(tops)} éléments à la racine :", tops[:12])

    found = defaultdict(list)
    total_audio = 0

    for dirpath, _, files in os.walk(root):
        for f in files:
            if not f.lower().endswith((".wav", ".ogg", ".mp3", ".m4a", ".caf")):
                continue
            total_audio += 1
            if not DEPLOY_RE.search(os.path.splitext(f)[0]):
                continue
            card = os.path.basename(dirpath)
            found[card].append(os.path.join(dirpath, f))

    print(f"{total_audio} fichiers audio au total")
    print(f"{len(found)} cartes avec un son de déploiement")

    entries = []
    skipped = 0
    for card in sorted(found):
        for path in sorted(found[card])[:3]:      # 3 variantes maximum par carte
            pcm = to_pcm(path)
            if not pcm:
                skipped += 1
                continue
            fp = fingerprint(read_samples(pcm))
            try:
                os.remove(pcm)
            except OSError:
                pass
            if fp is None:
                skipped += 1
                continue
            entries.append((card, os.path.basename(path), fp))

    print(f"{len(entries)} empreintes calculées, {skipped} ignorées")

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("// Fichier généré automatiquement à la compilation.\n")
        fh.write("// Ne pas modifier à la main.\n\n")
        fh.write("struct SoundRef {\n")
        fh.write("    let card: String\n")
        fh.write("    let file: String\n")
        fh.write("    let frames: [[UInt8]]\n")
        fh.write("}\n\n")
        fh.write("enum SoundRefs {\n")
        fh.write("    static let all: [SoundRef] = [\n")
        for card, name, fp in entries:
            rows = ", ".join("[" + ",".join(str(v) for v in row) + "]" for row in fp)
            fh.write(f'        SoundRef(card: "{card}", file: "{name}", frames: [{rows}]),\n')
        fh.write("    ]\n")
        fh.write("}\n")

    print("Écrit dans", out_path)


if __name__ == "__main__":
    main()
