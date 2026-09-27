# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["skia-python", "numpy"]
# ///
"""Tidex 15-second vertical showreel, drawn frame by frame with Skia.

    uv run video/reel/reel.py                  # renders video/out/Tidex-Reel.mp4
    uv run video/reel/reel.py --still 1.5 6.2  # writes video/out/reel/still-*.png and contact.png
    uv run video/reel/reel.py --audio          # writes video/out/reel/audio.wav only
    uv run video/reel/reel.py --check          # runs the self-checks

The glass icon on the end card comes from video/reel/icon3d.py (Blender). Without
its frames the reel falls back to the flat app icon.
"""
import json
import math
import os
import re
import subprocess
import sys
import urllib.request
import wave
import xml.etree.ElementTree as ET
from functools import cache, lru_cache
from multiprocessing import Pool
from pathlib import Path

import numpy as np
import skia

TL = skia.textlayout
ROOT = Path(__file__).resolve().parents[2]
PUB, OUT = ROOT / 'video/public', ROOT / 'video/out'
WORK = OUT / 'reel'
ICON_FRAMES = WORK / 'icon'
W, H, FPS, DUR, SR = 1080, 1920, 60, 15.0, 48000
NF = round(FPS * DUR)
RGBA = skia.ColorType.kRGBA_8888_ColorType
SAMPLING = skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear)
STROKE = dict(Style=skia.Paint.kStroke_Style, StrokeCap=skia.Paint.kRound_Cap)


def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


INK, NIGHT, RAISED = hexc('020817'), hexc('16243a'), hexc('1b2c45')
MIST, TEXT, SOFT, MUTED = hexc('f5f8fc'), hexc('f2f7fc'), hexc('c6d7e6'), hexc('9db4c8')
PAPER_INK, PAPER_MUTED, PAPER_RED = hexc('031425'), hexc('5b6b80'), hexc('c81e1e')
BLUE, ICON_BLUE = hexc('4c86ea'), hexc('2563eb')
APP_BG, CARD, BADGE, TAX_RED = (4, 9, 17), (18, 27, 40), (34, 97, 232), (237, 66, 67)
BODY, RIM, SIDE = (11, 15, 22), (59, 70, 86), (31, 39, 51)
WHITE, BLACK = (255, 255, 255), (0, 0, 0)


# Timing -----------------------------------------------------------------------

def clamp(x, a=0.0, b=1.0): return a if x < a else b if x > b else x
def lerp(a, b, x): return a + (b - a) * x
def mix(c0, c1, x): return tuple(lerp(a, b, x) for a, b in zip(c0, c1))
def prog(t, t0, t1): return clamp((t - t0) / (t1 - t0))
def lin(x): return x
def out3(x): return 1 - (1 - x) ** 3
def out4(x): return 1 - (1 - x) ** 4
def in3(x): return x ** 3
def io(x, n): return 0.5 * (2 * x) ** n if x < 0.5 else 1 - 0.5 * (2 - 2 * x) ** n
def io3(x): return io(x, 3)
def back(x, s=1.7): return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2


def spring(tau, z=0.42, w=20.0):
    """Unit step response of a damped spring, 0 before tau reaches 0."""
    if tau <= 0: return 0.0
    wd = w * math.sqrt(1 - z * z)
    return 1 - math.exp(-z * w * tau) * (math.cos(wd * tau) + z * w / wd * math.sin(wd * tau))


def kf(t, *keys):
    """Keyframes (time, value[, ease]); a key's ease shapes the segment that ends on it."""
    if t <= keys[0][0]: return keys[0][1]
    for (t0, v0, *_), (t1, v1, *e) in zip(keys, keys[1:]):
        if t < t1:
            x = (e[0] if e else io3)((t - t0) / (t1 - t0))
            return tuple(lerp(a, b, x) for a, b in zip(v0, v1)) if isinstance(v0, tuple) else lerp(v0, v1, x)
    return keys[-1][1]


def when(f, y, t0, t1):
    """First time in [t0, t1] where the rising function f reaches y."""
    for _ in range(40):
        tm = (t0 + t1) / 2
        t0, t1 = (tm, t1) if f(tm) < y else (t0, tm)
    return t1


# Drawing helpers --------------------------------------------------------------

def argb(c, a=1.0): return skia.ColorSetARGB(round(255 * clamp(a)), *(round(clamp(v, 0, 255)) for v in c))
def paint(c=WHITE, a=1.0, **kw): return skia.Paint(Color=argb(c, a), AntiAlias=True, **kw)
def rect(l, t, r, b): return skia.Rect.MakeLTRB(l, t, r, b)
def rrect(l, t, r, b, rad): return skia.RRect.MakeRectXY(rect(l, t, r, b), rad, rad)
def img(cv, im, a=1.0, x=0.0, y=0.0): cv.drawImage(im, x, y, SAMPLING, paint(WHITE, a))


def radial(x, y, r, c, a):
    return skia.Paint(Shader=skia.GradientShader.MakeRadial(skia.Point(x, y), r, [argb(c, a), argb(c, a * 0.4), argb(c, 0)], [0, 0.4, 1]))


def zoom_about(cv, s, x, y):
    cv.translate(x, y)
    cv.scale(s, s)
    cv.translate(-x, -y)


