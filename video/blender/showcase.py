# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["skia-python", "numpy"]
# ///
"""Tidex showcase film, 28 s at 886 x 1920, App Store Connect's app preview size. Skia draws every frame around
the 3D layer from phone3d.py and cuts the music to it. Run from the repository root:

  /Applications/Blender.app/Contents/MacOS/Blender -b -P video/blender/phone3d.py -- [--preview]
  uv run video/blender/showcase.py [--preview] [--still F F ...] [--locale en-US] [--captures DIR]

Writes video/blender/out/tidex-showcase-<locale>.mp4, or -preview.mp4 at half size from the preview layer.
--still writes those frames and a contact sheet to video/blender/out/stills/ instead.

The music is "Product Launch Advertisement Commercial Music" by HitsLab, from Pixabay:
https://pixabay.com/music/future-bass-product-launch-advertisement-commercial-music-301409/
Download the MP3 to video/blender/music.mp3. The Pixabay license lets the film use it, but not redistribute the file
on its own, so it stays out of this public repository.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys
import wave
from functools import cache
from multiprocessing import Pool

import numpy as np
import skia

from timeline import (BEAT, CAPTURES, CONFIG, DECIDE, DROP, FPS, FRAMES, H, LAND, LIFTS, OUT, OUTRO, OVERVIEW, ROOT,
                      PAD, STACK, SUBJECT, TEXT, TRUST, W, at, capture, layer, lift_boxes)

MUSIC, SOUNDS, SR = ROOT / 'video/blender/music.mp3', ROOT / 'video/public/audio', 48000
RGBA = skia.ColorType.kRGBA_8888_ColorType
SAMPLING = skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear)
HEADLINE, BODY, LOCKUP, BADGE = 84, 44, 112, 112


def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


WHITE, BLACK, APP_BG, ACCENT = (255, 255, 255), (0, 0, 0), hexc('070b12'), hexc(CONFIG['accent'][1:])
GLOW, GLOW_ALPHA = hexc(CONFIG['glow'][1:7]), int(CONFIG['glow'][7:9], 16) / 255
GRADIENT = [hexc(c) for c in re.findall(r'#(\w{6})', CONFIG['background'])]
STOPS = [int(p) / 100 for p in re.findall(r'(\d+)%', CONFIG['background'])]
ANGLE = math.radians(int(re.search(r'(\d+)deg', CONFIG['background'])[1]))

# On-screen text per beat, as (panel, line) in the "panels" of tidex-3d.json, where line 0 is the headline and 1
# the body. The film reuses the approved App Store copy, so any locale the screenshots have renders here as well.
COPY = {
    'tension': (0, 0),  # What's that extra shift really worth?
    'answer': (0, 1),  # Tidex shows what your work adds up to, before payday.
    'decision': (1, 0),  # Say yes to extra hours knowing what they pay
    'clarity': (2, 0),  # Every job in one overview
    'trust': (3, 0),  # Know where the money comes from
    'close': (4, 0),  # Your time is worth keeping track of
    'cta': (4, 1),  # Start with your next shift.
}
# Headlines: beat, frame the first word rises on, frames between words, frame the words leave on. The hook's words
# rise on eighth notes.
HEADLINES = [('tension', at(2), BEAT / 2, at(DROP - 1)), ('answer', at(DROP, 6), 2.5, at(DECIDE - 1.5)),
             ('decision', at(DECIDE, 12), 2.5, at(LAND - 4)), ('clarity', at(OVERVIEW, 18), 3, at(TRUST - 1)),
             ('trust', at(TRUST, 12), 3, at(TRUST + 3.5))]
# The music: the track cut on its bar lines, as (first bar of the track, bars). The breakdown's last two bars with
# the riser make the hook, the third groove carries the story, and the final section runs to the closing hit.
BAR0, BAR = 1.0251, 1.90438  # the track's first downbeat and bar length, in seconds
EDIT = [(26, 2), (17, 7), (28, None)]
# Whooshes from video/public/audio under the biggest moves: (frame, name, gain). One peaks 6 frames after it starts.
SFX = [(at(DROP, -10), 'whoosh', 0.45), (at(DECIDE, -5), 'whoosh', 0.3), (at(LAND - 1, -4), 'whoosh', 0.3),
       (at(OVERVIEW, -5), 'whoosh', 0.3), (at(TRUST, -5), 'whoosh', 0.3), (at(OUTRO - 1, 4), 'whoosh', 0.35)]
IMPACTS = [(at(DROP), 9, 0.14), (at(LAND), 12, 0.12), (at(OUTRO), 8, 0.22)]  # frame, shake in pixels, white flash
# Lift-outs: width on screen in pixels, and how far the card's centre moves from the glass. The payroll rows
# line up in a list instead.
LIFT_WIDTH = {'total': 640, 'extra': 590, 'month': 370, 'base': 800, 'supplement': 800, 'tax': 800, 'net': 800}
LIFT_MOVE = {'total': (0, -40), 'extra': (-110, -170), 'month': (130, 40)}
PHONE_PX = 0.85 * (SUBJECT[3] - SUBJECT[1])  # the phone's height on screen in a regular shot


# Timing -----------------------------------------------------------------------------------------------------------

def clamp(x, a=0.0, b=1.0): return a if x < a else b if x > b else x
def lerp(a, b, x): return a + (b - a) * x
def prog(t, t0, t1): return clamp((t - t0) / (t1 - t0))
def out3(x): return 1 - (1 - x) ** 3
def in3(x): return x ** 3
def io3(x): return 4 * x ** 3 if x < 0.5 else 1 - (2 - 2 * x) ** 3 / 2
def back(x, s=1.7): return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2


def spring(frames, z=0.6, w=16.0):
    """Unit step response of a damped spring, `frames` after it starts; 0 before."""
    tau = frames / FPS
    if tau <= 0: return 0.0
    wd = w * math.sqrt(1 - z * z)
    return 1 - math.exp(-z * w * tau) * (math.cos(wd * tau) + z * w / wd * math.sin(wd * tau))


def kf(t, *keys):
    """Keys are (frame, value[, ease]); a key's ease shapes the move that ends on it."""
    if t <= keys[0][0]: return keys[0][1]
    for (t0, v0, *_), (t1, v1, *e) in zip(keys, keys[1:]):
        if t < t1:
            x = (e[0] if e else io3)((t - t0) / (t1 - t0))
            return tuple(lerp(a, b, x) for a, b in zip(v0, v1)) if isinstance(v0, tuple) else lerp(v0, v1, x)
    return keys[-1][1]


