"""3D layer of the Tidex showcase: phones and calendar days on a transparent background, rendered in Blender.

showcase.py draws the rest of the film around these frames. Run from the repository root:

  /Applications/Blender.app/Contents/MacOS/Blender -b -P video/blender/phone3d.py -- [options]

  --preview            half size and fewer samples, for quick iterations
  --stills F,F,...     render only these frames
  --track              only write track.json
  --locale en-US       captures for this locale
  --captures DIR       raw captures; default ios/ASConnectScreenshots/<version>/raw-dark

Writes video/blender/out/layer-<locale>/ (-preview/ with --preview): a PNG per frame, and track.json with the on-screen
corners of every lift-out region on every frame. Without -b, Blender opens with the scene built and renders nothing.
"""
import argparse
import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from bpy_extras import anim_utils
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).parent))
from timeline import (CAPTURES, CONFIG, DECIDE, DROP, FPS, FRAMES, H, LAND, OUTRO, OVERVIEW, SUBJECT,  # noqa: E402
                      TRUST, W, at, capture, layer, lift_boxes)

LENS = 100 * (SUBJECT[3] - SUBJECT[1]) / H  # mm on a 24 mm tall sensor: the subject box sees what a 100 mm lens does
APERTURE = 6  # mm, about f/11: everything near the focus is sharp, only things far behind soften

# iPhone 17 Pro Max in millimetres, as in scripts/render-3d-screenshots.mjs.
PHONE_W, PHONE_H, PHONE_D, PHONE_R, EDGE = 78, 163.4, 8.75, 13.5, 1.4
GLASS_W, GLASS_H = PHONE_W - 2 * EDGE, PHONE_H - 2 * EDGE
PX_PER_MM = 460 / 25.4  # 460 ppi, so a 1320 x 2868 capture fills the display exactly
CAPTURE = 1320, 2868
CANVAS = round(GLASS_W * PX_PER_MM), round(GLASS_H * PX_PER_MM)
OFFSET = (CANVAS[0] - CAPTURE[0]) // 2, (CANVAS[1] - CAPTURE[1]) // 2  # capture corner on the glass texture
CELL = 172 / PX_PER_MM, 185 / PX_PER_MM  # one calendar day in the schedule captures, in millimetres
MM = 0.001
TEXTURES = {}

# Easing of the move from a key to the next one.
EASES = {
    'out': ('EXPO', 'EASE_OUT'),  # fast start, soft landing
    'in': ('EXPO', 'EASE_IN'),  # slow start, fast exit
    'accel': ('CUBIC', 'EASE_IN'),
    'linear': ('LINEAR', 'AUTO'),
    'step': ('CONSTANT', 'AUTO'),
}


def hex_rgb(value):
    return tuple(int(value[i:i + 2], 16) / 255 for i in (1, 3, 5))


def linear(rgb):
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)


def link(name, data=None, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent, ob.location, ob.rotation_euler = parent, loc, rot
    return ob


def anim(target, prop, keys):
    """Keys are (frame, value, ease); the ease shapes the move to the next key. `prop` may index, as in 'color[3]'."""
    name, _, index = prop.rstrip(']').partition('[')
    index = int(index) if index else -1
    for frame, value, how in keys:
        if index < 0:
            setattr(target, name, value)
        else:
            getattr(target, name)[index] = value
        target.keyframe_insert(name, index=index, frame=frame)
        data = target.id_data.animation_data
        path = target.path_from_id(name)
        for curve in anim_utils.action_get_channelbag_for_slot(data.action, data.action_slot).fcurves:
            if curve.data_path == path and index in (-1, curve.array_index):
                for point in curve.keyframe_points:
                    if abs(point.co.x - frame) < 1e-3:
                        point.interpolation, point.easing = EASES[how]


def move(ob, keys):
    """Keys are (frame, location, rotation in degrees, ease)."""
    anim(ob, 'location', [(f, loc, how) for f, loc, rot, how in keys])
    anim(ob, 'rotation_euler', [(f, [math.radians(a) for a in rot], how) for f, loc, rot, how in keys])


def visible(objects, start, end):
    """Renders the objects and their parts only from `start` up to `end`."""
    for ob in objects:
        for part in [ob, *ob.children_recursive]:
            for frame, hidden in ((0, True), (start, False), (end, True)):
                part.hide_render = hidden
                part.keyframe_insert('hide_render', frame=frame)


def alpha(ob, keys):
    for part in [ob, *ob.children_recursive]:
        anim(part, 'color[3]', keys)


# Materials ------------------------------------------------------------------------------------------------------

def principled(name, color, inputs, fading=False):
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*linear(hex_rgb(color)), 1)
    for slot, value in inputs.items():
        bsdf.inputs[slot].default_value = value
    if fading:
        m.node_tree.links.new(m.node_tree.nodes.new('ShaderNodeObjectInfo').outputs['Alpha'], bsdf.inputs['Alpha'])
        m.use_transparent_shadow = True
    return m