NUM = re.compile(r'[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def svg_path(d):
    """Parses the M, L, H, V, Q, C and Z commands the wordmark uses."""
    p, tok, i = skia.Path(), NUM.findall(d), 0
    x = y = x0 = y0 = 0.0
    cmd = 'M'

    def n():
        nonlocal i
        i += 1
        return float(tok[i - 1])

    while i < len(tok):
        if tok[i].isalpha():
            cmd, i = tok[i], i + 1
        rel, c = cmd.islower(), cmd.upper()
        dx, dy = (x, y) if rel else (0.0, 0.0)
        if c == 'M':
            x, y = dx + n(), dy + n()
            p.moveTo(x, y)
            x0, y0, cmd = x, y, 'l' if rel else 'L'
        elif c == 'L':
            x, y = dx + n(), dy + n()
            p.lineTo(x, y)
        elif c == 'H':
            x = dx + n()
            p.lineTo(x, y)
        elif c == 'V':
            y = dy + n()
            p.lineTo(x, y)
        elif c == 'Q':
            x1, y1 = dx + n(), dy + n()
            x, y = dx + n(), dy + n()
            p.quadTo(x1, y1, x, y)
        elif c == 'C':
            x1, y1, x2, y2 = dx + n(), dy + n(), dx + n(), dy + n()
            x, y = dx + n(), dy + n()
            p.cubicTo(x1, y1, x2, y2, x, y)
        elif c == 'Z':
            p.close()
            x, y = x0, y0
        else:
            raise ValueError(f'unsupported path command {cmd}')
    return p


def wordmark():
    """One path per letter of the wordmark, in SVG units."""
    ns = '{http://www.w3.org/2000/svg}'
    g = ET.parse(ROOT / 'marketing/public/brand/tidex-wordmark.svg').getroot().find(ns + 'g')

    def shift(el): return [float(v) for v in re.findall(r'[-\d.]+', el.get('transform', 'translate(0 0)'))][:2]

    gx, gy = shift(g)
    letters = []
    for el in g:
        dx, dy = shift(el)
        if el.tag == ns + 'g':
            p = skia.Path()
            for r in el:
                x, y, w, h, rx = (float(r.get(k, 0)) for k in ('x', 'y', 'width', 'height', 'rx'))
                p.addRRect(rrect(x, y, x + w, y + h, rx))
        else:
            p = svg_path(el.get('d'))
            if el.get('fill-rule') == 'evenodd': p.setFillType(skia.PathFillType.kEvenOdd)
        p.offset(gx + dx, gy + dy)
        letters.append(p)
    return letters


# Type -------------------------------------------------------------------------

FONTS = {
    'manrope': 'https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf',
    'mono': 'https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf',
}


@cache
def typeface(name):
    f = WORK / 'fonts' / f'{name}.ttf'
    if not f.exists():
        f.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(FONTS[name], f)
    return skia.Typeface.MakeFromFile(str(f))


@cache
def face(name, wght):
    vp = skia.FontArguments.VariationPosition
    coords = vp.Coordinates([vp.Coordinate(0x77676874, wght)])  # 'wght'; the clone reads these, so keep them alive
    pos = vp(coords)
    args = skia.FontArguments()
    args.setVariationDesignPosition(pos)
    return typeface(name).makeClone(args)


@cache
def font(name, wght):
    """A size-100 font at one variable weight; text() scales it on the canvas."""
    f = skia.Font(face(name, wght), 100)
    f.setSubpixel(True)
    f.setLinearMetrics(True)
    f.setHinting(skia.FontHinting.kNone)
    f.setEdging(skia.Font.Edging.kAntiAlias)
    return f


def q10(w): return int(round(w / 10) * 10)


@cache
def layout(s, name, wght):
    """Kerned pen offsets of each character at size 100, plus the whole advance."""
    prov = TL.TypefaceFontProvider()
    prov.registerTypeface(face(name, wght), 'F')
    fc = TL.FontCollection()
    fc.setDefaultFontManager(prov)
    style = TL.TextStyle()
    style.setFontFamilies(['F'])
    style.setFontSize(100)
    ps = TL.ParagraphStyle()
    ps.setTextStyle(style)

    def width(sub):
        b = TL.ParagraphBuilder(ps, fc, skia.Unicodes.ICU.Make())
        b.pushStyle(style)
        b.addText(sub)
        para = b.Build()
        para.layout(1e6)
        return para.LongestLine

    f = font(name, wght)
    adv = f.getWidths(f.textToGlyphs(s))
    return tuple(width(s[:i + 1]) - adv[i] for i in range(len(s))), width(s)


def tw(s, size, wght=700, name='manrope', track=0.0):
    if not s: return 0.0
    return (layout(s, name, q10(wght))[1] + track * 100 * (len(s) - 1)) * size / 100


def text(cv, s, x, y, size, c=TEXT, a=1.0, wght=700, name='manrope', align=0.0, track=0.0):
    """Kerned text with its baseline at y; align 0 is left, 0.5 centre, 1 right. Returns the advance."""
    if not s: return 0.0
    wq = q10(wght)
    xs, _ = layout(s, name, wq)
    total = tw(s, size, wq, name, track)
    if a > 0.003:
        blob = skia.TextBlob.MakeFromPosTextH(s, [p + track * 100 * i for i, p in enumerate(xs)], 0, font(name, wq))
        cv.save()
        cv.translate(x - align * total, y)
        cv.scale(size / 100, size / 100)
        cv.drawTextBlob(blob, 0, 0, paint(c, a))
        cv.restore()
    return total


@cache
def ink(s, wght):
    """Tight ink box of s at size 100, relative to its pen origin."""
    arr = np.zeros((200, int(tw(s, 100, wght)) + 60, 4), np.uint8)
    surf = skia.Surface(arr)
    text(surf.getCanvas(), s, 30, 140, 100, WHITE, 1.0, wght)
    ys, xs = np.nonzero(arr[..., 3] > 60)
    return xs.min() - 30.0, ys.min() - 140.0, xs.max() + 1 - 30.0, ys.max() + 1 - 140.0


def odo_pos(v, j):
    """Position of the 10^j odometer wheel for value v; it only turns while the lower wheels roll over."""
    if j == 0: return v
    p = 10 ** j
    return math.floor(v / p) + max(0.0, v % p - (p - 1))


def wheel(cv, pos, cx, y, size, c, a, wght):
    """One digit wheel: floor(pos) scrolling up as the next digit arrives from below."""
    d = math.floor(pos)
    fr, lh = pos - d, size * 1.02
    for digit, dy in ((d % 10, -fr * lh), ((d + 1) % 10, (1 - fr) * lh)):
        if abs(dy) < lh * 0.999: text(cv, str(digit), cx, y + dy, size, c, a, wght, align=0.5)


def counter(cv, v, x, y, size, a, unit, usize):
    """Odometer number and its unit, centred on x while the number grows digits."""
    cw = 0.6 * size  # a middle digit width; Manrope's figures are proportional
    nd = 1 + clamp(v - 9) + clamp(v - 99)
    gap = 0.24 * usize
    x0 = x - (nd * cw + gap + tw(unit, usize, 600)) / 2
    cv.save()
    cv.clipRect(rect(x0 - 30, y - size * 0.84, x0 + nd * cw + 30, y + size * 0.1), skia.ClipOp.kIntersect, True)
    for j in range(3):
        aj = a * (1.0 if j == 0 else clamp(v - (10 ** j - 1)))
        if aj > 0: wheel(cv, odo_pos(v, j), x0 + (nd - j - 0.5) * cw, y, size, TEXT, aj, 800)
    cv.restore()
    text(cv, unit, x0 + nd * cw + gap, y, usize, MUTED, a, 600)


def slot(cv, s, x, y, size, c, a, t, t0, wght=700, align=1.0, spins=2):
    """Text whose digits spin down into place from t0, left to right."""
    wq = q10(wght)
    xs, w = layout(s, 'manrope', wq)
    k = size / 100
    x0 = x - align * w * k
    ndig = sum(ch.isdigit() for ch in s)
    if t >= t0 + 0.4 + 0.03 * ndig or a <= 0.003: return text(cv, s, x0, y, size, c, a, wq)
    rest = [(ch, p) for ch, p in zip(s, xs) if not ch.isdigit()]
    if rest:
        blob = skia.TextBlob.MakeFromPosTextH(''.join(ch for ch, _ in rest), [p for _, p in rest], 0, font('manrope', wq))
        cv.save()
        cv.translate(x0, y)
        cv.scale(k, k)
        cv.drawTextBlob(blob, 0, 0, paint(c, a))
        cv.restore()
    ends = list(xs[1:]) + [w]
    cv.save()
    cv.clipRect(rect(x0 - 10, y - size * 0.84, x0 + w * k + 10, y + size * 0.12), skia.ClipOp.kIntersect, True)
    j = 0
    for i, ch in enumerate(s):
        if ch.isdigit():
            pos = int(ch) + 10 * spins * (1 - out4(prog(t, t0 + 0.03 * j, t0 + 0.03 * j + 0.4)))
            wheel(cv, pos, x0 + (xs[i] + ends[i]) / 2 * k, y, size, c, a, wq)
            j += 1
    cv.restore()
    return w * k


def caption_words(src):
    """Caption lines as (plain text, [(word, start index, highlighted)]); braces mark the blue words."""
    lines = []
    for line in src.split('\n'):
        plain, words, hl = '', [], False
        for tok in re.findall(r'[{}]|[^{}\s]+|\s+', line):
            if tok in ('{', '}'):
                hl = tok == '{'
                continue
            if not tok.isspace(): words.append((tok, len(plain), hl))
            plain += tok
        lines.append((plain, words))
    return lines


def caption(cv, src, cy, t, t_in, t_out=None, size=84, wght=800, lead=1.12):
    """Words spring up through their line one by one, then lift out."""
    lines = caption_words(src)
    k, n = size / 100, 0
    for li, (plain, words) in enumerate(lines):
        base = cy + (li - (len(lines) - 1) / 2) * size * lead + size * 0.36
        xs, w = layout(plain, 'manrope', wght)
        x0 = W / 2 - w * k / 2
        cv.save()
        cv.clipRect(rect(0, base - size * 1.02, W, base + size * 0.3))
        for word, i0, hl in words:
            e_in = spring(t - t_in - 0.045 * n, 0.62, 15)
            e_out = in3(prog(t, t_out + 0.03 * n, t_out + 0.03 * n + 0.32)) if t_out else 0.0
            if e_in > 0.001 and e_out < 0.999:
                text(cv, word, x0 + xs[i0] * k, base + (1 - e_in) * size * 1.2 - e_out * size * 1.3, size, BLUE if hl else TEXT, 1.0, wght)
            n += 1
        cv.restore()


def rise_line(cv, t, s, y, size, c, a, wght, starts, tilt_last=0.0):
    """A centred line whose characters spring up through the baseline mask at their own start times."""
    wq = q10(wght)
    xs, w = layout(s, 'manrope', wq)
    k = size / 100
    x0 = -w * k / 2
    ends = list(xs[1:]) + [w]
    cv.save()
    cv.clipRect(rect(-2000, y - size * 1.05, 2000, y + size * 0.3))
    for i, ch in enumerate(s):
        e = spring(t - starts[i], 0.6, 17) if starts[i] is not None else 0.0
        if e <= 0.001: continue
        cv.save()
        cv.translate(x0 + xs[i] * k, y + (1 - e) * size * 1.1)
        if tilt_last and i == len(s) - 1:
            pivot = (ends[i] - xs[i]) * k / 2
            cv.translate(pivot, 0)
            cv.rotate(tilt_last)
            cv.translate(-pivot, 0)
        text(cv, ch, 0, 0, size, c, a, wq)
        cv.restore()
    cv.restore()


# Perspective ------------------------------------------------------------------

F = 2200.0
KM = np.array([[F, 0, W / 2], [0, F, H / 2], [0, 0, 1]])


def rot(yaw, pitch, roll=0.0):
    a, b, c = (math.radians(v) for v in (yaw, pitch, roll))
    ry = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    rx = np.array([[1, 0, 0], [0, math.cos(b), -math.sin(b)], [0, math.sin(b), math.cos(b)]])
    rz = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    return ry @ rx @ rz


def plane_origin(cx, cy, z=0.0):
    """Camera-space origin of a plane that is centred on screen point (cx, cy) at depth F + z."""
    d = F + z
    return np.array([(cx - W / 2) * d / F, (cy - H / 2) * d / F, d])


def homography(R, s, o):
    Hm = KM @ np.column_stack([s * R[:, 0], s * R[:, 1], o])
    return Hm / Hm[2, 2]


def mat(Hm): return skia.Matrix.MakeAll(*Hm[0], *Hm[1], *Hm[2])


def proj(Hm, x, y):
    v = Hm @ (x, y, 1.0)
    return v[0] / v[2], v[1] / v[2]


# Scene 1: a month of shifts on the ruler tape (0 to 2.45 s) ---------------------

P, BAND = 90.0, 270.0  # px per hour, tape height
SHIFT_DAYS = (1, 3, 5, 9, 10, 12, 15, 17, 19, 22, 24, 26, 28, 30)
SHIFTS = [((d - 1) * 24 + 9, (d - 1) * 24 + 17) for d in SHIFT_DAYS]
DOW = ('Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon')  # 1 September 2026 is a Tuesday
END = SHIFTS[-1][1]


def playhead(t):
    if t < 1.0: return 9 + 8 * out3(prog(t, 0.5, 0.95))
    return 17 + (END - 17) * io(prog(t, 1.0, 2.0), 4)


@lru_cache(maxsize=64)
def ruler_path(m=1.0, depth=1.0):
    """The logo's ruler at 1 hour = 90 px; m blends a square shift block into the round-capped pill."""
    r = 1.5 * P * m
    body = skia.Path()
    body.addRRect(rrect(-4.1667 * P - r, -1.5 * P, 4.1667 * P + r, 1.5 * P, r))
    if depth < 0.01: return body
    cuts, hw = skia.Path(), 0.1481 * P
    for h in range(9):
        cuts.addRRect(rrect((h - 4) * P - hw, -1.5 * P - 30, (h - 4) * P + hw, -1.5 * P + (1.037 if h % 4 == 0 else 0.444) * P * depth, hw))
    return skia.Op(body, cuts, skia.PathOp.kDifference_PathOp)


def tape(cv, t):
    p = playhead(t)
    c = max(13.0, p - 4) + (1.4 * math.exp(-(t - 1.96) / 0.09) * math.sin((t - 1.96) * 17) if t > 1.96 else 0.0)
    # the whip: the tape tips back into a runway whose vanishing point sits in the upper right, then swings flat again
    zoom = kf(t, (0, 1.22), (0.9, 1.0, out3), (1.0, 1.0), (1.5, 1.4), (2.05, 1.0))
    R = rot(*(kf(t, (1.0, 0.0), (1.5, v), (2.05, 0.0)) for v in (10.0, -75.0, -90.0)))
    fold = 1 - clamp((abs(playhead(t + 0.004) - playhead(t - 0.004)) / 0.008 - 40) / 300)  # notches fold flat at speed
    Hm = homography(R, zoom, plane_origin(W / 2, H / 2))
    fade = 1 - prog(t, 2.0, 2.4)
    bh = 4 + (BAND - 4) * spring(t - 0.1, 0.55, 16)
    top = -bh / 2
    half = min(200.0, 700 / (P * zoom) * (1 + 40 * abs(R[2, 0])))
    lo, hi = max(c - half, -30.0), min(c + half, 750.0)
    if t < 0.4:  # the band grows out from the centre
        reach = 6 * out3(prog(t, 0.0, 0.35))
        lo, hi = max(lo, 13 - reach), min(hi, 13 + reach)
    r20, r21 = R[2, 0] * zoom, abs(R[2, 1]) * zoom * 280
    if abs(r20) > 1e-6:  # keep everything in front of the camera
        lim = c + (300 - F + r21) / r20 / P
        lo, hi = (max(lo, lim), hi) if r20 > 0 else (lo, min(hi, lim))

    def X(h): return (h - c) * P

    cv.save()
    cv.concat(mat(Hm))
    la = out3(prog(t, 0.35, 0.6)) * fade
    if la > 0:
        for d in range(1, 31):
            h9 = (d - 1) * 24 + 9
            if not lo - 10 < h9 < hi + 1: continue
            on = d in SHIFT_DAYS
            text(cv, f'{DOW[(d - 1) % 7]} {d}', X(h9) - 15, top - 44, 30, TEXT if on else MUTED, la * (0.9 if on else 0.45), 500, 'mono')
            if on: text(cv, '8 h', X(h9 + 4), -top + 62, 30, MUTED, la, 500, 'mono', align=0.5)
    cuts = skia.Path()
    for h in range(math.ceil(lo), math.floor(hi) + 1):
        dep = (1.037 if (h - 1) % 4 == 0 else 0.444) * P * spring(t - 0.22 - min(abs(h - 13), 8) * 0.02, 0.5, 20) * fold
        if dep > 1: cuts.addRRect(rrect(X(h) - 13.33, top - 30, X(h) + 13.33, top + dep, 13.33))
    cv.save()
    cv.clipPath(cuts, skia.ClipOp.kDifference, True)
    cv.drawRect(rect(X(lo), top, X(hi), -top), paint(mix(BLUE, RAISED, prog(bh, 6, 90)), fade))
    for s0, s1 in SHIFTS:
        a0, a1 = s0 - 1 / 6, s1 + 1 / 6
        if a1 < lo or a0 > hi or (s1 == END and t >= 2.0): continue
        cv.drawRect(rect(X(max(a0, lo)), top, X(min(a1, hi)), -top), paint(WHITE, 0.1 * la))
        l_, r_ = max(a0, lo), min(a1 if p >= s1 else p, hi)
        if r_ > l_: cv.drawRect(rect(X(l_), top, X(r_), -top), paint(BLUE, 1.0 if s1 == END else fade))
    cv.restore()
    if t >= 2.0:
        m = io3(prog(t, 2.0, 2.45))
        cv.translate(X(END - 4), 0)
        cv.drawPath(ruler_path(m), paint(mix(BLUE, WHITE, m)))
    cv.restore()

    pa = out3(prog(t, 0.3, 0.5)) * fade
    if pa > 0:
        x1, y1 = proj(Hm, X(p), top - 70)
        x2, y2 = proj(Hm, X(p), -top + 70)
        cv.drawLine(x1, y1, x2, y2, paint(BLUE, 0.55 * pa, StrokeWidth=16, MaskFilter=skia.MaskFilter.MakeBlur(skia.BlurStyle.kNormal_BlurStyle, 14), **STROKE))
        cv.drawLine(x1, y1, x2, y2, paint(BLUE, pa, StrokeWidth=6, **STROKE))
        cv.drawCircle(x1, y1, 13, paint(BLUE, pa))
        cv.drawCircle(x1, y1, 5.5, paint(WHITE, pa))

    ca = out3(prog(t, 0.4, 0.7)) * (1 - prog(t, 2.2, 2.5))
    if ca > 0:
        dy = 50 * (1 - out3(prog(t, 0.4, 0.75))) - 70 * in3(prog(t, 2.2, 2.5))
        hours = sum(clamp(p - s0, 0, 8) for s0, _ in SHIFTS)
        shifts = sum(clamp((p - s0) / 8) for s0, _ in SHIFTS)
        counter(cv, hours, W / 2, 610 + dy, 220, ca, 'hour' if 0.5 < hours < 1.5 else 'hours', 76)
        counter(cv, shifts, W / 2, 1420 + dy, 140, ca, 'shift' if 0.5 < shifts < 1.5 else 'shifts', 60)


# Scenes 2 and 3: the question, then the payslip prints (2.45 to 6 s) -------------

STEPS = (120, 190, 270, 340, 450, 520, 690, 780)  # printed length after each eighth note from 4 s


def paper_len(t):
    L = 0.0
    for k, v in enumerate(STEPS):
        t0 = 4.0 + 0.25 * k
        if t >= t0: L = lerp(STEPS[k - 1] if k else 0.0, v, out4(prog(t, t0, t0 + 0.16)))
    return L


def reveal(y): return 4.0 + 0.25 * next(k for k, v in enumerate(STEPS) if v >= y + 14)


def jolt(t):
    k = math.floor((t - 4.0) / 0.25)
    if not 0 <= k < len(STEPS): return 0.0
    tau = t - 4.0 - 0.25 * k
    return -6 * math.exp(-tau / 0.05) * math.cos(tau * 45)


def pill(cv, t):
    """The ruler from the tape: it floats up, prints the payslip, then shrinks into the Dynamic Island."""
    m = io3(prog(t, 6.0, 6.6))
    y = kf(t, (2.45, 960.0), (2.9, 430.0, out4), (6.0, 430.0), (6.6, 571.2, io3)) + jolt(t)
    s = kf(t, (2.45, 1.0), (2.9, 0.82, out4))
    cv.save()
    cv.translate(W / 2, y)
    cv.scale(lerp(s, 164 / 1020, m), lerp(s, 47.5 / 270, m))
    cv.drawPath(ruler_path(1.0, round(1 - io3(prog(t, 6.0, 6.2)), 3)), paint(mix(WHITE, BLACK, io3(prog(t, 6.0, 6.45))), 1 - prog(t, 6.62, 6.75)))
    cv.restore()


def question(cv, t):
    rec = io3(prog(t, 3.75, 4.1))
    a = lerp(1, 0.32, rec) * (1 - prog(t, 5.6, 6.1))
    if a <= 0: return
    gy = lerp(1015, 975, rec)
    L = paper_len(t)
    if L > 0: gy = max(gy, 540 + L + 56 + 150)
    cv.save()
    cv.translate(W / 2, gy)
    cv.scale(lerp(1, 0.72, rec), lerp(1, 0.72, rec))
    first = "What's it"
    rise_line(cv, t, first, -85, 150, TEXT, a, 800, [None if ch == ' ' else (2.5 + 0.03 * i if i < 6 else 2.75 + 0.03 * (i - 7)) for i, ch in enumerate(first)])
    rise_line(cv, t, 'worth?', 150, 230, BLUE, a, lerp(200, 800, out3(prog(t, 3.0, 3.4))), [3.0 + 0.035 * i for i in range(6)],
              tilt_last=-26 * (1 - spring(t - 3.22, 0.3, 12)))
    cv.restore()


# Receipt rows: text, paper x, baseline, size, weight, align, paper colour, ink box in the payroll screenshot, app colour
RECEIPT = (
    ('Oct 15', 672, 83, 30, 500, 1, PAPER_MUTED, (1114, 497, 1245, 531), MUTED),
    ('Work in September 2026', 48, 160, 28, 500, 0, PAPER_MUTED, (74, 591, 524, 627), SOFT),
    ('Base Pay', 48, 240, 36, 500, 0, PAPER_INK, (76, 677, 258, 717), SOFT),
    ('25,200 kr', 672, 240, 36, 700, 1, PAPER_INK, (1047, 676, 1247, 717), TEXT),
    ('Total Supplement', 48, 310, 36, 500, 0, PAPER_INK, (74, 803, 429, 844), SOFT),
    ('2,800 kr', 672, 310, 36, 700, 1, PAPER_INK, (1073, 803, 1247, 844), TEXT),
    ('Gross', 48, 420, 36, 500, 0, PAPER_INK, (75, 1291, 189, 1325), SOFT),
    ('28,000 kr', 672, 420, 36, 700, 1, PAPER_INK, (1045, 1291, 1246, 1332), TEXT),
    ('Estimated tax', 48, 490, 36, 500, 0, PAPER_INK, (76, 1417, 350, 1452), SOFT),
    ('−5,600 kr', 672, 490, 36, 700, 1, PAPER_RED, (1045, 1418, 1248, 1460), TAX_RED),
    ('Net', 48, 640, 48, 800, 0, PAPER_INK, (76, 1550, 145, 1583), TEXT),
    ('22,400 kr', 672, 640, 76, 800, 1, PAPER_INK, (1016, 1546, 1247, 1594), TEXT),
)
ROW = {y: i for i, y in enumerate(sorted({r[2] for r in RECEIPT}))}
K = 575 / 1320  # screenshot px to phone px
SCREEN = (252.0, 530.0, 827.0, 530 + 2868 * K)
PC = ((SCREEN[0] + SCREEN[2]) / 2, (SCREEN[1] + SCREEN[3]) / 2)


def sheet_path(l, tp, r, b, rad, teeth, n=8):
    """Rounded rectangle starting at the top centre, with a torn zigzag bottom while teeth > 0."""
    p = skia.Path()
    p.moveTo((l + r) / 2, tp)
    p.arcTo(r, tp, r, b, rad)
    p.arcTo(r, b, l, b, rad)
    if teeth > 0.5:
        wz = (r - l - 2 * rad) / n
        for k in range(n):
            x = r - rad - k * wz
            p.lineTo(x - wz / 2, b + teeth)
            p.lineTo(x - wz, b + teeth * 0.16 if k < n - 1 else b)
    p.arcTo(l, b, l, tp, rad)
    p.arcTo(l, tp, (l + r) / 2, tp, rad)
    p.close()
    return p


def shell(cv, t, a):
    """Phone body, side buttons and the backlight, in face-on screen coordinates."""
    if a <= 0: return
    l, tp, r, b = SCREEN
    cv.drawRRect(rrect(l - 15, tp - 15, r + 15, b + 15, 95), paint(BODY, a))
    for x0, y0, y1 in ((l - 19, 824.5, 864.5), (l - 19, 904.5, 964.5), (l - 19, 984.5, 1044.5), (r + 15, 894.5, 1004.5)):
        cv.drawRRect(rrect(x0, y0, x0 + 4, y1, 2), paint(RIM, a))


def sheet_scene(cv, t):
    """The payslip prints out of the ruler, then folds into the phone screen showing the same numbers."""
    L = paper_len(t)
    if L <= 0: return
    m = io3(prog(t, 6.0, 6.6))
    ba = io3(prog(t, 6.5, 6.8))
    if ba > 0:
        cv.drawPaint(radial(PC[0], PC[1], 900, BLUE, 0.13 * ba))
        shell(cv, t, ba)
    l, r = lerp(180, SCREEN[0], m), lerp(900, SCREEN[2], m)
    tp, b = lerp(500, SCREEN[1], m), lerp(540 + L, SCREEN[3], m)
    teeth = 56 * (1 - m) * min(1.0, L / 60)
    path = sheet_path(l, tp, r, b, 80 * m, teeth)
    cv.drawPath(path, paint(mix(MIST, APP_BG, io3(prog(t, 6.0, 6.45)))))
    cv.save()
    cv.clipPath(path, skia.ClipOp.kIntersect, True)
    if m < 1:  # slot shadow under the ruler, curl shadow above the torn edge
        cv.drawRect(rect(l, 500, r, 590), skia.Paint(Shader=skia.GradientShader.MakeLinear(
            [skia.Point(0, 540), skia.Point(0, 590)], [argb(BLACK, 0.3 * (1 - m)), argb(BLACK, 0)])))
        cv.drawRect(rect(l, b - 40, r, b + teeth), skia.Paint(Shader=skia.GradientShader.MakeLinear(
            [skia.Point(0, b - 40), skia.Point(0, b + teeth)], [argb(BLACK, 0), argb(BLACK, 0.1 * (1 - m))])))
    sa = io3(prog(t, 6.5, 6.75))
    if sa > 0:
        cv.save()
        cv.translate(SCREEN[0], SCREEN[1])
        cv.scale(K, K)
        img(cv, A.stills['payroll'], sa)
        cv.restore()
    fa = 1 - prog(t, 6.55, 6.75)
    da = 1 - prog(t, 6.0, 6.3)
    for y in (355, 535):
        w = out3(prog(t, reveal(y) + 0.1, reveal(y) + 0.4))
        if w > 0 and da > 0: cv.drawRect(rect(228, 539 + y, 228 + 624 * w, 541 + y), paint(PAPER_MUTED, 0.3 * da))
    text(cv, '14 shifts · 112 h', W / 2, 540 + 740, 26, PAPER_MUTED, da * out3(prog(t, 5.75, 5.95)), 500, 'mono', align=0.5)

    def fly(row): return io3(prog(t, 6.05 + 0.02 * row, 6.55 + 0.02 * row))

    e = fly(0)
    bw = tw('Nord', 30, 700) + 48
    bl, bt, br, bb = (lerp(u, v, e) for u, v in zip((228, 584, 228 + bw, 640), (SCREEN[0] + 72 * K, SCREEN[1] + 480 * K, SCREEN[0] + 236 * K, SCREEN[1] + 548 * K)))
    ba_ = fa * out3(prog(t, 4.0, 4.2))
    cv.drawRRect(rrect(bl, bt, br, bb, 0.28 * (bb - bt)), paint(mix(ICON_BLUE, BADGE, e), ba_))
    text(cv, 'Nord', (bl + br) / 2, (bt + bb) / 2 + 0.36 * 30 * (bb - bt) / 56, 30 * (bb - bt) / 56, WHITE, ba_, 700, align=0.5)
    for s, px, py, size, wght, align, pcol, box, acol in RECEIPT:
        e = fly(ROW[py])
        t0 = reveal(py)
        if e <= 0:
            if align: slot(cv, s, 180 + px, 540 + py, size, pcol, 1.0, t, t0, wght)
            else: text(cv, s, 180 + px - 14 * (1 - out3(prog(t, t0, t0 + 0.25))), 540 + py, size, pcol, out3(prog(t, t0, t0 + 0.2)), wght)
            continue
        ix0, iy0, ix1, iy1 = ink(s, q10(wght))
        k0 = size / 100
        ax, ay = (ix1 if align else ix0), iy1  # anchor: outer ink edge on the ink bottom
        src = (180 + px - align * tw(s, size, wght) + ax * k0, 540 + py + ay * k0)
        dst = (SCREEN[0] + (box[2] if align else box[0]) * K, SCREEN[1] + box[3] * K)
        k = lerp(k0, (box[3] - box[1]) * K / (iy1 - iy0), e)
        text(cv, s, lerp(src[0], dst[0], e) - ax * k, lerp(src[1], dst[1], e) - ay * k, 100 * k, mix(pcol, acol, e), fa, wght)
    cv.restore()

    k = io3(prog(t, 6.1, 6.6))
    if k > 0:
        rim = sheet_path(l - 15, tp - 15, r + 15, b + 15, 80 * m + 15, 0)
        cv.drawPath(rim, paint(mix(SOFT, RIM, prog(t, 6.6, 6.9)), StrokeWidth=3, **STROKE,
                               PathEffect=skia.TrimPathEffect.Make(k / 2, 1 - k / 2, skia.TrimPathEffect.Mode.kInverted)))


# Scene 5: the app tour on a phone in 3D (6.75 to 11.4 s) --------------------------

# screenshot, crop in screenshot px, corner radius, key text out of the background, rise, settle, depth
LIFTS = (
    ('home', (150, 670, 1260, 1090), 0, True, (8.35, 8.72), (8.8, 8.98), 140),
    ('stats', (48, 468, 1272, 1421), 80, False, (9.35, 9.72), (9.8, 9.98), 120),
)
CAPTIONS = (
    ('See how your\n{pay adds up}', 7.0, 7.85),
    ('Know what\n{payday} brings', 8.05, 8.85),
    ('Follow your\nearnings {over time}', 9.05, 9.85),
    ('Ask {anything}\nabout your shifts', 10.05, 10.9),
)


def phone_pose(t):
    cx = kf(t, (6.8, PC[0]), (7.3, 540.0))
    cy = kf(t, (6.8, PC[1]), (7.3, 1190.0), (11.0, 1190.0), (11.4, 960.0, io3))
    s = kf(t, (6.8, 1.0), (7.3, 0.94), (10.0, 0.94), (10.4, 1.0, out3), (11.0, 1.0), (11.4, 1.878, io3))
    yaw = kf(t, (6.8, 0.0), (7.3, -16.0), (8.0, -10.0, lin), (8.4, 14.0, out3), (9.0, 9.0, lin), (9.4, -14.0, out3),
             (10.0, -9.0, lin), (10.4, 8.0, out3), (11.0, 4.0, lin), (11.4, 0.0, io3))
    pitch = kf(t, (6.8, 0.0), (7.3, 6.0), (8.0, 6.0), (8.4, 8.0, out3), (9.0, 8.0), (9.4, 6.0, out3), (10.0, 6.0), (10.4, 4.0, out3), (11.0, 4.0), (11.4, 0.0, io3))
    return cx, cy, s, yaw, pitch


def lift_depth(t, rise, settle, depth): return depth * (back(prog(t, *rise), 1.3) - io3(prog(t, *settle)))


def bubble(cv, im, box, anchor, e):
    cv.save()
    zoom_about(cv, e, *anchor)
    cv.drawImageRect(im, rect(*box), rect(*box), SAMPLING, paint(WHITE, clamp(e * 3)))
    cv.restore()


def wagey(cv, t):
    """The Wagey chat with the question popping in and the answer typing itself out."""
    im = A.stills['wagey']
    img(cv, im)
    cv.drawRect(rect(470, 395, 1290, 555), paint(APP_BG))
    cv.drawRect(rect(40, 555, 1150, 1070), paint(APP_BG))
    e = spring(t - 10.2, 0.55, 18)
    if e > 0: bubble(cv, im, (482, 408, 1271, 540), (1271, 540), e)
    e = spring(t - 10.4, 0.6, 16)
    if e > 0:
        bubble(cv, im, (48, 566, 1139, 961), (48, 566), e)
        for i, (y0, y1) in enumerate(((613, 659), (678, 725), (809, 852), (876, 923))):
            x = lerp(90, 1175, out3(prog(t, 10.45 + 0.125 * i, 10.6 + 0.125 * i)))
            if x < 1175:
                cv.save()
                zoom_about(cv, e, 48, 566)
                cv.drawRect(rect(x, y0 - 8, 1115, y1 + 10), skia.Paint(Shader=skia.GradientShader.MakeLinear(
                    [skia.Point(x, 0), skia.Point(x + 60, 0)], [argb(CARD, 0), argb(CARD, 1)])))
                cv.restore()
    a = prog(t, 10.95, 11.1)
    if a > 0: cv.drawImageRect(im, rect(100, 985, 165, 1050), rect(100, 985, 165, 1050), SAMPLING, paint(WHITE, a))


def screen(cv, t):
    """App screens in screenshot pixels, with the transitions between them."""
    S = A.stills
    if t < 8.0:
        img(cv, S['payroll'])
    elif t < 8.4:  # the payroll sheet slides away
        e = out4(prog(t, 8.0, 8.4))
        img(cv, S['home'])
        cv.drawRect(rect(0, 0, 1320, 2868), paint(BLACK, 0.5 * (1 - e)))
        cv.save()
        cv.translate(0, e * 2700)
        cv.clipRRect(rrect(0, 186, 1320, 3400, 125), skia.ClipOp.kIntersect, True)
        img(cv, S['payroll'])
        cv.restore()
    elif t < 9.0:
        img(cv, S['home'])
    elif t < 9.4:  # push to statistics
        e = out3(prog(t, 9.0, 9.4))
        img(cv, S['home'], x=-396 * e)
        cv.drawRect(rect(0, 0, 1320, 2868), paint(BLACK, 0.3 * e))
        x = 1320 * (1 - e)
        cv.drawRect(rect(x - 50, 0, x, 2868), skia.Paint(Shader=skia.GradientShader.MakeLinear(
            [skia.Point(x - 50, 0), skia.Point(x, 0)], [argb(BLACK, 0), argb(BLACK, 0.35)])))
        img(cv, S['stats'], x=x)
    elif t < 10.0:
        img(cv, S['stats'])
    else:  # zoom over to Wagey
        cv.drawRect(rect(0, 0, 1320, 2868), paint(APP_BG))
        a = 1 - prog(t, 10.0, 10.3)
        if a > 0:
            cv.save()
            zoom_about(cv, lerp(1, 0.92, out3(prog(t, 10.0, 10.4))), 660, 1434)
            img(cv, S['stats'], a)
            cv.restore()
        b = out3(prog(t, 10.05, 10.4))
        if b > 0:
            cv.save()
            zoom_about(cv, lerp(1.1, 1.0, b), 660, 1434)
            cv.saveLayerAlpha(None, round(255 * b))
            wagey(cv, t)
            cv.restore()
            cv.restore()


def phone(cv, t):
    cx, cy, s, yaw, pitch = phone_pose(t)
    R, o = rot(yaw, pitch), plane_origin(cx, cy)

    def plane(dz=0.0):  # a plane parallel to the phone, dz px behind it, drawn in face-on screen coordinates
        cv.save()
        cv.concat(mat(homography(R, s, o + R @ np.array([0.0, 0.0, dz * s]))))
        cv.translate(-PC[0], -PC[1])

    l, tp, r, b = SCREEN
    ba = io3(prog(t, 6.5, 6.8))
    cv.drawPaint(radial(cx, cy, 900 * s, BLUE, 0.13 * ba))
    for dz in (14, 10.5, 7, 3.5):
        plane(dz)
        cv.drawRRect(rrect(l - 15, tp - 15, r + 15, b + 15, 95), paint(SIDE, ba))
        cv.restore()
    plane()
    shell(cv, t, ba)
    cv.drawRRect(rrect(l - 15, tp - 15, r + 15, b + 15, 95), paint(mix(SOFT, RIM, prog(t, 6.6, 6.9)), StrokeWidth=3, **STROKE))
    cv.save()
    cv.clipRRect(rrect(l, tp, r, b, 80), skia.ClipOp.kIntersect, True)
    cv.save()
    cv.translate(l, tp)
    cv.scale(K, K)
    screen(cv, t)
    lifts = [(name, box, rad, lift_depth(t, rise, settle, depth)) for name, box, rad, _, rise, settle, depth in LIFTS]
    for name, box, rad, d in lifts:
        if d > 0.3:
            cv.drawRRect(rrect(*box, rad), paint(APP_BG))
            sh, pad = A.lift_shadow[name]
            cv.drawImage(sh, box[0] - pad, box[1] - pad + d * 0.4 / K, SAMPLING, paint(WHITE, 0.75 * clamp(d / 40)))
    cv.restore()
    ga = 0.1 * clamp(abs(yaw) / 12)
    if ga > 0.004:
        gx = PC[0] - yaw * 36
        cv.drawRect(rect(l, tp, r, b), skia.Paint(Shader=skia.GradientShader.MakeLinear(
            [skia.Point(gx - 230, PC[1] - 90), skia.Point(gx + 230, PC[1] + 90)], [argb(WHITE, 0), argb(WHITE, ga), argb(WHITE, 0)])))
    cv.restore()
    cv.restore()
    for name, box, rad, d in lifts:
        if d > 0.3:
            plane(-d)
            cv.translate(l, tp)
            cv.scale(K, K)
            cv.drawImage(A.lift[name], box[0], box[1], SAMPLING)
            cv.restore()


# Scenes 6 and 7: the app closes into its icon, then the end card (11.4 to 15 s) ----

ICON_PX = 400  # icon width inside a Blender frame
RNG = np.random.default_rng(12)
PARTICLES = [(i / 28 * 2 * math.pi + RNG.uniform(-0.1, 0.1), RNG.uniform(260, 720), RNG.uniform(0.7, 1.3), RNG.random() < 0.35) for i in range(28)]


@lru_cache(maxsize=4)
def icon_image(f):
    if A.icon_frames: return skia.Image.open(str(A.icon_frames[f])).withDefaultMipmaps(), ICON_PX
    return A.flat_icon, 512


def icon(cv, t, cx, cy, size, a=1.0, bright=1.0):
    im, px = icon_image(int(clamp(round((t - 12.0) * FPS), 0, 179)))
    p = paint(WHITE, a)
    if bright != 1: p.setColorFilter(skia.ColorFilters.Matrix([bright, 0, 0, 0, 0, 0, bright, 0, 0, 0, 0, 0, bright, 0, 0, 0, 0, 0, 1, 0]))
    cv.save()
    cv.translate(cx, cy)
    cv.scale(size / px, size / px)
    if px == 512: cv.clipRRect(rrect(-256, -256, 256, 256, 115), skia.ClipOp.kIntersect, True)
    cv.drawImage(im, -im.width() / 2, -im.height() / 2, SAMPLING, p)
    cv.restore()


def close_app(cv, t):
    e, ev = io3(prog(t, 11.4, 11.75)), io3(prog(t, 11.4, 11.66))  # height lands first so the window is square for the icon
    top = H / 2 - 2868 * K * 1.878 / 2
    l, r = lerp(0.0, 350.0, e), lerp(float(W), 730.0, e)
    tp, b = lerp(top, 510.0, ev), lerp(H - top, 890.0, ev)
    ant = in3(prog(t, 11.75, 12.0))
    cv.save()
    zoom_about(cv, lerp(1, 0.86, ant), 540, 700)
    cv.save()
    cv.clipRRect(rrect(l, tp, r, b, lerp(150, 85, e)), skia.ClipOp.kIntersect, True)
    x = prog(e, 0.35, 0.8)
    cv.drawRect(rect(l, tp, r, b), paint(APP_BG, 1 - x))
    k = max((r - l) / 1320, (b - tp) / 2868)
    cv.save()
    cv.translate((l + r) / 2, (tp + b) / 2)
    cv.scale(k, k)
    cv.translate(-660, -1434)
    img(cv, A.stills['wagey'], 1 - x)
    cv.restore()
    if x > 0: icon(cv, 12.0, (l + r) / 2, (tp + b) / 2, max(r - l, b - tp), x, lerp(1, 0.75, ant))
    cv.restore()
    cv.restore()


def endcard(cv, t):
    tau = t - 12.0
    iy = lerp(700, 620, io3(prog(t, 13.0, 13.6)))
    cv.drawPaint(radial(540, iy, 620, BLUE, 0.2 * out3(prog(t, 12.0, 12.4))))
    for delay, width, a0 in ((0.0, 26, 0.5), (0.08, 12, 0.35)):
        x = prog(tau - delay, 0, 0.7)
        if 0 < x < 1:
            rr = lerp(190, 1300, out3(x))
            cv.drawRRect(rrect(540 - rr, 700 - rr, 540 + rr, 700 + rr, 0.45 * rr), paint(mix(WHITE, BLUE, 0.4), a0 * (1 - x) ** 1.5, StrokeWidth=lerp(width, 1, x), **STROKE))
    x = prog(tau, 0, 0.9)
    if 0 < x < 1:
        for ang, dist, size, blue in PARTICLES:
            rr = lerp(170, 170 + dist, out3(x))
            cv.save()
            cv.translate(540 + math.cos(ang) * rr, 700 + math.sin(ang) * rr)
            cv.rotate(math.degrees(ang) - 90)
            ln = 30 * size * (1 - 0.5 * x)
            cv.drawRRect(rrect(-5, -ln / 2, 5, ln / 2, 5), paint(BLUE if blue else WHITE, 0.9 * (1 - x) ** 1.2))
            cv.restore()
    icon(cv, t, 540, iy, 380 * (0.86 + 0.14 * spring(tau, 0.35, 22)))

    wm = 1.36
    x0, y0 = 540 - 174 * wm, 848 - 2 * wm
    for i, p in enumerate(A.wordmark):
        e = spring(t - 13.0 - 0.06 * i, 0.72, 15)
        if e <= 0: continue
        cv.save()
        cv.clipRect(rect(0, 800, W, y0 + 104 * wm))
        cv.translate(x0, y0 + (1 - e) * 120 * wm)
        cv.scale(wm, wm)
        cv.drawPath(p, paint(WHITE))
        cv.restore()
    caption(cv, 'Know what your\n{shift is worth}', 1112, t, 13.4, None, 62)
    e = spring(t - 13.9, 0.5, 16)
    if e > 0:
        cv.save()
        zoom_about(cv, e, 540, 1330)
        img(cv, A.badge, clamp(e * 2), 540 - A.badge.width() / 2, 1330 - A.badge.height() / 2)
        cv.restore()
    a = out3(prog(t, 14.0, 14.35))
    text(cv, 'Free to start', W / 2, 1462 + 16 * (1 - a), 40, MUTED, a, 600, align=0.5)
    a = 0.7 * out3(prog(t, 14.1, 14.5))
    text(cv, 'Account required. Some features require', W / 2, 1790, 24, MUTED, a, 500, align=0.5)
    text(cv, 'a subscription or in-app purchase.', W / 2, 1826, 24, MUTED, a, 500, align=0.5)


# Frame ------------------------------------------------------------------------

def shake(t):
    x = y = 0.0
    for t0, amp, decay in ((2.0, 5.0, 0.08), (12.0, 16.0, 0.11), (13.2, 3.0, 0.06)):
        tau = t - t0
        if 0 <= tau < 0.6:
            e = amp * math.exp(-tau / decay)
            x += e * math.sin(tau * 97 + t0)
            y += e * math.cos(tau * 83 + 2 * t0)
    return x, y


def scene(cv, t):
    cv.restoreToCount(1)
    cv.resetMatrix()
    cv.clear(argb(INK))
    cv.drawPaint(radial(540 + 140 * math.sin(t * 0.5), 700 + 120 * math.cos(t * 0.37), 1150, NIGHT, 0.8))
    cv.save()
    cv.translate(*shake(t))
    if t < 2.45: tape(cv, t)
    if 2.45 <= t < 6.1: question(cv, t)
    if 4.0 <= t < 6.75: sheet_scene(cv, t)
    if 2.45 <= t < 6.75: pill(cv, t)
    if 6.75 <= t < 11.4: phone(cv, t)
    if 11.4 <= t < 12.0: close_app(cv, t)
    if t >= 12.0: endcard(cv, t)
    for src, t_in, t_out in CAPTIONS:
        if t_in < t < t_out + 0.7: caption(cv, src, 350, t, t_in, t_out)
    cv.restore()
    for t0, a, decay in ((2.0, 0.1, 0.06), (12.0, 0.4, 0.05)):
        if t >= t0: cv.drawPaint(paint(WHITE, a * math.exp(-(t - t0) / decay)))
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeRadial(skia.Point(W / 2, H / 2), 1250, [argb(BLACK, 0), argb(BLACK, 0.5)], [0.5, 1.0])))