# Drawing ----------------------------------------------------------------------------------------------------------

def argb(c, a=1.0): return skia.ColorSetARGB(round(255 * clamp(a)), *c)
def paint(c=WHITE, a=1.0, **kw): return skia.Paint(Color=argb(c, a), AntiAlias=True, **kw)
def rrect(l, t, r, b, rad): return skia.RRect.MakeRectXY(skia.Rect.MakeLTRB(l, t, r, b), rad, rad)


def backdrop(cv, t):
    """The brand gradient and the glow behind the phone. The film moves along the App Store strip's gradient, from
    its dark start to its bright end at the close, and the glow pulses with the bass of the music."""
    p = kf(t, (0, 0.0), (at(DROP, -8), 0.03), (at(DROP, 10), 0.14, out3), (at(DECIDE, -2), 0.18),
           (at(DECIDE, 10), 0.26, out3), (at(OVERVIEW, -2), 0.30), (at(OVERVIEW, 10), 0.38, out3),
           (at(TRUST, -2), 0.42), (at(TRUST, 10), 0.50, out3), (at(OUTRO, -15), 0.54), (at(OUTRO, 5), 0.80, out3))
    length = W / 0.22  # the frame is 22 % of the strip
    dx, dy = math.sin(ANGLE), -math.cos(ANGLE)  # CSS angles: 0deg points up, 90deg right
    x0 = -p * length
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeLinear(
        [skia.Point(x0, 0), skia.Point(x0 + dx * length, dy * length)], [argb(c) for c in GRADIENT], STOPS)))
    pulse = A.pulse[min(max(round(t), 0), FRAMES - 1)]
    subject = ((SUBJECT[0] + SUBJECT[2]) / 2, (SUBJECT[1] + SUBJECT[3]) / 2)
    gx, gy = kf(t, (at(OUTRO, -15), subject), (at(OUTRO, 5), (W / 2, 0.47 * H), out3))
    m = skia.Matrix.Translate(gx, gy)
    m.preScale(0.55 * PHONE_PX, 0.45 * PHONE_PX)  # CSS: radial-gradient(0.55h 0.45h at the phone, glow, transparent)
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeRadial(
        skia.Point(0, 0), 1, [argb(GLOW, GLOW_ALPHA * pulse), argb(GLOW, 0)], [0, 1], skia.TileMode.kClamp, 0, m)))