def flat(name, rgb):
    """Unlit colour (linear rgb), faded by the object's alpha."""
    m = bpy.data.materials.new(name)
    tree = m.node_tree
    tree.nodes.clear()
    emit = tree.nodes.new('ShaderNodeEmission')
    emit.inputs['Color'].default_value = (*rgb, 1)
    mix = tree.nodes.new('ShaderNodeMixShader')
    tree.links.new(tree.nodes.new('ShaderNodeObjectInfo').outputs['Alpha'], mix.inputs[0])
    tree.links.new(tree.nodes.new('ShaderNodeBsdfTransparent').outputs[0], mix.inputs[1])
    tree.links.new(emit.outputs[0], mix.inputs[2])
    tree.links.new(mix.outputs[0], tree.nodes.new('ShaderNodeOutputMaterial').inputs[0])
    return m


def capture_pixels(screen):
    """The capture as an H x W x 3 array of 0 to 1 values, top row first."""
    path = capture(args.captures, args.locale, screen)
    source = bpy.data.images.load(str(path))
    if tuple(source.size) != CAPTURE:
        raise SystemExit(f'Wrong capture size: {path}')
    pixels = np.empty(CAPTURE[0] * CAPTURE[1] * 4, np.float32)
    source.pixels.foreach_get(pixels)
    bpy.data.images.remove(source)
    return pixels.reshape(CAPTURE[1], CAPTURE[0], 4)[::-1, :, :3]


def screen_texture(screen):
    """The capture as scripts/render-3d-screenshots.mjs draws it on the glass: rounded display corners on a black
    border, the Dynamic Island and a faint glare. The capture pixels themselves are not changed."""
    if screen in TEXTURES:
        return TEXTURES[screen]
    w, h = CAPTURE
    cw, ch = CANVAS
    y, x = np.mgrid[0:ch, 0:cw] + 0.5

    def inside(left, top, width, height, r):  # anti-aliased coverage of a rounded rectangle
        qx = np.abs(x - left - width / 2) - width / 2 + r
        qy = np.abs(y - top - height / 2) - height / 2 + r
        d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
        return np.clip(0.5 - d, 0, 1)[..., None]

    ox, oy = OFFSET
    canvas = np.empty((ch, cw, 3), np.float32)
    canvas[:] = np.array(hex_rgb('#030304'))
    placed = canvas.copy()
    placed[oy:oy + h, ox:ox + w] = capture_pixels(screen)
    display = inside(ox, oy, w, h, 186)
    canvas = placed * display + canvas * (1 - display)
    canvas *= 1 - inside(cw / 2 - 189, oy + 33, 378, 111, 55.5)  # Dynamic Island
    t = (x * cw + y * 0.6 * ch) / (cw ** 2 + (0.6 * ch) ** 2)  # glare runs from the top left corner
    glare = np.where(t < 0.46, np.interp(t, [0, 0.46], [0x14 / 255, 0x05 / 255]), 0)[..., None]
    canvas = canvas * (1 - glare) + glare
    image = bpy.data.images.new(f'screen {screen}', cw, ch)
    image.pixels.foreach_set(np.concatenate([canvas, np.ones((ch, cw, 1))], axis=2)[::-1].astype(np.float32).ravel())
    TEXTURES[screen] = image
    return image


