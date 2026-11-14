#!/usr/bin/env python3
"""Synthesizes the photonsword sound effects and the sound script that defines them.

    python3 tools/gen_sounds.py

Writes audio to media/sound/PhotonSword/ and the script to media/scripts/sounds_photonsword.txt
(both regenerated from scratch). Hum, swing, and hit come in several tones; swings and hits are
also rendered at several pitches, because the game plays them by name and Lua can't re-pitch them.
The hum is pitched at runtime instead (see client/PhotonSword/PS_Hum.lua).

The hum loops are WAVs built from whole-cycle sinusoids and circular (FFT) noise, so they loop
with no seam. One-shots are Ogg Vorbis via ffmpeg. Needs numpy and ffmpeg.
"""
import glob
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                     "PhotonSword", "Contents", "mods", "PhotonSword", "42", "media")
OUT = os.path.join(MEDIA, "sound", "PhotonSword")
SCRIPT = os.path.join(MEDIA, "scripts", "sounds_photonsword.txt")
HUM_HZ = 95.0  # hum fundamental; the ignite and extinguish sweeps land on / leave from it

# Must match the option lists in client/PhotonSword/PS_Options.lua and PS_Core.lua.
PITCHES = [70, 80, 90, 100, 110, 120, 130]  # percent, for swings and hits
TONES = {
    # harmonics: (multiple, amplitude); hiss: noise level; wobble: amplitude modulation depth;
    # crackle: chance per sample of a spark spike in the noise; sparks: how much a hit throws sparks.
    "Smooth": {"harmonics": [(1, 1.0), (2, 0.3), (3, 0.08)], "hiss": 0.02, "wobble": 0.05, "crackle": 0.0,
               "sparks": 0.6},
    "Classic": {"harmonics": [(1, 1.0), (2, 0.5), (3, 0.25), (4, 0.12), (5, 0.06), (7, 0.04), (9, 0.03),
                              (11, 0.02)], "hiss": 0.05, "wobble": 0.08, "crackle": 0.0, "sparks": 1.0},
    "Gritty": {"harmonics": [(1, 1.0), (2, 0.6), (3, 0.45), (4, 0.25), (5, 0.2), (7, 0.15), (9, 0.12),
                             (11, 0.1), (13, 0.08), (15, 0.06)], "hiss": 0.1, "wobble": 0.14, "crackle": 0.004,
               "sparks": 1.6},
}
CLASSIC = TONES["Classic"]
rng = np.random.default_rng(42)


def times(seconds):
    return np.arange(int(SR * seconds)) / SR


def bandpass(signal, low, high):
    """Brick-wall band filter applied in the frequency domain (circular, so loop-safe)."""
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / SR)
    spectrum[(freqs < low) | (freqs > high)] = 0
    return np.fft.irfft(spectrum, len(signal))


def noise(n, low, high):
    return bandpass(rng.standard_normal(n), low, high)


def sparks(n, chance):
    """Sparse random spikes, band-limited so they crackle rather than click."""
    if chance <= 0:
        return np.zeros(n)
    return bandpass((rng.random(n) < chance) * rng.standard_normal(n), 1500, 9000)


def sweep(freq):
    """Sine whose instantaneous frequency follows the array `freq`."""
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def buzz(freq, harmonics):
    """Fundamental plus decaying harmonics: the sword's electric timbre."""
    return sum(amp * sweep(freq * k) for k, amp in harmonics)


def normalize(signal, peak_db=-3.0):
    return signal / np.max(np.abs(signal)) * 10 ** (peak_db / 20)


def fade(signal, fade_in, fade_out):
    env = np.ones(len(signal))
    a, b = int(SR * fade_in), int(SR * fade_out)
    if a:
        env[:a] = np.linspace(0, 1, a)
    if b:
        env[-b:] = np.minimum(env[-b:], np.linspace(1, 0, b))
    return signal * env


def hum(tone, seconds=4.0):
    # Every frequency is a whole number of cycles over the loop, so the end meets the start.
    t = times(seconds)
    step = 1 / seconds
    assert (HUM_HZ / step).is_integer()
    tone_wave = sum(amp * np.sin(2 * np.pi * HUM_HZ * k * t) for k, amp in tone["harmonics"])
    tone_wave += 0.6 * np.sin(2 * np.pi * (HUM_HZ + 3 * step) * t)  # slow beating against the fundamental
    w = tone["wobble"]
    wobble = 1 + w * np.sin(2 * np.pi * 2 * step * t) + (w / 2) * np.sin(2 * np.pi * 7 * step * t)
    hiss = tone["hiss"] * normalize(noise(len(t), 1500, 6000) + 4 * sparks(len(t), tone["crackle"]), 0)
    return normalize(tone_wave * wobble + hiss, -6.0)


def ignite():
    t = times(1.1)
    rise = np.clip(t / 0.35, 0, 1)
    freq = 35 + (HUM_HZ - 35) * (1 - (1 - rise) ** 3)
    body = buzz(freq, CLASSIC["harmonics"])
    whine = 0.35 * sweep(300 + 1700 * rise ** 0.5) * np.exp(-t * 4)
    snap = 1.5 * noise(len(t), 800, 9000) * np.exp(-t * 40)
    signal = body * np.minimum(1, t / 0.02) + whine + snap
    return normalize(fade(signal, 0.002, 0.35), -3.0)


