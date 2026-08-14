#!/usr/bin/env python3
"""Blender (bpy) render of the Necker-cube device chart.

Real 3D engine pass: the data lives in a 10 cm unit cube; each board is a
1 cm matte Lambertian sphere (diffuse BSDF only) with Freestyle toon
outlines. The cube is a true wireframe of thin ink cylinders with the three
origin axes highlighted as thicker warm-white cylinders. One-point
perspective: camera just outside the origin corner, aimed at (1,1,1), nudged
off the exact diagonal so correlated points don't collapse onto the
vanishing point.

Palette is WCMYK on sepia: process Cyan/Magenta/Yellow for the device kinds,
warm White for the highlighted axes, ink blacK for wireframe + outlines.

Outputs render.png plus anchors.json (projected pixel coordinates of every
labeled thing) for the typography overlay pass (annotate.py).
"""

import json
import math
import os

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

DRAFT = bool(int(os.environ.get("DRAFT", "0")))
OUT = os.path.dirname(os.path.abspath(__file__))

# --- data (same as chart.py) ------------------------------------------------
KINDS = {
    "Screen dev board": "#EC008C",     # process magenta
    "Smart display panel": "#00AEEF",  # process cyan
    "Headless dev board": "#FFF200",   # process yellow
}

DEVICES = [
    ("T-Display", "Screen dev board", 18, 4, 180),
    ("T-Display-S3", "Screen dev board", 23, 5, 210),
    ("T-Display S3 Long", "Screen dev board", 32, 5, 260),
    ("T-Display-Bar", "Screen dev board", 30, 6, 260),
    ("T-Dongle-S3", "Screen dev board", 19, 5, 170),
    ("T-RGB", "Smart display panel", 37, 6, 300),
    ("T-Panel S3", "Smart display panel", 50, 6, 450),
    ("Feather ESP32-C6", "Headless dev board", 15, 6, 100),
    ("Metro ESP32-S2", "Headless dev board", 20, 5, 140),
]

X_MAX, Y_MAX, Z_MAX = 55.0, 8.0, 500.0
X_TICKS = range(10, 60, 10)
Y_TICKS = range(2, 9, 2)
Z_TICKS = range(100, 501, 100)

SEPIA = "#7A5A38"
INK = "#181008"
WHITE = "#F7F1E3"

CUBE = 1.0                     # cube edge = 10 cm
R_SPHERE = 0.05                # 1 cm diameter at that scale
R_AXIS = 0.010
R_WIRE = 0.0042
R_DROP = 0.0022

CAM_POS = Vector((-0.75, -0.55, -0.15))
CAM_AIM = Vector((1.0, 1.0, 1.0))


def norm(price, feats, power):
    return Vector((price / X_MAX, feats / Y_MAX, power / Z_MAX))