def shake(t):
    x = y = 0.0
    for t0, amp, _ in IMPACTS:
        tau = t - t0
        if 0 <= tau < 18:
            e = amp * math.exp(-tau / 3.5)
            x += e * math.sin(tau * 2.9 + t0)
            y += e * math.cos(tau * 2.5 + 2 * t0)
    return x, y


# Lift-outs --------------------------------------------------------------------------------------------------------

def quad(name, t):
    """Corners of a lift-out region on screen at time t, between the frames phone3d.py tracked."""
    f = clamp(t, 0, FRAMES - 1)
    i = min(int(f), FRAMES - 2)
    a, b, x = A.track[name][i], A.track[name][i + 1], f - i
    return [(lerp(a[k], b[k], x), lerp(a[k + 1], b[k + 1], x)) for k in range(0, 8, 2)]


def centre(points): return sum(p[0] for p in points) / 4, sum(p[1] for p in points) / 4


def raised(name, t):
    """0 on the glass, 1 lifted (overshooting a little on the way)."""
    _, _, rise, settle = LIFTS[name]
    e = back(prog(t, at(rise), at(rise, 12)), 1.4)
    if settle: e *= 1 - io3(prog(t, at(settle), at(settle, 10)))
    return e


def target(name, t):
    """Corners of the lifted card: facing the camera, LIFT_WIDTH wide."""
    l, tp, r, b = A.boxes[name]
    w = LIFT_WIDTH[name]
    h = w * (b - tp) / (r - l)
    if name in STACK:  # the payroll rows line up in a list over the phone
        heights = [LIFT_WIDTH[n] * (A.boxes[n][3] - A.boxes[n][1]) / (A.boxes[n][2] - A.boxes[n][0]) for n in STACK]
        gap, k = 20, STACK.index(name)
        middles = [centre(quad(n, t)) for n in STACK]
        cx = sum(m[0] for m in middles) / 4
        cy = sum(m[1] for m in middles) / 4 - (sum(heights) + gap * 3) / 2 + sum(heights[:k]) + gap * k + h / 2 - 40
    else:
        cx, cy = centre(quad(name, t))
        cx, cy = cx + LIFT_MOVE[name][0], cy + LIFT_MOVE[name][1]
    return [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]


def lifts(cv, t):
    """Parts of the screen rise off the glass toward the viewer, then settle back. The card starts exactly on its
    region of the 3D screen, so the lift reads as the pixels themselves coming loose."""
    up = [(name, raised(name, t) * (1 - prog(t, at(OUTRO - 1), at(OUTRO - 1, 10)))) for name in LIFTS]
    up = [(name, e) for name, e in up if e > 0.003]
    for name, e in up:  # the region's place on the glass stays empty while it is up
        path = skia.Path()
        path.addPoly([skia.Point(*p) for p in quad(name, t)], True)
        cv.drawPath(path, paint(APP_BG, clamp(e * 4)))
    for name, e in up:
        l, tp, r, b = A.boxes[name]
        w, h = r - l, b - tp
        dst = [skia.Point(lerp(p[0], q[0], e), lerp(p[1], q[1], e)) for p, q in zip(quad(name, t), target(name, t))]
        m = skia.Matrix()
        m.setPolyToPoly([skia.Point(0, 0), skia.Point(w, 0), skia.Point(w, h), skia.Point(0, h)], dst)
        radius = 34
        shadow = skia.Path()
        shadow.addRRect(rrect(0, 0, w, h, radius))
        shadow.transform(m)
        s = clamp(e)
        cv.save()
        cv.translate(0, 30 * s)
        blur = skia.MaskFilter.MakeBlur(skia.kNormal_BlurStyle, 8 + 26 * s)
        cv.drawPath(shadow, paint(BLACK, 0.55 * s, MaskFilter=blur))
        cv.restore()
        cv.save()
        cv.concat(m)
        cv.clipRRect(rrect(0, 0, w, h, radius), True)
        cv.drawImage(A.crops[name], 0, 0, SAMPLING)
        rim = paint(WHITE, 0.16 * s, Style=skia.Paint.kStroke_Style, StrokeWidth=3)
        cv.drawRRect(rrect(1, 1, w - 1, h - 1, radius), rim)
        cv.restore()