def screen_material(name, shots):
    """Glass that switches to each (frame, screen) in turn."""
    m = bpy.data.materials.new(name)
    tree = m.node_tree
    bsdf = tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
    bsdf.inputs['Roughness'].default_value = 0.12
    bsdf.inputs['Specular IOR Level'].default_value = 0.4
    bsdf.inputs['Emission Strength'].default_value = 1
    color = None
    for frame, screen in shots:
        tex = tree.nodes.new('ShaderNodeTexImage')
        tex.image = screen_texture(screen)
        tex.extension = 'EXTEND'
        if color is None:
            color = tex.outputs['Color']
            continue
        mix = tree.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        tree.links.new(color, mix.inputs[6])  # A and B of the colour variant
        tree.links.new(tex.outputs['Color'], mix.inputs[7])
        anim(mix.inputs[0], 'default_value', [(0, 0, 'step'), (frame, 1, 'step')])
        color = mix.outputs[2]
    tree.links.new(color, bsdf.inputs['Emission Color'])
    return m



# Geometry -------------------------------------------------------------------------------------------------------

def outline(w, h, r, segments=16):
    """Rounded rectangle with quadratic corners, like the three.js phone. Counter-clockwise."""
    x, y, points = w / 2, h / 2, []
    for p0, c, p1 in (((x - r, -y), (x, -y), (x, -y + r)), ((x, y - r), (x, y), (x - r, y)),
                      ((-x + r, y), (-x, y), (-x, y - r)), ((-x, -y + r), (-x, -y), (-x + r, -y))):
        for i in range(segments + 1):
            t = i / segments
            points.append(tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * e for a, b, e in zip(p0, c, p1)))
    return points


def slab(name, w, h, r, depth, edge, parent, material, z=0.0, segments=16):
    """Rounded plate of w x h x depth mm whose edges are rounded with radius `edge`."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions, cu.fill_mode = '2D', 'BOTH'
    points = outline((w - 2 * edge) * MM, (h - 2 * edge) * MM, (r - edge) * MM, segments)
    spline = cu.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for point, (px, py) in zip(spline.points, points):
        point.co = (px, py, 0, 1)
    spline.use_cyclic_u = spline.use_smooth = True
    cu.extrude, cu.bevel_depth, cu.bevel_resolution = (depth / 2 - edge) * MM, edge * MM, 6
    cu.materials.append(material)
    return link(name, cu, parent, loc=(0, 0, z * MM))


def face(name, w, h, r, z, parent, material):
    """Flat rounded rectangle (mm) with UVs spanning it."""
    points = outline(w * MM, h * MM, r * MM, 24)
    me = bpy.data.meshes.new(name)
    me.from_pydata([(px, py, z * MM) for px, py in points], [], [range(len(points))])
    uv = me.uv_layers.new()
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x / (w * MM) + 0.5, co.y / (h * MM) + 0.5)
    me.materials.append(material)
    return link(name, me, parent)


def box(name, size, radius, parent, loc, material):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=[s * MM for s in size], verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    ob = link(name, me, parent, loc=[c * MM for c in loc])
    bevel = ob.modifiers.new('round', 'BEVEL')
    bevel.width, bevel.segments = radius * MM, 4
    return ob


def on_glass(px, py, lift=0.0):
    """Point in phone model space (metres) over capture pixel (px, py), `lift` mm above the glass."""
    return Vector((((px + OFFSET[0]) / PX_PER_MM - GLASS_W / 2) * MM,
                   (GLASS_H / 2 - (py + OFFSET[1]) / PX_PER_MM) * MM, (PHONE_D / 2 + lift) * MM))


def phone(name, shots, mats):
    """Returns the rig to animate and the model inside it: x across, y up the phone, z out of the screen."""
    rig = link(name)
    model = link(f'{name} model', parent=rig, rot=(math.pi / 2, 0, 0))
    slab(f'{name} frame', PHONE_W, PHONE_H, PHONE_R, PHONE_D, EDGE, model, mats['titanium'], segments=24)
    face(f'{name} glass', GLASS_W, GLASS_H, PHONE_R - EDGE, PHONE_D / 2 + 0.05, model,
         screen_material(f'{name} screen', shots))
    for side, from_top, length, material in ((-1, 31, 7, 'titanium'), (-1, 46, 13, 'titanium'),
                                             (-1, 62, 13, 'titanium'), (1, 50, 19, 'titanium'),
                                             (1, 112, 17, 'sapphire')):
        inset = 0.1 + (0.4 if material == 'sapphire' else 0)
        box(f'{name} button', (1.4, length, 2.6), 0.6, model,
            (side * (PHONE_W / 2 - inset), PHONE_H / 2 - from_top, 0), mats[material])
    return rig, model


def label(body, size, parent, loc, material, align='CENTER', leading=1.0):
    """Tile text. Sizes and positions in mm."""
    cu = bpy.data.curves.new('label', 'FONT')
    cu.font, cu.body, cu.size = FONT, body, size * MM
    cu.align_x, cu.align_y, cu.space_line = align, 'CENTER', leading
    cu.materials.append(material)
    return link(f'label {body}', cu, parent, loc=[c * MM for c in loc])


def day(number, parent, mats, selected=False):
    """A calendar day with a 09:00 to 17:00 shift, drawn after the schedule screen's day cells."""
    rig = link(f'day {number}', parent=parent)
    w, h = CELL
    if selected:
        slab('border', w + 0.7, h + 0.7, 1.75, 0.8, 0.2, rig, mats['border'])
        slab('fill', w, h, 1.4, 0.7, 0.2, rig, mats['selected'], z=0.1)
    else:
        slab('fill', w, h, 1.4, 0.8, 0.2, rig, mats['cell'])
    label(str(number), 3.6, rig, (w / 2 - 0.8, h / 2 - 1.25, 0.46), mats['white'], align='RIGHT')
    label('09:00\n17:00', 4.6, rig, (0, -1.35, 0.46), mats['white'], leading=0.64)
    return rig