def srgb_lin(hexcode):
    out = []
    for i in (0, 2, 4):
        c = int(hexcode.lstrip("#")[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# --- scene ------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24 if DRAFT else 128
scene.cycles.use_denoising = True
scene.render.resolution_x = 850 if DRAFT else 1700
scene.render.resolution_y = 750 if DRAFT else 1500

world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
wbg = world.node_tree.nodes["Background"]
wbg.inputs[0].default_value = srgb_lin(SEPIA)
wbg.inputs[1].default_value = 1.0

# Freestyle toon outlines, ink black, spheres only (the wireframe cylinders
# already read as drawn lines and would just double up)
scene.render.use_freestyle = True
scene.render.line_thickness = 1.6 if DRAFT else 2.6
vl = bpy.context.view_layer
vl.use_freestyle = True
points_col = bpy.data.collections.new("points")
scene.collection.children.link(points_col)
while vl.freestyle_settings.linesets:          # drop the default styleless set
    vl.freestyle_settings.linesets.remove(vl.freestyle_settings.linesets[0])
lineset = vl.freestyle_settings.linesets.new("toon")
lineset.select_silhouette = True
lineset.select_border = True
lineset.select_crease = False
lineset.select_by_collection = True
lineset.collection = points_col
style = bpy.data.linestyles.new("toon-ink")
style.color = srgb_lin(INK)[:3]
style.thickness = 1.6 if DRAFT else 2.6
lineset.linestyle = style


def material(name, hexcode):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")     # pure Lambertian
    diff.inputs["Color"].default_value = srgb_lin(hexcode)
    diff.inputs["Roughness"].default_value = 0.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(diff.outputs["BSDF"], out.inputs["Surface"])
    return m


MATS = {k: material(k, c) for k, c in KINDS.items()}
MAT_INK = material("ink", INK)
MAT_WHITE = material("white", WHITE)


def add_sphere(loc, radius, mat, name):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=radius, segments=48, ring_count=24, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def add_cyl(p0, p1, radius, mat, name):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=d.length, location=(p0 + p1) / 2, vertices=24)
    ob = bpy.context.object
    ob.name = name
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = d.to_track_quat("Z", "Y")
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


# true cube wireframe; origin edges become the highlighted axes
C = [(x, y, z) for x in (0, CUBE) for y in (0, CUBE) for z in (0, CUBE)]
EDGES = [(a, b) for i, a in enumerate(C) for b in C[i + 1:]
         if sum(u != v for u, v in zip(a, b)) == 1]
AXES = {((0, 0, 0), (CUBE, 0, 0)), ((0, 0, 0), (0, CUBE, 0)),
        ((0, 0, 0), (0, 0, CUBE))}
for a, b in EDGES:
    if (a, b) in AXES or (b, a) in AXES:
        add_cyl(a, b, R_AXIS, MAT_WHITE, f"axis-{a}-{b}")
    else:
        add_cyl(a, b, R_WIRE, MAT_INK, f"wire-{a}-{b}")
for c in C:                                     # corner joints
    r = R_AXIS * 1.15 if c == (0, 0, 0) else R_WIRE * 1.6
    m = MAT_WHITE if c == (0, 0, 0) else MAT_INK
    add_sphere(c, r, m, f"joint-{c}")

# tick nubs on the three axes (tiny ink cylinders across the white axis)
for tv in X_TICKS:
    f = tv / X_MAX
    add_cyl((f, 0, 0), (f, 0.030, 0), R_WIRE, MAT_INK, f"tickx{tv}")
for tv in Y_TICKS:
    f = tv / Y_MAX
    add_cyl((0, f, 0), (0.030, f, 0), R_WIRE, MAT_INK, f"ticky{tv}")
for tv in Z_TICKS:
    f = tv / Z_MAX
    add_cyl((0, 0, f), (0.030, 0, f), R_WIRE, MAT_INK, f"tickz{tv}")

# data spheres + drop cylinders + floor discs
for name, kind, price, feats, power, in DEVICES:
    p = norm(price, feats, power)
    sph = add_sphere(p, R_SPHERE, MATS[kind], f"pt-{name}")
    for coll in sph.users_collection:
        coll.objects.unlink(sph)
    points_col.objects.link(sph)
    floor = Vector((p.x, p.y, 0))
    add_cyl(floor, p - Vector((0, 0, R_SPHERE)), R_DROP, MAT_INK, f"drop-{name}")
    disc = add_cyl(floor - Vector((0, 0, 0.001)), floor + Vector((0, 0, 0.002)),
                   R_SPHERE * 0.35, MATS[kind], f"disc-{name}")
    disc.data.materials.clear()
    disc.data.materials.append(MATS[kind])

# --- camera & light ---------------------------------------------------------
bpy.ops.object.camera_add(location=CAM_POS)
cam = bpy.context.object
cam.data.sensor_fit = "HORIZONTAL"
cam.data.angle = math.radians(63)
cam.data.shift_y = 0.05                        # headroom for the title band
aim = bpy.data.objects.new("aim", None)
scene.collection.objects.link(aim)
aim.location = CAM_AIM
tr = cam.constraints.new("TRACK_TO")
tr.target = aim
tr.track_axis = "TRACK_NEGATIVE_Z"
tr.up_axis = "UP_Y"
scene.camera = cam

bpy.ops.object.light_add(type="SUN", location=(-1.0, 0.4, 2.0))
sun = bpy.context.object
sun.data.energy = 3.2
sun.data.angle = math.radians(12)              # soft-ish terminator
sun.rotation_euler = (math.radians(38), math.radians(-28), math.radians(-18))

bpy.context.view_layer.update()

# --- render -----------------------------------------------------------------
scene.render.filepath = os.path.join(OUT, "render.png")
bpy.ops.render.render(write_still=True)

# --- export projected anchors for the typography pass -----------------------
deps = bpy.context.evaluated_depsgraph_get()
W, H = scene.render.resolution_x, scene.render.resolution_y


def px(p):
    ndc = world_to_camera_view(scene, cam, Vector(p))
    return [round(ndc.x * W, 1), round((1 - ndc.y) * H, 1)]


anchors = {
    "size": [W, H],
    "devices": {},
    "ticks": {"x": {}, "y": {}, "z": {}},
    "axis_ends": {"o": px((0, 0, 0)), "x": px((CUBE, 0, 0)),
                  "y": px((0, CUBE, 0)), "z": px((0, 0, CUBE))},
}
for name, kind, price, feats, power in DEVICES:
    p = norm(price, feats, power)
    edge = p + (CAM_POS - p).normalized() * R_SPHERE   # sphere front edge
    anchors["devices"][name] = {
        "kind": kind, "center": px(p),
        "r_px": abs(px(p)[0] - px(p + Vector((R_SPHERE, 0, 0)))[0]),
    }
for tv in X_TICKS:
    anchors["ticks"]["x"][str(tv)] = px((tv / X_MAX, 0, 0))
for tv in Y_TICKS:
    anchors["ticks"]["y"][str(tv)] = px((0, tv / Y_MAX, 0))
for tv in Z_TICKS:
    anchors["ticks"]["z"][str(tv)] = px((0, 0, tv / Z_MAX))

with open(os.path.join(OUT, "anchors.json"), "w") as fh:
    json.dump(anchors, fh, indent=1)
print("wrote render.png and anchors.json")