# Type -------------------------------------------------------------------------------------------------------------

@cache
def font(size):
    f = skia.Font(A.typeface, size)
    f.setSubpixel(True)
    f.setLinearMetrics(True)
    f.setHinting(skia.FontHinting.kNone)
    f.setEdging(skia.Font.Edging.kAntiAlias)
    return f


@cache
def blob(word, size): return skia.TextBlob.MakeFromShapedText(word, font(size))  # kerned; y = 0 is the ascent line


def wrap(advances, space, width):
    lines, used = [[]], 0.0
    for i, a in enumerate(advances):
        if lines[-1] and used + space + a > width:
            lines.append([])
            used = 0.0
        used += (space if lines[-1] else 0) + a
        lines[-1].append(i)
    return lines


@cache
def layout(markup, size, width, max_height, leading, align):
    """Words as (x, baseline, word, accent, line) in a box whose top left is 0, 0. Lines are balanced like CSS
    text-wrap: balance, and the size shrinks until the block fits max_height. Returns the words, size and height."""
    tokens, before = [], ' '
    for i, part in enumerate(re.split(r'</?em>', markup)):
        for j, word in enumerate(part.split()):
            if j == 0 and not before[-1:].isspace() and not part[:1].isspace():  # no space at the tag, as in "</em>,"
                tokens[-1] = (tokens[-1][0] + word, tokens[-1][1])
            else:
                tokens.append((word, i % 2 == 1))
        before = part or before
    while True:
        advances = [font(size).measureText(word) for word, _ in tokens]
        space = font(size).measureText(' ')
        lines = wrap(advances, space, width)
        if len(lines) * leading * size <= max_height or size < 30: break
        size *= 0.94
    lo, hi = max(advances), width
    for _ in range(16):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if len(wrap(advances, space, mid)) > len(lines) else (lo, mid)
    lines = wrap(advances, space, hi)
    words = []
    for row, line in enumerate(lines):
        used = sum(advances[i] for i in line) + space * (len(line) - 1)
        x = (width - used) / 2 if align == 'center' else 0.0
        for i in line:
            words.append((x, (row * leading + 0.89) * size, *tokens[i], row))  # Poppins sits 0.89 em below the top
            x += advances[i] + space
    return tuple(words), size, len(lines) * leading * size


def headline(cv, markup, box, t, t_in, gap, t_out=None, size=HEADLINE, align='left', leading=1.08, alpha=1.0):
    """Words spring up through their line one by one, then leave upwards."""
    left, top, right, bottom = box
    words, size, _ = layout(markup, size, right - left, bottom - top, leading, align)
    for n, (x, y, word, accent, _) in enumerate(words):
        e_in = spring(t - t_in - n * gap, 0.62, 15)
        e_out = in3(prog(t, t_out + n, t_out + n + 9)) if t_out else 0.0
        if e_in <= 0.001 or e_out >= 0.999: continue
        cv.save()
        cv.clipRect(skia.Rect.MakeLTRB(left - 60, top + y - 1.05 * size, right + 60, top + y + 0.32 * size))
        baseline = top + y + (1 - e_in) * size * 1.2 - e_out * size * 1.3
        cv.drawTextBlob(blob(word, size), left + x, baseline + font(size).getMetrics().fAscent,
                        paint(ACCENT if accent else WHITE, alpha))
        cv.restore()


def svg_image(path, height):
    dom = skia.SVGDOM.MakeFromStream(skia.Stream.MakeFromFile(str(path)))
    w0, h0 = (float(v) for v in re.search(r'viewBox="[\d.-]+ [\d.-]+ ([\d.]+) ([\d.]+)"', path.read_text()).groups())
    dom.setContainerSize(skia.Size(w0, h0))
    k = height / h0
    surf = skia.Surface(round(w0 * k), round(height))
    c = surf.getCanvas()
    c.scale(k, k)
    dom.render(c)
    return surf.makeImageSnapshot().withDefaultMipmaps()


