// Synthesizes the showcase music bed and UI sound effects, so no third-party audio is involved.
// Run from video/: node scripts/make-audio.mjs  (writes public/audio/*.wav)
import { mkdirSync, writeFileSync } from 'node:fs';

const SR = 48000;
const BEAT = 0.5; // 120 BPM, matching the 15-frame beat grid in src/timing.ts
const BAR = 4 * BEAT;
const STEP = BEAT / 4; // 16th note
const BARS = 14;
const OUT = new URL('../public/audio/', import.meta.url);
mkdirSync(OUT, { recursive: true });

// Deterministic noise so every run produces identical files.
let seed = 0x7d3a;
const noise = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 2147483648 - 1;
};
const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);
const track = (seconds) => [new Float32Array(Math.ceil(seconds * SR)), new Float32Array(Math.ceil(seconds * SR))];

// RBJ biquad, recomputable per sample for sweeps.
function biquad(type, freq, q) {
  let b0, b1, b2, a1, a2, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  const set = (f) => {
    const w = (2 * Math.PI * Math.min(f, SR * 0.45)) / SR, alpha = Math.sin(w) / (2 * q), c = Math.cos(w);
    const a0 = 1 + alpha;
    if (type === 'lp') [b0, b1, b2] = [(1 - c) / 2, 1 - c, (1 - c) / 2];
    if (type === 'hp') [b0, b1, b2] = [(1 + c) / 2, -(1 + c), (1 + c) / 2];
    if (type === 'bp') [b0, b1, b2] = [alpha, 0, -alpha];
    [b0, b1, b2, a1, a2] = [b0 / a0, b1 / a0, b2 / a0, (-2 * c) / a0, (1 - alpha) / a0];
  };
  set(freq);
  const run = (x) => {
    const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    [x2, x1, y2, y1] = [x1, x, y1, y];
    return y;
  };
  run.set = set;
  return run;
}

// Renders `fn(t)` (mono sample at local time t) into a stereo track with constant-power panning.
function place(buf, start, seconds, pan, fn) {
  const l = Math.cos(((pan + 1) * Math.PI) / 4), r = Math.sin(((pan + 1) * Math.PI) / 4);
  const i0 = Math.round(start * SR), n = Math.round(seconds * SR);
  for (let i = 0; i < n && i0 + i < buf[0].length; i++) {
    if (i0 + i < 0) continue;
    const v = fn(i / SR);
    buf[0][i0 + i] += v * l;
    buf[1][i0 + i] += v * r;
  }
}
const attack = (t, a) => Math.min(1, t / a);

