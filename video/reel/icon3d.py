"""Renders the Tidex app icon as a glass object for the end card of the reel.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python video/reel/icon3d.py
    ... --python video/reel/icon3d.py -- --test   # six preview frames in video/out/reel/icon-test

Writes 180 transparent 800x800 PNG frames (3 s at 60 fps) to video/out/reel/icon/.
The ruler and payslip come from the icon's own layer SVGs in ios/TidexApp/Resources/tidex.icon.
At frame 0 the icon faces the camera flat and is exactly 400 px wide.
"""
import math
import re
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'ios/TidexApp/Resources/tidex.icon/Assets'
TEST = '--test' in sys.argv
OUT = ROOT / 'video/out/reel' / ('icon-test' if TEST else 'icon')
NUM = re.compile(r'[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def arc(p0, p1, r, large, sweep, steps):
    """Points along a circular SVG arc from p0 to p1, excluding p0."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = (x1 - x0) / 2, (y1 - y0) / 2
    d = math.hypot(dx, dy)
    r = max(r, d)
    h = math.sqrt(max(0.0, r * r - d * d)) * (1 if large != sweep else -1)
    cx, cy = (x0 + x1) / 2 - h * dy / d, (y0 + y1) / 2 + h * dx / d
    a0, a1 = math.atan2(y0 - cy, x0 - cx), math.atan2(y1 - cy, x1 - cx)
    da = a1 - a0
    if sweep and da < 0: da += 2 * math.pi
    if not sweep and da > 0: da -= 2 * math.pi
    return [(cx + r * math.cos(a0 + da * k / steps), cy + r * math.sin(a0 + da * k / steps)) for k in range(1, steps + 1)]


def outline(svg, steps=14):
    """The single closed outline of a layer SVG (absolute M, L, Q, A, Z), in icon units: the squircle spans -1..1."""
    tok, pts, i, cmd = NUM.findall(re.search(r' d="([^"]+)"', svg.read_text()).group(1)), [], 0, 'M'

    def n():
        nonlocal i
        i += 1
        return float(tok[i - 1])

    while i < len(tok):
        if tok[i].isalpha():
            cmd, i = tok[i], i + 1
            if cmd == 'Z': break
        if cmd in 'ML':
            pts.append((n(), n()))
        elif cmd == 'Q':
            (x0, y0), x1, y1, x2, y2 = pts[-1], n(), n(), n(), n()
            pts += [((1 - s) ** 2 * x0 + 2 * (1 - s) * s * x1 + s * s * x2, (1 - s) ** 2 * y0 + 2 * (1 - s) * s * y1 + s * s * y2)
                    for s in (k / steps for k in range(1, steps + 1))]
        elif cmd == 'A':
            r, _, _, large, sweep, x, y = (n() for _ in range(7))
            pts += arc(pts[-1], (x, y), r, large, sweep, steps)
    if math.dist(pts[0], pts[-1]) < 1e-6: pts.pop()
    return [((x - 512) / 512 * 0.92, (512 - y) / 512 * 0.92) for x, y in pts]  # the layer groups sit at 0.92 scale


def squircle(n=5.0, count=256):
    pts = []
    for k in range(count):
        a = 2 * math.pi * k / count
        c, s = math.cos(a), math.sin(a)
        pts.append((math.copysign(abs(c) ** (2 / n), c), math.copysign(abs(s) ** (2 / n), s)))
    return pts


def ccw(pts):
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


def srgb(v): return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def material(name, color, rough, coat_rough=0.05, transmission=0.0, glow=0.0):
    m = bpy.data.materials.new(name)
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Coat Weight'].default_value = 1.0
    b.inputs['Coat Roughness'].default_value = coat_rough
    b.inputs['Transmission Weight'].default_value = transmission
    b.inputs['Emission Color'].default_value = (*color, 1)
    b.inputs['Emission Strength'].default_value = glow
    return m


def slab(name, pts, depth, bevel, mat, parent):
    """A filled, extruded and bevelled outline whose back face sits at z = 0 of its parent."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = depth / 2 - bevel
    cu.bevel_depth = bevel
    cu.bevel_resolution = 6
    cu.offset = -bevel  # keep the outline where the SVG puts it
    sp, pts = cu.splines.new('POLY'), ccw(pts)
    sp.points.add(len(pts) - 1)
    for p, (x, y) in zip(sp.points, pts): p.co = (x, y, 0, 1)
    sp.use_cyclic_u = True
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    ob.parent = parent
    ob.location.z = depth / 2
    return ob


def area(name, size, energy, loc, size_y=None):
    lt = bpy.data.lights.new(name, 'AREA')
    lt.energy = energy
    if size_y:
        lt.shape, lt.size, lt.size_y = 'RECTANGLE', size, size_y
    else:
        lt.size = size
    ob = bpy.data.objects.new(name, lt)
    bpy.context.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = ob.location.to_track_quat('Z', 'Y').to_euler()  # aim at the origin
    ob.visible_camera = False
    return ob


def ease_out(x): return 1 - (1 - x) ** 3
def ease_in(x): return x ** 3
def clamp(x): return max(0.0, min(1.0, x))


def pose(f):
    """Rig yaw and pitch in degrees, lift of ruler and payslip in icon units, rig scale, sweep light x."""
    if f <= 30:  # burst apart on the impact
        e = ease_out(f / 30)
        yaw, pitch, lr, lp = -30 * e, 12 * e, 0.75 * e, 0.45 * e
    elif f <= 54:  # drift
        e = (f - 30) / 24
        yaw, pitch, lr, lp = -30 - 4 * math.sin(e * math.pi / 2), 12 - 1.5 * e, 0.75 + 0.05 * e, 0.45 + 0.04 * e
    elif f <= 72:  # snap back together, landing on frame 72
        e = ease_in((f - 54) / 18)
        yaw, pitch, lr, lp = -34 * (1 - e), 10.5 * (1 - e), 0.8 * (1 - e), 0.49 * (1 - e)
    else:  # rest, then a slow float
        w = clamp((f - 96) / 30)
        yaw, pitch, lr, lp = 4 * math.sin(2 * math.pi * (f - 96) / 140) * w, -3 * math.sin(2 * math.pi * (f - 96) / 170) * w, 0.0, 0.0
    scale = 1 + 0.03 * math.sin(math.pi * clamp((f - 72) / 10))  # the click
    sweep = -2.4 + 5.4 * clamp((f - 78) / 40)
    return yaw, pitch, lr, lp, scale, sweep


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for d in prefs.devices: d.use = d.type == 'METAL'
    scene.cycles.device = 'GPU'
    scene.cycles.samples = 32 if TEST else 48
    scene.cycles.adaptive_threshold = 0.02
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.fps = 60
    scene.render.use_motion_blur = True
    scene.render.use_persistent_data = True
    scene.render.motion_blur_shutter = 0.5
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'  # keep the brand blue as authored
    scene.view_settings.exposure = -1.3  # lands the lit base on the icon's #2563EB
    scene.frame_start, scene.frame_end = 0, 179

    world = bpy.data.worlds.new('studio')
    scene.world = world
    nt = world.node_tree
    env = nt.nodes.new('ShaderNodeTexEnvironment')
    env.image = bpy.data.images.load(str(Path(bpy.utils.system_resource('DATAFILES')) / 'studiolights/world/studio.exr'))
    bg = nt.nodes['Background']
    nt.links.new(env.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 0.55

    cam = bpy.data.objects.new('camera', bpy.data.cameras.new('camera'))
    bpy.context.collection.objects.link(cam)
    cam.data.lens, cam.data.sensor_width = 85, 36
    cam.location = (0, 0, 2 * 85 / 18)  # the squircle (2 units wide) fills half the frame
    scene.camera = cam

    rig = bpy.data.objects.new('rig', None)
    bpy.context.collection.objects.link(rig)
    blue = material('blue', tuple(srgb(v) for v in (0.145, 0.388, 0.922)), 0.32, 0.06)
    glass = material('glass', (0.86, 0.9, 0.98), 0.24, 0.03, transmission=0.18, glow=0.65)  # frosted white that reads bright under the -1.3 exposure
    base = slab('base', squircle(), 0.16, 0.05, blue, rig)
    base.location.z = -0.08
    ruler = slab('ruler', outline(ASSETS / 'Hour-ruler.svg'), 0.07, 0.012, glass, rig)
    payslip = slab('payslip', outline(ASSETS / 'Payslip.svg'), 0.07, 0.012, glass, rig)
    rest = 0.055  # half the layer depth plus a 0.02 gap above the base

    area('key', 5, 900, (-2.5, 3.5, 6))
    area('fill', 6, 250, (4, -1, 5))
    area('top', 3, 300, (0, 5, 1.2))
    sweep = area('sweep', 0.22, 500, (-2.4, 0, 4), size_y=14)
    sweep.visible_diffuse = False  # only shows up as a reflection

    bpy.context.view_layer.update()
    for ob in (base, ruler, payslip): print(ob.name, tuple(round(v, 4) for v in ob.dimensions))
    assert abs(base.dimensions.x - 2) < 0.01, 'the base must be 2 units wide so it renders at 400 px'

    for f in range(180):
        yaw, pitch, lr, lp, s, sx = pose(f)
        rig.rotation_euler = (math.radians(-pitch), math.radians(yaw), 0)
        rig.scale = (s, s, s)
        ruler.location.z, payslip.location.z = rest + lr, rest + lp
        ruler.rotation_euler.z, payslip.rotation_euler.z = math.radians(-7) * lr / 0.8, math.radians(5) * lp / 0.49  # each layer tilts its own way
        sweep.location.x = sx
        sweep.rotation_euler = (0, math.atan2(sx, 4), math.radians(20))
        for ob, path in ((rig, 'rotation_euler'), (rig, 'scale'), (ruler, 'location'), (payslip, 'location'), (ruler, 'rotation_euler'), (payslip, 'rotation_euler'), (sweep, 'location'), (sweep, 'rotation_euler')):
            ob.keyframe_insert(path, frame=f)

    OUT.mkdir(parents=True, exist_ok=True)
    if TEST:
        for f in (0, 18, 40, 66, 96, 150):
            scene.frame_set(f)
            scene.render.filepath = str(OUT / f'{f:04d}.png')
            bpy.ops.render.render(write_still=True)
    else:
        scene.render.filepath = str(OUT / '####')
        bpy.ops.render.render(animation=True)


main()