def pop(cv, image, x, y, w, h, t, t0):
    """Draws an image into (x, y, w, h), springing up from 60 % around its centre."""
    e = spring(t - t0, 0.5, 14)
    if e <= 0.001: return
    cv.save()
    cv.translate(x + w / 2, y + h / 2)
    cv.scale(0.6 + 0.4 * e, 0.6 + 0.4 * e)
    cv.drawImageRect(image, skia.Rect.MakeXYWH(-w / 2, -h / 2, w, h), SAMPLING, paint(WHITE, clamp(2 * e)))
    cv.restore()


def endcard(cv, t):
    """Logo, closing line, call to action and the App Store badge, one after the other from the outro downbeat."""
    card_w = W - 2 * TEXT[0]
    _, _, close_h = layout(A.copy['close'], HEADLINE, card_w, HEADLINE * 3.4, 1.08, 'center')
    _, _, cta_h = layout(A.copy['cta'], BODY, card_w, BODY * 3, 1.32, 'center')
    gaps = LOCKUP * 0.75, HEADLINE * 0.25, BODY * 1.6
    y = 0.47 * H - (LOCKUP + gaps[0] + close_h + gaps[1] + cta_h + gaps[2] + BADGE) / 2
    word_w = A.wordmark.width() * 0.953 * LOCKUP / A.wordmark.height()
    x = (W - LOCKUP - word_w) / 2
    cv.save()  # the icon and the wordmark pop as one lockup
    e = spring(t - at(OUTRO), 0.5, 14)
    cv.translate(W / 2, y + LOCKUP / 2)
    cv.scale(0.6 + 0.4 * e, 0.6 + 0.4 * e)
    cv.translate(-W / 2, -y - LOCKUP / 2)
    a = paint(WHITE, clamp(2 * e))
    if e > 0.001:
        cv.drawImageRect(A.icon, skia.Rect.MakeXYWH(x, y + 0.05 * LOCKUP, 0.9 * LOCKUP, 0.9 * LOCKUP), SAMPLING, a)
        cv.drawImageRect(A.wordmark, skia.Rect.MakeXYWH(x + LOCKUP, y, word_w, 0.953 * LOCKUP), SAMPLING, a)
    cv.restore()
    y += LOCKUP + gaps[0]
    headline(cv, A.copy['close'], ((W - card_w) / 2, y, (W + card_w) / 2, y + close_h), t, at(OUTRO, 12), 3,
             align='center')
    y += close_h + gaps[1]
    headline(cv, A.copy['cta'], ((W - card_w) / 2, y, (W + card_w) / 2, y + cta_h), t, at(OUTRO, 36), 2, size=BODY,
             align='center', leading=1.32, alpha=0.72)
    y += cta_h + gaps[2]
    badge_w = A.badge.width() * BADGE / A.badge.height()
    pop(cv, A.badge, (W - badge_w) / 2, y, badge_w, BADGE, t, at(OUTRO, 60))


# Frame ------------------------------------------------------------------------------------------------------------

def scene(cv, t, layer):
    backdrop(cv, t)
    cv.save()
    cv.translate(*shake(t))
    cv.drawImageRect(layer, skia.Rect.MakeWH(W, H), SAMPLING)
    lifts(cv, t)
    cv.restore()
    for beat, t_in, gap, t_out in HEADLINES:
        if t_in - 1 <= t < t_out + 30: headline(cv, A.copy[beat], TEXT, t, t_in, gap, t_out)
    if t >= at(OUTRO, -4): endcard(cv, t)
    for t0, _, flash in IMPACTS:
        if t >= t0: cv.drawPaint(paint(WHITE, flash * math.exp(-(t - t0) / 3)))
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeRadial(
        skia.Point(W / 2, H / 2), 1300, [argb(BLACK, 0), argb(BLACK, 0.35)], [0.55, 1.0])))


def size(scale):
    """Pixel size of the output; H.264 needs an even width, so a half-size preview gains a column."""
    return 2 * math.ceil(W * scale / 2), round(H * scale)


def frame(i):
    """Frame i, with the 2D motion blurred over a 180 degree shutter. The 3D layer brings its own blur."""
    w, h = size(A.scale)
    buf = np.zeros((h, w, 4), np.uint8)
    cv = skia.Surface(buf).getCanvas()
    layer = skia.Image.open(str(A.layer / f'{i:04d}.png'))
    acc = np.zeros((h, w, 3), np.float32)
    for k in range(A.samples):
        cv.save()
        cv.scale(A.scale, A.scale)
        scene(cv, i + ((k + 0.5) / A.samples - 0.5) * 0.5, layer)
        cv.restore()
        acc += buf[..., :3]
    return np.rint(acc / A.samples).astype(np.uint8)