// Instruments ---------------------------------------------------------------
function kick(buf, at, vel = 1) {
  let phase = 0;
  place(buf, at, 0.42, 0, (t) => {
    phase += (2 * Math.PI * (46 + 110 * Math.exp(-t / 0.028))) / SR;
    return vel * (0.9 * Math.sin(phase) * Math.exp(-t / 0.14) * attack(t, 0.001) + 0.12 * noise() * Math.exp(-t / 0.0015));
  });
}
function clap(buf, at, vel = 1, pan = 0) {
  const bp = biquad('bp', 1400, 0.8);
  place(buf, at, 0.35, pan, (t) => {
    const bursts = [0, 0.011, 0.022].reduce((s, o) => s + (t >= o ? Math.exp(-(t - o) / 0.005) : 0), 0);
    const tail = t >= 0.022 ? Math.exp(-(t - 0.022) / 0.085) : 0;
    return vel * 2.2 * bp(noise() * (0.8 * bursts + 0.55 * tail));
  });
}
function hat(buf, at, vel = 1, open = false, pan = 0, cutoff = 7500) {
  const hp = biquad('hp', cutoff, 0.7);
  place(buf, at, open ? 0.3 : 0.08, pan, (t) => vel * 0.5 * hp(noise()) * Math.exp(-t / (open ? 0.085 : 0.02)) * attack(t, 0.0007));
}
function bass(buf, at, midi, seconds, vel = 1, decay = Infinity) {
  const f = hz(midi);
  place(buf, at, seconds + 0.06, 0, (t) => {
    const env = attack(t, 0.006) * Math.exp(-t / decay) * (t > seconds ? Math.max(0, 1 - (t - seconds) / 0.05) : 1);
    return vel * 0.55 * Math.tanh(1.6 * (Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(4 * Math.PI * f * t))) * env;
  });
}
// Marimba-like mallet: fundamental plus the characteristic ~4x partial, both decaying fast.
function mallet(buf, at, midi, vel = 1, pan = 0, decay = 0.38) {
  const f = hz(midi);
  place(buf, at, decay * 5, pan, (t) => {
    const a = attack(t, 0.0015);
    return vel * a * (0.5 * Math.sin(2 * Math.PI * f * t) * Math.exp(-t / decay)
      + 0.2 * Math.sin(2 * Math.PI * 3.93 * f * t) * Math.exp(-t / 0.045)
      + 0.06 * Math.sin(2 * Math.PI * 9.1 * f * t) * Math.exp(-t / 0.012));
  });
}
function pad(buf, at, midis, seconds, vel = 1) {
  const voices = midis.flatMap((m) => [hz(m) * 0.9985, hz(m) * 1.0015]);
  place(buf, at, seconds + 0.8, 0, (t) => {
    const env = Math.min(1, t / 0.35) * (t > seconds ? Math.max(0, 1 - (t - seconds) / 0.8) : 1);
    const trem = 1 + 0.06 * Math.sin(2 * Math.PI * 4.2 * t);
    return (vel * 0.05 * env * trem * voices.reduce((s, f, i) => s + Math.sin(2 * Math.PI * f * t + i), 0)) / Math.sqrt(voices.length);
  });
}
// FM bell: inharmonic modulator ratio with a decaying index.
function bell(buf, at, midi, vel = 1, pan = 0, length = 1.6) {
  const f = hz(midi);
  place(buf, at, length, pan, (t) => {
    const index = 3.2 * Math.exp(-t / 0.35);
    return vel * 0.32 * attack(t, 0.002) * Math.exp(-t / (length / 3.2)) * Math.sin(2 * Math.PI * f * t + index * Math.sin(2 * Math.PI * f * 3.5 * t));
  });
}
function sweep(buf, at, seconds, from, to, vel = 1, shape = (x) => x * x, panFrom = 0, panTo = 0) {
  const bp = biquad('bp', from, 1.2);
  const i0 = Math.round(at * SR), n = Math.round(seconds * SR);
  for (let i = 0; i < n && i0 + i < buf[0].length; i++) {
    const x = i / n;
    bp.set(from * (to / from) ** x);
    const v = vel * 1.6 * bp(noise()) * shape(x);
    const pan = panFrom + (panTo - panFrom) * x;
    buf[0][i0 + i] += v * Math.cos(((pan + 1) * Math.PI) / 4);
    buf[1][i0 + i] += v * Math.sin(((pan + 1) * Math.PI) / 4);
  }
}

// Small stereo reverb (Freeverb-style comb + allpass network) for glue.
function reverb(buf, mix, room = 0.8, damp = 0.35) {
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  const alls = [556, 441, 341, 225];
  return buf.map((ch, c) => {
    const out = new Float32Array(ch.length);
    const cs = combs.map((d) => ({ b: new Float32Array(d + c * 23), i: 0, s: 0 }));
    const as = alls.map((d) => ({ b: new Float32Array(d + c * 23), i: 0 }));
    for (let n = 0; n < ch.length; n++) {
      let y = 0;
      for (const cb of cs) {
        const o = cb.b[cb.i];
        cb.s = o * (1 - damp) + cb.s * damp;
        cb.b[cb.i] = ch[n] * 0.015 + cb.s * room;
        cb.i = (cb.i + 1) % cb.b.length;
        y += o;
      }
      for (const ap of as) {
        const o = ap.b[ap.i];
        ap.b[ap.i] = y + o * 0.5;
        ap.i = (ap.i + 1) % ap.b.length;
        y = o - y;
      }
      out[n] = ch[n] + y * mix;
    }
    return out;
  });
}

function mix(target, source, gain = 1, duck) {
  for (let c = 0; c < 2; c++) for (let i = 0; i < target[c].length; i++) target[c][i] += source[c][i] * gain * (duck ? duck[i] : 1);
}

function writeWav(name, [l, r], peak = 0.89) {
  let max = 1e-9;
  for (let i = 0; i < l.length; i++) max = Math.max(max, Math.abs(l[i]), Math.abs(r[i]));
  const gain = peak / max;
  const data = Buffer.alloc(l.length * 4);
  for (let i = 0; i < l.length; i++) {
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, l[i] * gain)) * 32767), i * 4);
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, r[i] * gain)) * 32767), i * 4 + 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(36 + data.length, 4); header.write('WAVE', 8);
  header.write('fmt ', 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
  header.writeUInt32LE(SR, 24); header.writeUInt32LE(SR * 4, 28); header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(data.length, 40);
  writeFileSync(new URL(name, OUT), Buffer.concat([header, data]));
  console.log(`wrote public/audio/${name} (${(l.length / SR).toFixed(2)}s)`);
}