# Motion blur sample counts: fast moves get more.
BUSY = ((0.95, 2.1, 24), (1.2, 1.8, 32), (2.4, 3.1, 12), (5.95, 6.7, 12), (7.95, 8.2, 16), (8.95, 9.15, 16), (9.95, 10.15, 12), (11.35, 12.5, 12))


def samples(t): return max([n for a, b, n in BUSY if a <= t < b], default=8)


def post(frame, t, i):
    """Chromatic punch on the impact, bloom and film grain; returns H x W x 3 uint8."""
    src = skia.Image.fromarray(frame, RGBA)
    out = np.empty_like(frame)
    surf = skia.Surface(out)
    cv = surf.getCanvas()
    eps = 0.012 * math.exp(-(t - 12.0) / 0.08) if 12.0 <= t < 12.4 else 0.0
    if eps > 0.0005:
        cv.clear(argb(BLACK))
        for ch, s in ((0, 1 + 2 * eps), (1, 1 + eps), (2, 1.0)):
            m = [0.0] * 20
            m[ch * 6] = m[18] = 1.0
            cv.save()
            zoom_about(cv, s, W / 2, H / 2)
            cv.drawImage(src, 0, 0, SAMPLING, skia.Paint(ColorFilter=skia.ColorFilters.Matrix(m), BlendMode=skia.BlendMode.kPlus))
            cv.restore()
    else:
        cv.drawImage(src, 0, 0)
    thr = 0.6
    g = 1 / (1 - thr)
    small = skia.Surface(W // 4, H // 4)
    sc = small.getCanvas()
    sc.scale(0.25, 0.25)
    sc.drawImage(src, 0, 0, SAMPLING, skia.Paint(ColorFilter=skia.ColorFilters.Matrix(
        [g, 0, 0, 0, -thr * g, 0, g, 0, 0, -thr * g, 0, 0, g, 0, -thr * g, 0, 0, 0, 1, 0])))
    bright = small.makeImageSnapshot()
    glow = skia.Surface(W // 4, H // 4)
    gc = glow.getCanvas()
    gc.drawImage(bright, 0, 0, SAMPLING, skia.Paint(ImageFilter=skia.ImageFilters.Blur(5, 5)))
    gc.drawImage(bright, 0, 0, SAMPLING, skia.Paint(ImageFilter=skia.ImageFilters.Blur(18, 18), BlendMode=skia.BlendMode.kPlus))
    strength = 0.22 + (0.12 if 0.95 < t < 2.1 else 0) + (0.08 + 0.6 * math.exp(-(t - 12.0) / 0.25) if t >= 12.0 else 0)
    p = skia.Paint(BlendMode=skia.BlendMode.kPlus)
    p.setAlphaf(clamp(strength))
    cv.save()
    cv.scale(4, 4)
    cv.drawImage(glow.makeImageSnapshot(), 0, 0, SAMPLING, p)
    cv.restore()
    return np.clip(out[..., :3].astype(np.int16) + A.grain[i % len(A.grain)], 0, 255).astype(np.uint8)


def frame(t, i=0):
    """The finished frame at time t, motion-blurred with a 180 degree shutter."""
    n = samples(t)
    buf = np.zeros((H, W, 4), np.uint8)
    surf = skia.Surface(buf)
    cv = surf.getCanvas()
    acc = np.zeros((H, W, 3), np.float32)
    for k in range(n):
        scene(cv, t + ((k + 0.5) / n - 0.5) * 0.5 / FPS)
        acc += buf[..., :3]
    buf[..., :3] = np.rint(acc / n).astype(np.uint8)
    buf[..., 3] = 255
    return post(buf, t, i)


def render(i): return frame(i / FPS, i).tobytes()


class A:
    """Per-process assets, filled by init()."""


def svg_image(path, width):
    dom = skia.SVGDOM.MakeFromStream(skia.Stream.MakeFromFile(str(path)))
    w0, h0 = 119.66407, 40.0  # viewBox of the App Store badge
    dom.setContainerSize(skia.Size(w0, h0))
    k = width / w0
    surf = skia.Surface(round(width), round(h0 * k))
    c = surf.getCanvas()
    c.scale(k, k)
    dom.render(c)
    return surf.makeImageSnapshot().withDefaultMipmaps()


def lift_images(name, box, rad, keyed):
    """The lifted part of a screenshot and its soft shadow."""
    x0, y0, x1, y1 = box
    px = skia.Image.open(str(PUB / f'stills/en-{name}.png')).toarray()[y0:y1, x0:x1, :3].astype(np.float32)
    if keyed:  # un-mix light text from the flat background so it can float on its own
        bg = np.array(APP_BG, np.float32)
        a = np.clip(((px - bg) / (255 - bg)).max(-1), 0, 1)[..., None]
        rgb = np.clip(px - (1 - a) * bg, 0, 255 * a)
    else:
        m = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        ms = skia.Surface(m)
        ms.getCanvas().drawRRect(rrect(0, 0, x1 - x0, y1 - y0, rad), paint(WHITE))
        a = m[..., 3:4] / 255.0
        rgb = px * a
    el = skia.Image.fromarray(np.dstack([rgb, 255 * a]).round().astype(np.uint8), RGBA, skia.AlphaType.kPremul_AlphaType).withDefaultMipmaps()
    pad = 90
    sh = skia.Surface(x1 - x0 + 2 * pad, y1 - y0 + 2 * pad)
    sh.getCanvas().drawImage(el, pad, pad, SAMPLING, skia.Paint(ImageFilter=skia.ImageFilters.Blur(26, 26),
                                                              ColorFilter=skia.ColorFilters.Blend(argb(BLACK), skia.BlendMode.kSrcIn)))
    return el, (sh.makeImageSnapshot().withDefaultMipmaps(), pad)


def init():
    A.stills = {n: skia.Image.open(str(PUB / f'stills/en-{n}.png')).makeRasterImage().withDefaultMipmaps() for n in ('home', 'payroll', 'stats', 'wagey')}
    A.lift, A.lift_shadow = {}, {}
    for name, box, rad, keyed, *_ in LIFTS:
        A.lift[name], A.lift_shadow[name] = lift_images(name, box, rad, keyed)
    A.badge = svg_image(PUB / 'brand/app-store-en.svg', 360)
    A.wordmark = wordmark()
    frames = sorted(ICON_FRAMES.glob('*.png'))
    A.icon_frames = frames if len(frames) == 180 else []
    A.flat_icon = skia.Image.open(str(PUB / 'brand/tidex-app-icon.png')).makeRasterImage().withDefaultMipmaps()
    rng = np.random.default_rng(3)
    A.grain = [np.rint(rng.normal(0, 2.0, (H, W, 1))).astype(np.int16) for _ in range(6)]


# Audio ------------------------------------------------------------------------

def hz(m): return 440 * 2 ** ((m - 69) / 12)


def synth():
    """The music bed and the sound design as one stereo mix that follows the picture."""
    rng = np.random.default_rng(0x7D3A)
    n = round(DUR * SR)
    total = n + 3 * SR
    bus = {k: np.zeros((total, 2)) for k in ('drums', 'low', 'keys', 'fx', 'sfx')}
    kicks = []

    def T(d): return np.arange(round(d * SR)) / SR
    def noise(m): return rng.uniform(-1, 1, m)

    def put(name, at, x, pan=0.0, g=1.0):
        i = round(at * SR)
        if i < 0: x, i = x[-i:], 0
        x = x[:total - i]
        a = (pan + 1) * math.pi / 4
        bus[name][i:i + len(x)] += g * x[:, None] * np.array([math.cos(a), math.sin(a)])

    def filt(x, gain):  # zero-phase FFT filter, zero-padded so tails do not wrap
        nfft = 1 << (len(x) + 4096).bit_length()
        f = np.maximum(np.fft.rfftfreq(nfft, 1 / SR), 1.0)
        return np.fft.irfft(np.fft.rfft(x, nfft) * gain(f), nfft)[:len(x)]

    def bp(fc, q):
        sd = 2 * math.asinh(1 / (2 * q)) / math.log(2) / 2.355
        return lambda f: np.exp(-0.5 * (np.log2(f / fc) / sd) ** 2)

    def hp(fc): return lambda f: 1 / np.sqrt(1 + (fc / f) ** 4)
    def lp(fc): return lambda f: 1 / np.sqrt(1 + (f / fc) ** 4)
    def att(t, a): return np.minimum(1, t / a)

    def kick(at, vel=1.0):
        t = T(0.42)
        ph = 2 * np.pi * np.cumsum(46 + 110 * np.exp(-t / 0.028)) / SR
        put('drums', at, vel * (0.9 * np.sin(ph) * np.exp(-t / 0.14) * att(t, 0.001) + 0.12 * noise(len(t)) * np.exp(-t / 0.0015)))
        kicks.append(at)

    def clap(at, vel=1.0, pan=0.0):
        t = T(0.35)
        env = 0.8 * sum(np.where(t >= o, np.exp(-np.maximum(t - o, 0) / 0.005), 0) for o in (0, 0.011, 0.022))
        env = env + 0.55 * np.where(t >= 0.022, np.exp(-np.maximum(t - 0.022, 0) / 0.085), 0)
        put('drums', at, vel * 2.2 * filt(noise(len(t)) * env, bp(1400, 0.8)), pan)

    def hat(at, vel=1.0, open_=False, pan=0.0, cutoff=7500):
        t = T(0.3 if open_ else 0.08)
        put('drums', at, vel * 0.5 * filt(noise(len(t)), hp(cutoff)) * np.exp(-t / (0.085 if open_ else 0.02)) * att(t, 0.0007), pan)

    def bass(at, midi, dur, vel=1.0, decay=math.inf):
        f, t = hz(midi), T(dur + 0.06)
        env = att(t, 0.006) * np.exp(-t / decay) * np.clip(1 - (t - dur) / 0.05, 0, 1)
        put('low', at, vel * 0.55 * np.tanh(1.6 * (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t))) * env)

    def mallet(at, midi, vel=1.0, pan=0.0, decay=0.38):
        f, t = hz(midi), T(decay * 5)
        put('keys', at, vel * att(t, 0.0015) * (0.5 * np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
                                                 + 0.2 * np.sin(2 * np.pi * 3.93 * f * t) * np.exp(-t / 0.045)
                                                 + 0.06 * np.sin(2 * np.pi * 9.1 * f * t) * np.exp(-t / 0.012)), pan)

    def pad(at, midis, dur, vel=1.0, attack=0.35, release=0.8):
        t = T(dur + release)
        env = att(t, attack) * np.clip(1 - (t - dur) / release, 0, 1)
        voices = [hz(m) * d for m in midis for d in (0.9985, 1.0015)]
        x = sum(np.sin(2 * np.pi * f * t + i) for i, f in enumerate(voices)) / math.sqrt(len(voices))
        put('keys', at, vel * 0.05 * env * (1 + 0.06 * np.sin(2 * np.pi * 4.2 * t)) * x)

    def bell(at, midi, vel=1.0, pan=0.0, length=1.6):
        f, t = hz(midi), T(length)
        put('fx', at, vel * 0.32 * att(t, 0.002) * np.exp(-t / (length / 3.2)) * np.sin(2 * np.pi * f * t + 3.2 * np.exp(-t / 0.35) * np.sin(2 * np.pi * f * 3.5 * t)), pan)

    def sweep(at, dur, f0, f1, vel=1.0, env=lambda x: x * x, pan0=0.0, pan1=0.0, q=1.2, to='fx'):
        N, hop, m = 2048, 512, round(dur * SR)
        src, y, win = noise(m + N), np.zeros(m + N), np.hanning(N)
        f = np.maximum(np.fft.rfftfreq(N, 1 / SR), 1.0)
        for i in range(0, m, hop):
            y[i:i + N] += np.fft.irfft(np.fft.rfft(src[i:i + N] * win) * bp(f0 * (f1 / f0) ** (i / m), q)(f), N) * win
        x = y[N // 2:N // 2 + m] / 1.5 * env(np.arange(m) / m) * vel * 1.6
        a = (np.linspace(pan0, pan1, m) + 1) * math.pi / 4
        i0 = round(at * SR)
        bus[to][i0:i0 + m] += np.stack([x * np.cos(a), x * np.sin(a)], 1)[:total - i0]

    def whoosh(at, dur, f0, f1, vel=1.0, pan0=-0.4, pan1=0.4):
        sweep(at, dur, f0, f1, vel, lambda x: np.sin(np.pi * x) ** 2, pan0, pan1, to='sfx')

    def tock(at, vel=1.0, pan=0.0, f0=520):
        t = T(0.12)
        put('sfx', at, vel * np.sin(2 * np.pi * np.cumsum(f0 + 140 * np.exp(-t / 0.012)) / SR) * np.exp(-t / 0.028) * att(t, 0.002), pan)

    def tick(at, vel=1.0, pan=0.0, fc=3800):
        t = T(0.05)
        put('sfx', at, vel * 3 * filt(noise(len(t)), bp(fc, 2.5)) * np.exp(-t / 0.004), pan)

    def tap(at, vel=1.0, pan=0.0):
        t = T(0.1)
        put('sfx', at, vel * att(t, 0.0008) * (0.6 * np.sin(2 * np.pi * (1500 - 500 * t / 0.1) * t) * np.exp(-t / 0.012)
                                               + 0.5 * np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.02)), pan)

    def blip(at, f, vel=0.2, pan=0.0):
        t = T(0.06)
        put('sfx', at, vel * np.sin(2 * np.pi * f * t) * np.exp(-t / 0.014) * att(t, 0.002), pan)

    def thump(at, vel=1.0, f0=45, f1=135, decay=0.16):
        t = T(decay * 4)
        put('sfx', at, vel * 0.8 * np.sin(2 * np.pi * np.cumsum(f0 + (f1 - f0) * np.exp(-t / 0.06)) / SR) * np.exp(-t / decay) * att(t, 0.003))

    def boom(at):
        t = T(1.6)
        sub = np.sin(2 * np.pi * np.cumsum(32 + 30 * np.exp(-t / 0.18)) / SR) * np.exp(-t / 0.55) * att(t, 0.004)
        put('sfx', at, 0.9 * sub + 1.6 * filt(noise(len(t)), lp(260)) * np.exp(-t / 0.09))

    def crash(at, vel=1.0, dur=2.2, rev=False):
        t = T(dur)
        x = filt(noise(len(t)), hp(4200)) * np.exp(-t / 0.55) + 0.4 * filt(noise(len(t)), bp(6800, 1.0)) * np.exp(-t / 0.25)
        put('fx', at - dur if rev else at, vel * 0.3 * (x[::-1] if rev else x * att(t, 0.001)))

    def zipper(at, vel=1.0):
        sweep(at, 0.11, 1100, 3400, vel * 0.7, lambda x: np.sin(np.pi * x) ** 0.8, q=2.2, to='sfx')
        t = T(0.11)
        put('sfx', at, vel * filt(np.sign(np.sin(2 * np.pi * 190 * t)) * 0.08 * np.sin(np.pi * t / 0.11), lp(2400)))

    def ratchet(t0, spins=20):  # one tick per digit the slot wheel passes, slowing like out4
        for j in range(spins - 1, 0, -1):
            tick(t0 + 0.4 * (1 - (j / spins) ** 0.25), 0.16 + 0.2 * (1 - j / spins), 0.15, 5200)

    # Music: 120 BPM, I V vi IV in C with a V build into the impact on bar 6.
    chords = {'C': (36, (55, 60, 64), (72, 76, 79, 84)), 'G': (43, (55, 59, 62), (71, 74, 79, 83)),
              'Am': (45, (57, 60, 64), (72, 76, 81, 84)), 'F': (41, (57, 60, 65), (72, 77, 81, 84))}
    step, tres, mel = 0.125, (0, 3, 6, 8, 11, 14), (0, 1, 2, 1, 3, 2)
    pad(0.0, (55, 60, 64), 1.95, 0.55, attack=0.6)
    for b, name in enumerate(('C', 'C', 'G', 'Am', 'F', 'G'), start=0):
        if b == 0: continue
        t0 = 2.0 * b
        root, chord, arp = chords[name]
        pad(t0, chord, 1.72 if b == 5 else 1.95, 0.9, release=0.05 if b == 5 else 0.8)
        for beat in range(4):
            if t0 + 0.5 * beat < 11.75: kick(t0 + 0.5 * beat, 1.0 if beat == 0 else 0.9)
        for beat in (1, 3):
            if t0 + 0.5 * beat < 11.0: clap(t0 + 0.5 * beat, 0.55, 0.1)
        for s in range(16):
            at = t0 + s * step + (0.006 if s % 2 else 0)
            if at < 11.0 and not 4.0 <= at < 6.0:
                hat(at, 0.34 if s % 4 == 2 else 0.14 if s % 2 else 0.22, s % 4 == 2, 0.35 if s % 2 else -0.25)
        for s in (2, 6, 10, 14):
            if t0 + s * step < 11.5: bass(t0 + s * step, root, step * 1.6, 0.75 if s == 14 else 0.9)
        for i, s in enumerate(tres):
            if t0 + s * step < 11.5: mallet(t0 + s * step, arp[mel[i]], 0.62 * (1.1 if i == 0 else 0.95), 0.35 if i % 2 else -0.35)

    # 0 to 2.45 s: the tape opens, fills one shift, then whips through the month.
    kick(0.0, 0.8)
    sweep(0.0, 0.42, 280, 5200, 0.55, lambda x: np.sin(np.pi * x) ** 1.5, -0.3, 0.3, to='sfx')
    tock(0.12, 0.35, 0, 380)
    for i in range(6): tick(0.22 + 0.03 * i, 0.5 - 0.06 * i, 0.12 * (i + 1) * (-1) ** i)
    for h in range(10, 18): tick(when(playhead, h, 0.5, 0.95), 0.42, 0.08 * (h - 13), 4400)
    sweep(0.95, 1.1, 220, 2600, 0.9, lambda x: np.sin(np.pi * x) ** 2, -0.6, 0.6, to='sfx')
    penta = (60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84, 86, 88)
    for k, (s0, _) in enumerate(SHIFTS[1:]):
        mallet(when(playhead, s0, 1.0, 2.0), penta[k], 0.42, 0.5 * (k % 2 * 2 - 1), 0.22)
    thump(2.0)
    # 2.45 to 6 s: the question, then the printer.
    whoosh(2.42, 0.3, 500, 2400, 0.5, 0, 0)
    tock(2.5, 0.6, -0.2, 600)
    tock(2.75, 0.5, 0.2, 700)
    tap(3.0, 0.7)
    bell(3.0, 84, 0.35, 0.1, 1.2)
    for k in range(len(STEPS)): zipper(4.0 + 0.25 * k, 0.8)
    for _, _, py, _, _, align, *_ in RECEIPT:
        if align: ratchet(reveal(py))
    hits, at = [], 4.0
    for until, dt in ((5.0, 0.125), (5.5, 0.0625), (6.0, 0.0417)):
        while at < until - 1e-6:
            hits.append(at)
            at += dt
    for j, at in enumerate(hits):
        x = j / len(hits)
        hat(at, 0.16 + 0.3 * x, False, -0.35 + 0.7 * x, 6500 + 3000 * x)
    # 6 to 7 s: the receipt folds into the phone.
    whoosh(5.95, 0.5, 300, 1800, 0.8, 0.3, -0.3)
    sweep(6.1, 0.5, 2000, 9000, 0.18, lambda x: 4 * x * (1 - x), -0.5, 0.5, to='sfx')
    tick(6.6, 0.6, 0, 2600)
    tock(6.6, 0.5, 0, 300)
    tap(6.75, 0.6)
    # 8 to 11 s: the tour.
    whoosh(7.97, 0.36, 700, 260, 0.7, 0, 0)
    tock(8.35, 0.5, 0.3, 480)
    tick(8.8, 0.3, 0.3)
    whoosh(8.97, 0.36, 400, 1800, 0.7, 0.6, -0.6)
    tock(9.35, 0.5, -0.3, 480)
    tick(9.8, 0.3, -0.3)
    whoosh(9.97, 0.3, 900, 3000, 0.5, 0, 0)
    tock(10.2, 0.55, 0.3, 760)
    tock(10.4, 0.5, -0.3, 560)
    for j in range(8): blip(10.47 + 0.0625 * j, 1250 + 110 * (j * 3 % 5), 0.2, -0.3 + 0.08 * j)
    # 11 to 12 s: build, push in, close, then a held breath.
    sweep(10.75, 1.0, 500, 9000, 0.32, lambda x: x ** 2.2, -0.4, 0.4)
    for j, at in enumerate([11.0 + 0.125 * j for j in range(4)] + [11.5 + 0.0625 * j for j in range(4)]):
        clap(at, 0.22 + 0.06 * j, -0.2 + 0.05 * j)
    crash(12.0, 0.5, 0.8, rev=True)
    # 12 s: impact.
    kick(12.0, 1.2)
    boom(12.0)
    crash(12.0)
    bass(12.0, 36, 1.6, 0.8, 0.45)
    for m in (60, 64, 67, 72, 76): mallet(12.0, m, 0.35, 0, 0.6)
    for m, d, pn in ((72, 0, -0.3), (79, 0.05, 0.3), (84, 0.1, 0), (88, 0.16, 0.15)): bell(12.0 + d, m, 0.6, pn, 2.6)
    for j, m in enumerate((96, 100, 103)): bell(12.12 + 0.06 * j, m, 0.18 - 0.04 * j, 0.4 * (-1) ** j, 0.5)
    pad(12.0, (60, 64, 67, 72), 2.6, 1.1, attack=0.05)
    # 13 s on: the lock-up.
    for j, m in enumerate((72, 76, 79, 84, 88)): mallet(13.04 + 0.06 * j, m, 0.5, -0.4 + 0.2 * j, 0.3)
    tick(13.2, 0.7, 0, 3000)
    tock(13.2, 0.6, 0, 300)
    kick(13.2, 0.45)
    whoosh(13.38, 0.4, 500, 2000, 0.35, -0.3, 0.3)
    tap(13.92, 0.6)
    bell(14.0, 96, 0.28, 0.2, 1.8)
    for j in range(8): hat(13.125 + 0.25 * j, 0.12, j % 2 == 1, 0.3 * (-1) ** j)

    def reverb(x, wet, rt60=1.8):
        m = round(rt60 * SR)
        t = np.arange(m) / SR
        ir = np.stack([filt(rng.standard_normal(m), lp(3000)) * np.exp(-6.9 * t / rt60) + 0.5 * rng.standard_normal(m) * np.exp(-6.9 * t / 0.35)
                       for _ in range(2)], 1)
        ir[:round(0.012 * SR)] = 0
        ir /= np.sqrt((ir ** 2).sum(0))
        nfft = 1 << (len(x) + m).bit_length()
        return x + wet * np.fft.irfft(np.fft.rfft(x, nfft, axis=0) * np.fft.rfft(ir, nfft, axis=0), nfft, axis=0)[:len(x)]

    duck = np.ones(total)
    for k in kicks:
        seg = duck[round(k * SR):round(k * SR) + round(0.22 * SR)]
        seg[:] = np.minimum(seg, 1 - 0.55 * np.exp(-np.arange(len(seg)) / SR / 0.07))
    d = duck[:, None]
    music = (bus['drums'] * 0.9 + bus['low'] * 0.8 * d + reverb(bus['keys'], 0.2) * 0.75 * d
             + reverb(bus['fx'], 0.3) * 0.8 + reverb(bus['sfx'], 0.12) * 0.85)
    out = np.tanh(1.1 * music[:n]) * np.clip((DUR - np.arange(n) / SR) / 0.4, 0, 1)[:, None]
    return out * (0.89 / np.abs(out).max())


def write_wav(path, audio):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.rint(np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())


# Output -----------------------------------------------------------------------

def mux(video, audio, dst):
    """Two-pass loudnorm to -15 LUFS like scripts/export.sh, then AAC next to the H.264 stream."""
    log = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', str(audio), '-af', 'loudnorm=I=-15:TP=-1.5:LRA=11:print_format=json',
                          '-f', 'null', '-'], capture_output=True, text=True).stderr
    m = json.loads(log[log.rindex('{'):log.rindex('}') + 1])
    af = (f"loudnorm=I=-15:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
          f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true,aresample=48000")
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(video), '-i', str(audio), '-map', '0:v', '-map', '1:a',
                    '-c:v', 'copy', '-af', af, '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-movflags', '+faststart', '-t', str(DUR), str(dst)], check=True)


