"""Frame grid shared by phone3d.py, which renders the 3D layer in Blender, and showcase.py, which draws the rest."""
import json
import re
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / 'scripts/assets/app-store/tidex-3d.json').read_text())
VERSION = re.search(r'^MARKETING_VERSION = (\S+)', (ROOT / 'ios/Version.xcconfig').read_text(), re.M)[1]
CAPTURES = ROOT / 'ios/ASConnectScreenshots' / VERSION / 'raw-dark'
OUT = ROOT / 'video/blender/out'

W, H, FPS = 886, 1920, 30  # App Store Connect's app preview size for every iPhone from 5.8 to 6.9 inches
SUBJECT = 0, 640, W, 1860  # pixel box (left, top, right, bottom) the camera frames the phones in
TEXT = 64, 250, W - 64, 600  # headlines stay in this box, above the phones

# The film is cut to its music on the track's bar lines (see EDIT in showcase.py), so it keeps the track's tempo.
# Times below are beats of the film, counted from its first frame: a two-bar hook, then the drop.
BPM = 240 / 1.90438  # one bar of the track lasts 1.90438 s
BEAT = 60 * FPS / BPM  # frames
DROP, DECIDE, LAND, OVERVIEW, TRUST, OUTRO = 8, 20, 32, 36, 44, 52


def at(beat, frames=0):
    """The frame a beat falls on, plus a number of frames."""
    return round(beat * BEAT + frames)


FRAMES = at(OUTRO) + 96  # the track's closing hit rings for a second, then the end card holds

# Parts of a capture that lift off the phone's glass: screen, a region of the capture that holds the part, the beat it
# rises on and the beat it settles back on. None means it stays up until the phone leaves. The regions are generous,
# because translations run wider; the card itself is fitted to what the region holds (see lift_boxes).
LIFTS = {
    'total': ('01-home', (60, 585, 1260, 1045), DROP + 4, DECIDE - 2),  # After tax in September, $2,240
    'extra': ('05-add', (660, 585, 1310, 670), LAND, OVERVIEW - 1),  # +$160 after tax
    'month': ('05-add', (10, 585, 660, 670), LAND + 1, OVERVIEW - 1),  # $2,400, the month with the extra shift
    'base': ('04-payroll', (10, 648, 1310, 743), TRUST + 4, None),
    'supplement': ('04-payroll', (10, 775, 1310, 870), TRUST + 4.5, None),
    'tax': ('04-payroll', (10, 1388, 1310, 1482), TRUST + 5, None),
    'net': ('04-payroll', (10, 1522, 1310, 1616), TRUST + 5.5, None),
}
STACK = 'base', 'supplement', 'tax', 'net'  # payroll rows that line up as a list
PAD = 40  # capture pixels of margin around a card's content, the same on every side


def capture(folder, locale, screen):
    return Path(folder) / CONFIG['capture'].replace('{locale}', locale).replace('{screen}', screen)


def layer(locale, preview):
    """Folder of the 3D layer's frames for a locale."""
    return OUT / f'layer-{locale}{"-preview" if preview else ""}'


def lift_boxes(load):
    """Card box (left, top, right, bottom) in capture pixels for every lift-out: the content in its region, padded by
    PAD on every side. The payroll rows share their left and right edges. load(screen) gives the capture as an
    H x W x 3 array of 0 to 255 values, top row first."""
    boxes = {}
    for name, (screen, (left, top, right, bottom), *_) in LIFTS.items():
        region = np.asarray(load(screen))[top:bottom, left:right, :3].astype(int)
        ink = np.abs(region - (7, 11, 18)).max(2) > 48  # text and icons; not the faint dividers on the background
        ys, xs = np.nonzero(ink)
        boxes[name] = [left + xs.min() - PAD, top + ys.min() - PAD, left + xs.max() + 1 + PAD, top + ys.max() + 1 + PAD]
    rows = [boxes[name] for name in STACK]
    for box in rows:
        box[0], box[2] = min(b[0] for b in rows), max(b[2] for b in rows)
    return {name: tuple(box) for name, box in boxes.items()}