# Scene ----------------------------------------------------------------------------------------------------------

def build():
    global FONT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.resolution_percentage = 50 if args.preview else 100
    scene.render.fps, scene.frame_start, scene.frame_end = FPS, 0, FRAMES - 1
    scene.render.engine = 'BLENDER_EEVEE'
    scene.eevee.taa_render_samples = 16 if args.preview else 64
    scene.eevee.use_raytracing = True
    scene.render.use_motion_blur = True
    scene.render.motion_blur_shutter = 0.5
    scene.render.film_transparent = True
    bpy.context.preferences.system.anisotropic_filter = 'FILTER_16'  # screens seen at an angle stay crisp
    scene.view_settings.view_transform = 'Standard'  # keeps the captures and brand colours exact
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.compression = 15
    FONT = bpy.data.fonts.load(str(Path(__file__).parents[2] / 'scripts/assets/app-store' / CONFIG['font']))

    mats = {
        'titanium': principled('titanium', CONFIG['finish'], {'Metallic': 1, 'Roughness': 0.32, 'Coat Weight': 0.4}),
        'sapphire': principled('sapphire', '#111318', {'Metallic': 0.2, 'Roughness': 0.1, 'Coat Weight': 1}),
        'cell': principled('cell', '#151d2a', {'Roughness': 0.45, 'Coat Weight': 0.3}, fading=True),
        'selected': principled('selected', '#0b1833', {'Roughness': 0.45, 'Coat Weight': 0.3}, fading=True),
        'border': principled('border', '#2563eb', {'Roughness': 0.4}, fading=True),
        'white': flat('white', (1, 1, 1)),
    }
    glow = mats['border'].node_tree.nodes['Principled BSDF'].inputs
    glow['Emission Color'].default_value = (*linear(hex_rgb('#2563eb')), 1)
    # The selected day's border flashes as it lands, in the hook and on the phone.
    anim(glow['Emission Strength'], 'default_value', [(0, 0.5, 'step'), (at(6), 8, 'out'), (at(6, 14), 0.5, 'step'),
                                                      (at(LAND), 8, 'out'), (at(LAND, 14), 0.5, 'linear')])

    # Camera. The subject box always spans the angle a 100 mm lens gives on a 24 mm sensor.
    left, top, right, bottom = SUBJECT
    cam = bpy.data.cameras.new('camera')
    cam.sensor_fit, cam.sensor_height, cam.lens = 'VERTICAL', 24, LENS
    cam.shift_x, cam.shift_y = (W / 2 - (left + right) / 2) / H, ((top + bottom) / 2 - H / 2) / H  # in frame heights
    cam.clip_start, cam.clip_end = 0.01, 50
    camera = link('camera', cam)
    aim = link('aim')
    track = camera.constraints.new('TRACK_TO')
    track.target, track.track_axis, track.up_axis = aim, 'TRACK_NEGATIVE_Z', 'UP_Y'
    cam.dof.use_dof, cam.dof.aperture_fstop = True, LENS / APERTURE
    scene.camera = camera

    # Studio light for the titanium: a dim blue room, a soft key and two blue rims.
    world = bpy.data.worlds.new('studio')
    scene.world = world
    tree = world.node_tree
    sep = tree.nodes.new('ShaderNodeSeparateXYZ')
    tree.links.new(tree.nodes.new('ShaderNodeTexCoord').outputs['Generated'], sep.inputs[0])
    height = tree.nodes.new('ShaderNodeMath')
    height.operation = 'MULTIPLY_ADD'
    tree.links.new(sep.outputs['Z'], height.inputs[0])
    height.inputs[1].default_value = height.inputs[2].default_value = 0.5
    ramp = tree.nodes.new('ShaderNodeValToRGB')
    tree.links.new(height.outputs[0], ramp.inputs[0])
    ramp.color_ramp.elements.new(0.5)
    ramp.color_ramp.elements.new(0.75)
    for element, (position, color) in zip(ramp.color_ramp.elements,
                                     ((0, '#020308'), (0.5, '#0c1024'), (0.75, '#26305c'), (1, '#4a5a8c'))):
        element.position, element.color = position, (*linear(hex_rgb(color)), 1)
    tree.links.new(ramp.outputs['Color'], tree.nodes['Background'].inputs['Color'])
    for name, energy, color, size, loc in (('key', 90, '#ffffff', (0.9, 0.9), (-0.8, -1.0, 0.9)),
                                           ('rim right', 120, '#5b86ff', (0.25, 1.4), (0.75, 0.55, 0.25)),
                                           ('rim left', 60, '#8fb0ff', (0.25, 1.4), (-0.8, 0.5, 0.1)),
                                           ('top', 30, '#ffffff', (1.2, 0.6), (0.1, -0.2, 1.1))):
        light = bpy.data.lights.new(name, 'AREA')
        light.energy, light.color, light.shape = energy, linear(hex_rgb(color)), 'RECTANGLE'
        light.size, light.size_y = size
        ob = link(name, light, loc=loc)
        ob.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()

    # Hook: two days with the same shift slam in on the first beats and the extra one flies in from behind on beat 6,
    # clear of the headline, then all three blast past the camera into the drop.
    row = link('week', rot=(math.pi / 2, 0, 0))  # square to the camera, so the gaps read as even
    days = {number: day(number, row, mats, selected=number == 29) for number in (28, 29, 30)}
    for rig in days.values():
        rig.scale = (3.2,) * 3
    step = 0.037  # metres between day centres
    move(days[28], [(at(0), (-0.20, 0.02, 0.05), (0, -90, 15), 'out'), (at(0, 12), (-step, 0, 0), (0, 0, 0), 'linear'),
                    (at(DROP - 1), (-step - 0.002, 0, 0.003), (0, 2, 0), 'in'),
                    (at(DROP, -1), (-0.11, 0.03, 0.30), (20, -30, 30), 'linear')])
    move(days[30], [(at(1), (0.20, -0.02, 0.05), (0, 90, -15), 'out'), (at(1, 12), (step, 0, 0), (0, 0, 0), 'linear'),
                    (at(DROP - 1), (step + 0.002, 0, 0.003), (0, -2, 0), 'in'),
                    (at(DROP, -1), (0.12, -0.04, 0.30), (-15, 30, -25), 'linear')])
    move(days[29], [(at(6, -12), (0, -0.02, -0.30), (-30, 0, 20), 'accel'), (at(6), (0, 0, 0), (0, 0, 0), 'linear'),
                    (at(DROP - 1), (0, 0, 0.003), (0, 0, 0), 'in'),
                    (at(DROP, -1), (0.01, 0.09, 0.32), (30, 0, 5), 'linear')])
    for number, start in ((28, at(0)), (30, at(1)), (29, at(6, -12))):
        visible([days[number]], start, at(DROP))

    # The phone spins in back first on the drop and flips to change screens. Every switch but the one under the
    # landing day falls in the frames where the back faces the camera, two frames into a flip.
    hero, hero_model = phone('phone', [(0, '01-home'), (at(DECIDE, 2), '03-schedule'), (at(LAND), '05-add'),
                                       (at(OVERVIEW, 2), '02-statistics'), (at(TRUST, 2), '04-payroll')], mats)
    move(hero, [(at(DROP, -6), (0, 0.22, -0.05), (-10, 0, -526), 'out'),
                (at(DROP, 22), (0, 0, 0), (-4, 0, 14), 'linear'),
                (at(DECIDE), (0, 0, 0.004), (-4, 0, 4), 'out'), (at(DECIDE, 22), (0, 0, 0.004), (-3, 0, 348), 'linear'),
                (at(OVERVIEW), (0, 0, 0.004), (-3, 0, 354), 'out'),
                (at(OVERVIEW, 22), (0, -0.012, 0), (-3, 0, 720), 'linear'),
                (at(TRUST), (0, -0.012, 0), (-3, 0, 724), 'out'), (at(TRUST, 22), (0, 0, 0), (-6, 0, 352), 'linear'),
                (at(OUTRO - 1), (0, 0, 0.004), (-6, 0, 356), 'in'),
                (at(OUTRO), (0, 0.12, -0.45), (40, 0, 400), 'linear')])
    visible([hero], at(DROP, -6), at(OUTRO, 1))

    # The extra shift sweeps in, hangs for a moment and slams onto the 29th, and the screen becomes the add screen
    # with the new total. The day then fades to show the cell underneath, which now reads 160.
    extra = day(29, hero_model, mats, selected=True)
    landing = on_glass(293, 1661.5, lift=0.45)
    move(extra, [(at(LAND - 3), landing + Vector((0.20, 0.14, 0.20)), (-60, 50, -40), 'out'),
                 (at(LAND - 1), landing + Vector((0.06, 0.05, 0.08)), (-30, 25, -15), 'accel'),
                 (at(LAND), landing, (0, 0, 0), 'linear')])
    anim(extra, 'scale', [(at(LAND - 3), (3.2,) * 3, 'out'), (at(LAND - 1), (2.6,) * 3, 'accel'),
                          (at(LAND), (1,) * 3, 'linear')])
    alpha(extra, [(at(LAND), 1, 'out'), (at(LAND, 10), 0, 'linear')])
    visible([extra], at(LAND - 3), at(LAND, 11))

    # Every job in one overview: two more phones fly in on the beats either side of the hero.
    for name, screen, side, beat in (('schedule phone', '03-schedule', -1, OVERVIEW + 1),
                                     ('home phone', '01-home', 1, OVERVIEW + 2)):
        rig, _ = phone(name, [(0, screen)], mats)
        move(rig, [(at(beat), (side * 0.34, 0.10, 0.02), (-3, 0, -side * 70), 'out'),
                   (at(beat, 20), (side * 0.058, 0.06, 0), (-3, 0, -side * 24), 'linear'),
                   (at(TRUST), (side * 0.060, 0.06, 0), (-3, 0, -side * 20), 'in'),
                   (at(TRUST, 14), (side * 0.40, 0.12, 0.02), (-3, 0, -side * 70), 'linear')])
        visible([rig], at(beat), at(TRUST, 15))

    # Camera: (frame, aim, distance, yaw, pitch, ease of the move to the next shot). It never stops moving.
    def screen_at(px, py, frame):
        scene.frame_set(frame)
        return hero_model.matrix_world @ on_glass(px, py)

    week, centre, trio, above = Vector((0, 0, 0)), Vector((0, 0, 0)), Vector((0, 0.03, 0)), Vector((0, 0, 0.12))
    shots = [
        (at(0), week, 0.78, -8, 6, 'linear'), (at(DROP - 1), week, 0.68, 6, 3, 'accel'),
        (at(DROP, -2), week, 0.54, 6, 3, 'out'), (at(DROP, 20), centre, 0.88, -6, 3, 'linear'),
        (at(DECIDE, -4), centre, 0.80, 8, 3, 'linear'), (at(LAND - 3), centre, 0.72, -10, 4, 'linear'),
        (at(LAND), centre, 0.64, -6, 4, 'linear'), (at(OVERVIEW, -2), centre, 0.62, -8, 4, 'out'),
        (at(OVERVIEW, 20), trio, 1.20, -12, 4, 'linear'), (at(TRUST, -4), trio, 1.14, 10, 4, 'out'),
        (at(TRUST, 20), centre, 0.86, 6, 4, 'linear'),
        (at(OUTRO - 1), screen_at(660, 1130, at(OUTRO - 1)), 0.68, -4, 3, 'in'),
        (at(OUTRO), above, 0.80, 0, -10, 'linear'), (FRAMES - 1, above, 0.78, 0, -8, 'linear'),
    ]
    for frame, target, distance, yaw, pitch, how in shots:
        yaw, pitch = math.radians(yaw), math.radians(pitch)
        offset = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
        anim(aim, 'location', [(frame, target, how)])
        anim(camera, 'location', [(frame, target + distance * offset, how)])

    # Focus on whatever is in front, not on where the camera aims: the row of days in the hook, halfway between the
    # extra day and the screen while it flies onto the phone, and the phone's screen the rest of the time.
    for frame in range(FRAMES):
        scene.frame_set(frame)
        if frame < at(DROP):
            subject = row.matrix_world.translation
        else:
            subject = hero_model.matrix_world @ on_glass(CAPTURE[0] / 2, CAPTURE[1] / 2)
            if at(LAND - 3) <= frame < at(LAND):
                subject = (subject + extra.matrix_world.translation) / 2
        view = camera.matrix_world
        depth = (subject - view.translation).dot(-view.col[2].xyz.normalized())
        anim(cam.dof, 'focus_distance', [(frame, depth, 'linear')])
    return scene, camera, hero_model