def workers(): return Pool(max(1, (os.cpu_count() or 2) - 1), initializer=init)


def render_all():
    WORK.mkdir(parents=True, exist_ok=True)
    typeface('manrope'), typeface('mono')  # download once, before the workers start
    if len(list(ICON_FRAMES.glob('*.png'))) != 180: print('no Blender icon frames in video/out/reel/icon, using the flat icon')
    audio, video = WORK / 'audio.wav', WORK / 'video.mp4'
    write_wav(audio, synth())
    ff = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
                           '-r', str(FPS), '-i', '-', '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
                           '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-maxrate', '20M', '-bufsize', '40M', '-profile:v', 'high',
                           '-level:v', '4.2', '-g', '60', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
                           '-color_range', 'tv', '-movflags', '+faststart', str(video)], stdin=subprocess.PIPE)
    with workers() as pool:
        for i, data in enumerate(pool.imap(render, range(NF), chunksize=2)):
            ff.stdin.write(data)
            if i % 60 == 0: print(f'frame {i}/{NF}', flush=True)
    ff.stdin.close()
    if ff.wait(): sys.exit('ffmpeg failed')
    mux(video, audio, OUT / 'Tidex-Reel.mp4')
    print(f'wrote {OUT / "Tidex-Reel.mp4"}')