// Music bed: 14 bars, I-V-vi-IV in C. Bars 0-1 are the social hook, 2-11 the features, 12-13 the outro.
const chords = [
  { bass: 36, pad: [55, 60, 64], arp: [72, 76, 79, 84] }, // C
  { bass: 43, pad: [55, 59, 62], arp: [71, 74, 79, 83] }, // G
  { bass: 45, pad: [57, 60, 64], arp: [72, 76, 81, 84] }, // Am
  { bass: 41, pad: [57, 60, 65], arp: [72, 77, 81, 84] }, // F
];
const seconds = BARS * BAR + 1.5;
const drums = track(seconds), low = track(seconds), keys = track(seconds), fx = track(seconds);
const tresillo = [0, 3, 6, 8, 11, 14]; // 3+3+2 feel on the 16th grid
const melodic = [0, 1, 2, 1, 3, 2];
const kicks = [];
// Hi-hat rolls do the printing: under the hook's payslip, and under the payroll receipt, whose last row lands
// on the bar 6 downbeat (RECEIPT_AT in src/config.ts). Each roll speeds up from 16ths to 64ths.
const ROLLS = [
  { start: 2.0, parts: [[2.5, STEP / 2], [2.75, STEP / 3]], vel: [0.18, 0.45] },
  { start: 10.25, parts: [[11.0, STEP], [11.5, STEP / 2], [11.75, STEP / 3], [12.0, STEP / 4]], vel: [0.2, 0.55] },
];
// The regular hats drop out while a roll plays.
const inRoll = (t) => ROLLS.some(({ start, parts }) => t > start - 1e-6 && t < parts.at(-1)[0] - 1e-6);

for (let bar = 0; bar < BARS; bar++) {
  const t0 = bar * BAR, ch = chords[bar % 4];
  const groove = bar >= 2 && bar <= 11;
  const outro = bar >= 12;
  // Clock ticks under the hook, a nod to the ruler in the logo.
  if (bar < 2) for (let s = 0; s < 8; s++) {
    const at = t0 + (s * BEAT) / 2;
    if (!inRoll(at)) hat(drums, at, s % 2 ? 0.28 : 0.45, false, s % 2 ? 0.3 : -0.3);
  }
  if (bar === 1) for (const b of [0, 2]) { kick(drums, t0 + b * BEAT, 0.7); kicks.push(t0 + b * BEAT); }
  if (groove) {
    for (let b = 0; b < 4; b++) { kick(drums, t0 + b * BEAT, b === 0 ? 1 : 0.9); kicks.push(t0 + b * BEAT); }
    for (const b of [1, 3]) clap(drums, t0 + b * BEAT, 0.55, 0.1);
    for (let s = 0; s < 16; s++) {
      const at = t0 + s * STEP + (s % 2 ? 0.006 : 0);
      if (!inRoll(at)) hat(drums, at, s % 4 === 2 ? 0.34 : s % 2 ? 0.14 : 0.22, s % 4 === 2, s % 2 ? 0.35 : -0.25);
    }
    for (const s of [2, 6, 10, 14]) bass(low, t0 + s * STEP, ch.bass, STEP * 1.6, s === 14 ? 0.75 : 0.9);
    // Snare-roll lift into the outro.
    if (bar === 11) for (let s = 12; s < 16; s++) clap(drums, t0 + s * STEP, 0.25 + (s - 12) * 0.1, -0.2);
  }
  if (bar === 12) { kick(drums, t0, 1); kicks.push(t0); bass(low, t0, 36, 1.6, 0.8, 0.45); }
  // Mallet tresillo; filtered-sounding (short, soft) during the hook.
  if (bar < 13) tresillo.forEach((s, i) => {
    const midi = ch.arp[melodic[i]] - (bar < 2 ? 12 : 0);
    mallet(keys, t0 + s * STEP, midi, (bar < 2 ? 0.45 : 0.62) * (i === 0 ? 1.1 : 0.95), (i % 2 ? 0.35 : -0.35), bar < 2 ? 0.22 : 0.38);
  });
  if (bar >= 2 && !outro) pad(keys, t0, ch.pad, BAR - 0.05, 0.9);
  if (outro) pad(keys, t0, bar === 12 ? [60, 64, 67, 72] : [60, 67, 72, 76], bar === 13 ? BAR * 0.8 : BAR - 0.05, 1.1);
}
for (const { start, parts, vel } of ROLLS) {
  const hits = [];
  let t = start;
  for (const [until, step] of parts) for (; t < until - 1e-6; t += step) hits.push(t);
  hits.forEach((at, i) => {
    const x = i / (hits.length - 1);
    hat(drums, at, vel[0] + (vel[1] - vel[0]) * x, false, -0.35 + 0.7 * x, 6500 + 3000 * x);
  });
}
// Riser into the first groove bar, and into the outro reveal.
sweep(fx, 1 * BAR + 0.4, BAR - 0.4, 500, 7000, 0.26, (x) => x ** 2.4, -0.4, 0.4);
sweep(fx, 11 * BAR + 1.0, 1.0, 700, 8000, 0.2, (x) => x ** 2.2);
// Logo chime (hook bar 1, beat 3) and the outro chord bells.
for (const [m, d, p] of [[84, 0, -0.2], [91, 0.06, 0.2], [88, 0.12, 0]]) bell(fx, 1 * BAR + 2 * BEAT + d, m, 0.55, p, 1.8);
for (const [m, d, p] of [[72, 0, -0.3], [79, 0.05, 0.3], [84, 0.1, 0], [88, 0.16, 0.15]]) bell(fx, 12 * BAR + d, m, 0.6, p, 2.6);
bell(fx, 13 * BAR, 96, 0.3, 0.2, 2.0);