def extinguish():
    t = times(0.9)
    fall = np.clip(t / 0.6, 0, 1)
    freq = HUM_HZ - (HUM_HZ - 28) * fall ** 0.7
    body = buzz(freq, CLASSIC["harmonics"]) * (1 - fall) ** 1.5
    whine = 0.3 * sweep(1400 - 1150 * fall ** 0.5) * np.exp(-t * 6)
    puff = 0.5 * noise(len(t), 300, 4000) * np.exp(-((t - 0.05) / 0.04) ** 2)
    return normalize(fade(body + whine + puff, 0.003, 0.15), -3.0)


def swing(seconds, variation, tone, pitch):
    """pitch scales every frequency (synthesized, not resampled), so length stays the same."""
    t = times(seconds)
    arc = np.sin(np.pi * t / seconds)
    p = variation * pitch
    freq = HUM_HZ * p * (1 + 0.45 * arc)  # doppler-style bend up and back down
    body = buzz(freq, tone["harmonics"])
    whoosh = 0.8 * noise(len(t), 400 * p, min(3500 * p, 16000))
    crackle = 3 * sparks(len(t), tone["crackle"])
    return normalize((body + whoosh + crackle) * arc ** 2, -3.0)


SWINGS = [(0.42, 1.0), (0.50, 1.1), (0.55, 0.92)]  # (seconds, pitch variation) per clip


def band(low, high):
    """Clamps a pitched band to below Nyquist."""
    top = SR / 2 - 500
    return min(low, top - 1000), min(high, top)


def hit(seconds, variation, tone, pitch):
    """A spark burst: a bright crack, a shower of sparks thinning out, a sizzle tail, and a short
    electric zap in the tone's timbre over a low thump."""
    t = times(seconds)
    n = len(t)
    p = variation * pitch
    amount = tone["sparks"]
    crack = 1.2 * noise(n, *band(2500 * p, 14000 * p)) * np.exp(-t * 70)
    shower = (rng.random(n) < 0.035 * amount * np.exp(-t * 7)) * rng.standard_normal(n)
    shower = 3.0 * bandpass(shower, *band(1800 * p, 12000 * p))
    sizzle = 0.35 * amount * noise(n, *band(3000 * p, 10000 * p)) * np.exp(-t * 10)
    zap = 0.45 * buzz(np.full(n, HUM_HZ * 2 * p), tone["harmonics"]) * np.exp(-t * 16)
    thump = 0.7 * sweep(140 * p * np.exp(-t * 6)) * np.exp(-t * 20)
    return normalize(fade(crack + shower + sizzle + zap + thump, 0.001, 0.08), -3.0)


HITS = [(0.38, 1.0), (0.45, 0.9)]  # (seconds, pitch variation) per clip


def write_wav(path, signal):
    data = (np.clip(signal, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def write_ogg(path, signal):
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "out.wav")
        write_wav(wav_path, signal)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
                        "-c:a", "libvorbis", "-q:a", "5", path], check=True)


def sound_block(name, files, distance_max, loop=False):
    lines = [f"    sound {name}", "    {", "        category = Item,"]
    if loop:
        lines += ["        loop = true,", "        is3D = true,"]
    for f in files:
        lines += ["        clip", "        {", f"            file = media/sound/PhotonSword/{f},"]
        if loop:
            lines.append("            distanceMin = 2,")
        lines += [f"            distanceMax = {distance_max},", "        }"]
    lines.append("    }")
    return "\n".join(lines)


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, "*.ogg")) + glob.glob(os.path.join(OUT, "*.wav")):
        os.remove(old)

    blocks = []
    write_ogg(os.path.join(OUT, "Ignite.ogg"), ignite())
    blocks.append(sound_block("PhotonSwordIgnite", ["Ignite.ogg"], 20))
    write_ogg(os.path.join(OUT, "Extinguish.ogg"), extinguish())
    blocks.append(sound_block("PhotonSwordExtinguish", ["Extinguish.ogg"], 20))
    for tone_name, tone in TONES.items():
        # The loop stays WAV: Vorbis encoder padding can leave a click at the loop point.
        hum_file = f"Hum_{tone_name}.wav"
        write_wav(os.path.join(OUT, hum_file), hum(tone))
        blocks.append(sound_block(f"PhotonSwordHum_{tone_name}", [hum_file], 12, loop=True))
        for pitch in PITCHES:
            files = []
            for i, (seconds, variation) in enumerate(SWINGS, 1):
                files.append(f"Swing{i}_{tone_name}_{pitch}.ogg")
                write_ogg(os.path.join(OUT, files[-1]), swing(seconds, variation, tone, pitch / 100))
            blocks.append(sound_block(f"PhotonSwordSwing_{tone_name}_{pitch}", files, 20))
            files = []
            for i, (seconds, variation) in enumerate(HITS, 1):
                files.append(f"Hit{i}_{tone_name}_{pitch}.ogg")
                write_ogg(os.path.join(OUT, files[-1]), hit(seconds, variation, tone, pitch / 100))
            blocks.append(sound_block(f"PhotonSwordHit_{tone_name}_{pitch}", files, 25))

    with open(SCRIPT, "w") as f:
        f.write("module Base\n{\n")
        f.write("    /* Generated by tools/gen_sounds.py; edit that and re-run instead of editing this file. */\n\n")
        f.write("\n\n".join(blocks))
        f.write("\n}\n")
    count = len(glob.glob(os.path.join(OUT, "*")))
    print(f"Wrote {count} audio files to {os.path.normpath(OUT)} and {len(blocks)} sounds to {os.path.normpath(SCRIPT)}")


if __name__ == "__main__":
    main()