def stills(times):
    WORK.mkdir(parents=True, exist_ok=True)
    typeface('manrope'), typeface('mono')
    with workers() as pool:
        shots = pool.starmap(frame, [(t, round(t * FPS)) for t in times])
    ims = [skia.Image.fromarray(np.dstack([s, np.full((H, W, 1), 255, np.uint8)]), RGBA) for s in shots]
    for t, im in zip(times, ims): im.save(str(WORK / f'still-{t:.2f}.png'), skia.kPNG)
    if len(ims) > 1:
        cols = min(4, len(ims))
        sheet = skia.Surface(cols * 270, math.ceil(len(ims) / cols) * 480)
        c = sheet.getCanvas()
        for k, im in enumerate(ims):
            c.drawImageRect(im, rect(k % cols * 270, k // cols * 480, (k % cols + 1) * 270, (k // cols + 1) * 480), SAMPLING)
        sheet.makeImageSnapshot().save(str(WORK / 'contact.png'), skia.kPNG)


def check():
    b = skia.Rect()
    letters = wordmark()
    for p in letters: b.join(p.computeTightBounds())
    assert len(letters) == 5 and 2.5 < b.left() < 3.5 and 343 < b.right() < 346 and 1.5 < b.top() < 2.5 and 103 < b.bottom() < 104.5, b
    assert kf(0.5, (0, 0.0), (1, 10.0, lin)) == 5.0 and kf(0.25, (0, (0.0, 4.0)), (1, (8.0, 0.0), lin)) == (2.0, 3.0)
    assert abs(spring(3.0) - 1) < 1e-4 and spring(-1) == 0
    f = font('manrope', 700)
    assert layout('To', 'manrope', 700)[1] < sum(f.getWidths(f.textToGlyphs('To'))) - 3, 'kerning missing'
    assert odo_pos(9.5, 1) == 0.5 and odo_pos(15.0, 1) == 1 and odo_pos(99.5, 2) == 0.5
    assert caption_words('Ask {anything}\nabout') == [('Ask anything', [('Ask', 0, False), ('anything', 4, True)]), ('about', [('about', 0, False)])]
    assert sum(s1 - s0 for s0, s1 in SHIFTS) == 112 and len(SHIFTS) == 14 and abs(playhead(2.0) - END) < 1e-9
    assert 225 * 112 == 25200 and 25 * 112 == 2800 and 25200 + 2800 == 28000 and 28000 - 5600 == 22400
    assert paper_len(6.0) == STEPS[-1] and reveal(640) == 5.5
    audio = synth()
    assert audio.shape == (round(DUR * SR), 2) and abs(np.abs(audio).max() - 0.89) < 1e-9
    print('reel checks passed')


if __name__ == '__main__':
    arg = sys.argv[1:]
    if arg[:1] == ['--check']: check()
    elif arg[:1] == ['--still']: stills([float(v) for v in arg[1:]])
    elif arg[:1] == ['--audio']:
        WORK.mkdir(parents=True, exist_ok=True)
        write_wav(WORK / 'audio.wav', synth())
    else: render_all()