class A:
    """Per-process assets, filled by init()."""


def init(opts):
    for key, value in opts.items(): setattr(A, key, value)
    A.track = json.loads((A.layer / 'track.json').read_text())
    A.typeface = skia.Typeface.MakeFromFile(str(ROOT / 'scripts/assets/app-store' / CONFIG['font']))
    panels = CONFIG['panels'][A.locale]
    A.copy = {beat: panels[panel][line] for beat, (panel, line) in COPY.items()}
    captures = {screen: skia.Image.open(str(capture(A.captures, A.locale, screen))).toarray()
                for screen, *_ in LIFTS.values()}
    A.boxes = lift_boxes(captures.get)
    A.crops = {}
    for name, (l, t, r, b) in A.boxes.items():  # a margin may run past the capture's edge, so extend its background
        pixels = captures[LIFTS[name][0]]
        canvas = np.empty((pixels.shape[0] + 2 * PAD, pixels.shape[1] + 2 * PAD, 4), np.uint8)
        canvas[:] = (*APP_BG, 255)
        canvas[PAD:-PAD, PAD:-PAD] = pixels
        crop = np.ascontiguousarray(canvas[t + PAD:b + PAD, l + PAD:r + PAD])
        A.crops[name] = skia.Image.fromarray(crop, RGBA).withDefaultMipmaps()
    A.icon = skia.Image.open(str(ROOT / 'marketing/public/brand/tidex-app-icon.png')).withDefaultMipmaps()
    A.wordmark = svg_image(ROOT / 'marketing/public/brand/tidex-wordmark-dark.svg', 2 * LOCKUP)
    badge = 'app-store-no.svg' if A.locale == 'no' else 'app-store-en.svg'
    A.badge = svg_image(ROOT / 'marketing/public/badges' / badge, 2 * BADGE)


# Sound and output -------------------------------------------------------------------------------------------------

