#!/usr/bin/env python3
# Render ios/TidexApp/Resources/tidex_notification.caf, the sound used by local
# reminders and remote pushes. Run on a Mac: python3 scripts/generate-notification-sound.py
#
# Two layers start together. A C major bell chord swells in, and plucked notes
# a step above it (D6, A6) play over it, then settle on G6. Every note is in the
# C major pentatonic scale, so the layers blend into a C6/9 chord instead of
# clashing. Each pluck starts with a short upward pitch glide, like a water drop.
# A short echo adds room.
import math, os, struct, subprocess, tempfile, wave

SR = 48000
LENGTH = 1.3  # seconds

# Bell chord: (frequency Hz, gain). Soft FM bell timbre, slow swell, long ring.
BELL = [(261.63, 0.35), (523.25, 0.6), (783.99, 0.5), (1318.51, 0.3)]
BELL_START, BELL_SWELL, BELL_DECAY = 0.0, 0.09, 0.38  # seconds
BELL_MOD_RATIO, BELL_MOD_INDEX = 2.0, 0.7  # harmonic modulator keeps the bell in tune; index decays with the note

# Plucks: (start seconds, frequency Hz, gain, decay seconds)
PLUCKS = [(0.05, 1174.66, 0.8, 0.14), (0.14, 1760.00, 0.75, 0.16), (0.23, 1567.98, 0.7, 0.4)]
# Mallet partials: (frequency ratio, gain, decay multiplier)
PARTIALS = [(1.0, 1.0, 1.0), (2.0, 0.15, 0.5), (4.1, 0.06, 0.15)]
GLIDE = 0.02  # seconds to slide up from 88% pitch

# Level of each layer before the mix is normalized.
BELL_GAIN, PLUCK_GAIN = 0.8, 1.0
ECHO_DELAY, ECHO_GAIN = 0.075, 0.2

out = [0.0] * int(SR * LENGTH)

first = int(BELL_START * SR)
for freq, gain in BELL:
    for i in range(len(out) - first):
        t = i / SR
        env = min(1.0, t / BELL_SWELL) ** 2 * math.exp(-max(0.0, t - BELL_SWELL) / BELL_DECAY)
        index = BELL_MOD_INDEX * math.exp(-t / 0.15)
        mod = index * math.sin(2 * math.pi * freq * BELL_MOD_RATIO * t)
        out[first + i] += BELL_GAIN * gain * env * math.sin(2 * math.pi * freq * t + mod)

for start, freq, gain, decay in PLUCKS:
    first = int(start * SR)
    for ratio, pgain, pdecay in PARTIALS:
        phase = 0.0
        for i in range(len(out) - first):
            t = i / SR
            glide = 1 - 0.12 * max(0.0, 1 - t / GLIDE) ** 2
            phase += 2 * math.pi * freq * ratio * glide / SR
            attack = min(1.0, t / 0.003)
            env = attack * math.exp(-t / (decay * pdecay))
            out[first + i] += PLUCK_GAIN * gain * pgain * env * math.sin(phase)

delay = int(ECHO_DELAY * SR)
for i in range(len(out) - 1, delay - 1, -1):
    out[i] += ECHO_GAIN * out[i - delay]

fade = int(0.2 * SR)
for i in range(fade):
    out[-1 - i] *= i / fade

peak = max(map(abs, out))
scale = 0.89 / peak  # -1 dBFS
samples = [round(x * scale * 32767) for x in out]
assert max(map(abs, samples)) < 32767 and samples[0] == samples[-1] == 0

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
target = os.path.join(root, "ios/TidexApp/Resources/tidex_notification.caf")
with tempfile.TemporaryDirectory() as tmp:
    wav_path = os.path.join(tmp, "notification.wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@48000", wav_path, target], check=True)
print(f"wrote {target}")