// Sidechain-style ducking on bass and keys from the kick.
const duck = new Float32Array(drums[0].length).fill(1);
for (const k of kicks) for (let i = 0; i < 0.22 * SR; i++) {
  const n = Math.round(k * SR) + i;
  if (n < duck.length) duck[n] = Math.min(duck[n], 1 - 0.55 * Math.exp(-i / SR / 0.07));
}
const music = track(seconds);
mix(music, drums, 0.9);
mix(music, low, 0.8, duck);
mix(music, reverb(keys, 0.32), 0.75, duck);
mix(music, reverb(fx, 0.45), 0.8);
// Fade the tail so the file ends at 28 s.
const end = BARS * BAR;
for (let c = 0; c < 2; c++) for (let i = 0; i < music[c].length; i++) {
  const t = i / SR;
  music[c][i] = Math.tanh(1.1 * music[c][i]) * (t < end - 1.2 ? 1 : Math.max(0, (end - t) / 1.2));
}
writeWav('music.wav', music.map((ch) => ch.subarray(0, Math.round(end * SR))), 0.8);

// Sound effects: kept soft so they sit under the music.
const sfx = (name, secs, draw, peak = 0.7) => { const b = track(secs); draw(b); writeWav(name, reverb(b, 0.18), peak); };
sfx('whoosh.wav', 0.45, (b) => sweep(b, 0, 0.38, 380, 1600, 1, (x) => Math.sin(Math.PI * x) ** 2, -0.4, 0.4));
// A short wooden tock rather than a bubble pop.
sfx('pop.wav', 0.16, (b) => {
  let phase = 0;
  place(b, 0, 0.12, 0, (t) => {
    phase += (2 * Math.PI * (520 + 140 * Math.exp(-t / 0.012))) / SR;
    return Math.sin(phase) * Math.exp(-t / 0.028) * attack(t, 0.002);
  });
});
sfx('tick.wav', 0.06, (b) => {
  const bp = biquad('bp', 3800, 2.5);
  place(b, 0, 0.05, 0, (t) => 3 * bp(noise()) * Math.exp(-t / 0.004));
});
sfx('tap.wav', 0.12, (b) => {
  place(b, 0, 0.1, 0, (t) => attack(t, 0.0008) * (0.6 * Math.sin(2 * Math.PI * (1500 - 500 * t / 0.1) * t) * Math.exp(-t / 0.012)
    + 0.5 * Math.sin(2 * Math.PI * 180 * t) * Math.exp(-t / 0.02)));
});
sfx('sparkle.wav', 0.8, (b) => [96, 100, 103].forEach((m, i) => bell(b, i * 0.06, m, 0.2 - i * 0.04, i % 2 ? 0.4 : -0.4, 0.5)));