def music():
    """The film's music: the bars of EDIT back to back, each cut crossfading into the next over the 25 ms before it,
    so every downbeat keeps its attack."""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(MUSIC), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    track = np.frombuffer(raw, np.float32).reshape(-1, 2)
    out = np.zeros((FRAMES * SR // FPS, 2), np.float32)
    t = np.arange(len(out)) / SR
    fade = 0.025

    def ramp(x): return 0.5 - 0.5 * np.cos(np.pi * np.clip(x, 0, 1))

    start = 0.0
    for i, (bar, bars) in enumerate(EDIT):
        end = start + bars * BAR if bars else t[-1] + 1
        weight = (ramp((t - start + fade) / fade) if i else 1.0) * ramp((end - t) / fade)
        source = np.rint((t - start + BAR0 + bar * BAR) * SR).astype(int)
        keep = (weight > 0) & (source < len(track))
        out[keep] += track[source[keep]] * np.broadcast_to(weight, t.shape)[keep, None]
        start = end
    return out


def bass_pulse(audio):
    """Per frame, how hard the bass hits: 1 when quiet, up to 1.45, with a quick decay like a meter."""
    step = SR // FPS
    low = np.array([np.abs(np.fft.rfft(audio[i * step:(i + 1) * step].mean(1), 2 * step)[:6]).sum()  # under 150 Hz
                    for i in range(FRAMES)])
    for i in range(1, FRAMES): low[i] = max(low[i], 0.8 * low[i - 1])
    return list(1 + 0.45 * np.clip(low / np.percentile(low, 95), 0, 1.2))


def soundtrack(audio, path):
    """The music with the sound effects mixed in, as a 16-bit WAV."""
    mix = audio.copy()
    for frame, name, gain in SFX:
        with wave.open(str(SOUNDS / f'{name}.wav')) as f:
            sound = np.frombuffer(f.readframes(f.getnframes()), '<i2').reshape(-1, 2).astype(np.float32) / 32768 * gain
        i = frame * SR // FPS
        n = min(len(sound), len(mix) - i)
        mix[i:i + n] += sound[:n]
    mix *= min(1.0, 0.97 / np.abs(mix).max())
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(np.rint(mix * 32767).astype('<i2').tobytes())


def loudness(path):
    """Two-pass loudnorm to -16 LUFS: measure the mix, then apply the gain linearly so its dynamics stay intact."""
    log = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', str(path), '-af',
                          'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    m = json.loads(log[log.rindex('{'):log.rindex('}') + 1])
    return (f"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}"
            f":measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}"
            f":linear=true,aresample={SR}")


def main():
    parser = argparse.ArgumentParser(prog='showcase.py')
    parser.add_argument('--preview', action='store_true', help='half size, from the preview 3D layer')
    parser.add_argument('--still', type=int, nargs='+', metavar='FRAME')
    parser.add_argument('--locale', default='en-US')
    parser.add_argument('--captures', default=str(CAPTURES))
    args = parser.parse_args()
    frames = args.still or range(FRAMES)
    folder = layer(args.locale, args.preview)
    missing = [i for i in frames if not (folder / f'{i:04d}.png').exists()]
    if missing: sys.exit(f'{len(missing)} frames of the 3D layer are missing from {folder}; run phone3d.py first.')
    if not MUSIC.exists(): sys.exit(f'Download the music to {MUSIC} first; see the top of this file.')
    audio = music()
    opts = dict(layer=folder, scale=0.5 if args.preview else 1.0, samples=3 if args.preview else 6,
                locale=args.locale, captures=args.captures, pulse=bass_pulse(audio))
    w, h = size(opts['scale'])
    with Pool(max(1, (os.cpu_count() or 2) - 1), initializer=init, initargs=(opts,)) as pool:
        if args.still:
            stills = OUT / 'stills'
            stills.mkdir(parents=True, exist_ok=True)
            shots = pool.map(frame, args.still)
            sheet = np.zeros((math.ceil(len(shots) / 5) * h // 2, min(5, len(shots)) * w // 2, 3), np.uint8)
            for k, (i, shot) in enumerate(zip(args.still, shots)):
                image = skia.Image.fromarray(np.dstack([shot, np.full((h, w, 1), 255, np.uint8)]), RGBA)
                image.save(str(stills / f'{args.locale}-{i:04d}.png'), skia.kPNG)
                small = image.resize(w // 2, h // 2, SAMPLING).toarray()[..., :3]
                sheet[k // 5 * h // 2:(k // 5 + 1) * h // 2, k % 5 * w // 2:(k % 5 + 1) * w // 2] = small
            skia.Image.fromarray(np.dstack([sheet, np.full(sheet.shape[:2] + (1,), 255, np.uint8)]), RGBA).save(
                str(stills / 'contact.png'), skia.kPNG)
            print(f'Wrote {len(shots)} stills and contact.png to {stills}')
            return
        wav = OUT / 'audio.wav'
        soundtrack(audio, wav)
        video = OUT / f'tidex-showcase-{args.locale}{"-preview" if args.preview else ""}.mp4'
        # App Store Connect's app preview specification, encoded like the Remotion cuts in video/scripts/export.sh:
        # H.264 High@4.0 at a constant 11 Mbps (Apple asks for 10 to 12), AAC 256 kbps at 48 kHz, -16 LUFS.
        quality = ['-preset', 'medium', '-crf', '20'] if args.preview else [
            '-preset', 'slow', '-profile:v', 'high', '-level:v', '4.0', '-b:v', '11M', '-minrate', '11M',
            '-maxrate', '11M', '-bufsize', '11M', '-x264-params', 'nal-hrd=cbr', '-g', '60']
        ff = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo',
                               '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-r', str(FPS), '-i', '-', '-i', str(wav),
                               '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', *quality,
                               '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p', '-r', str(FPS),
                               '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
                               '-af', loudness(wav), '-c:a', 'aac', '-b:a', '256k', '-ar', str(SR), '-ac', '2',
                               '-shortest', '-movflags', '+faststart', str(video)], stdin=subprocess.PIPE)
        for i, data in enumerate(pool.imap(frame, frames, chunksize=4)):
            ff.stdin.write(data.tobytes())
            if i % 120 == 0: print(f'frame {i}/{FRAMES}', flush=True)
        ff.stdin.close()
        if ff.wait(): sys.exit('ffmpeg failed')
        print(f'Wrote {video}')


if __name__ == '__main__':
    main()