def corners(scene, camera, model):
    """Where each lift-out card's corners (top left, top right, bottom right, bottom left) land on screen, in
    full-size pixels, for every frame."""
    boxes = lift_boxes(lambda screen: capture_pixels(screen) * 255)
    track = {name: [] for name in boxes}
    for frame in range(FRAMES):
        scene.frame_set(frame)
        for name, (left, top, right, bottom) in boxes.items():
            points = []
            for px, py in ((left, top), (right, top), (right, bottom), (left, bottom)):
                v = world_to_camera_view(scene, camera, model.matrix_world @ on_glass(px, py))
                points += [round(v.x * W, 2), round((1 - v.y) * H, 2)]
            track[name].append(points)
    return track


parser = argparse.ArgumentParser(prog='phone3d.py')
parser.add_argument('--preview', action='store_true')
parser.add_argument('--stills', type=lambda value: [int(f) for f in value.split(',')])
parser.add_argument('--track', action='store_true')
parser.add_argument('--locale', default='en-US')
parser.add_argument('--captures', type=Path, default=CAPTURES)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

scene, camera, model = build()
folder = layer(args.locale, args.preview)
folder.mkdir(parents=True, exist_ok=True)
(folder / 'track.json').write_text(json.dumps(corners(scene, camera, model)))
scene.frame_set(0)
if bpy.app.background and not args.track:
    started = time.time()
    for frame in args.stills or []:
        scene.frame_set(frame)
        scene.render.filepath = str(folder / f'{frame:04d}.png')
        bpy.ops.render.render(write_still=True)
    if not args.stills:
        scene.render.filepath = f'{folder}/'
        bpy.ops.render.render(animation=True)
    print(f'Rendered the 3D layer in {time.time() - started:.0f} s')
