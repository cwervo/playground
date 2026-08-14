#!/usr/bin/env python3
"""Typography pass over the Blender render (render3d.py).

Reads render.png + anchors.json (projected pixel coordinates exported by the
Blender script) and lays crisp 2D type on top: title, legend, axis titles,
tick numerals, and a fanned label per device sphere. Ink follows the WCMYK
palette: warm white type with a blacK stroke on the sepia ground.

Writes esp32-necker3d.png.
"""

import json
import math
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
import matplotlib.patheffects as pe
from matplotlib.lines import Line2D

HERE = os.path.dirname(os.path.abspath(__file__))
WHITE = "#F7F1E3"
PARCH = "#E4D5B4"      # muted warm ink for ticks/subtitle
INK = "#181008"
KINDS = {
    "Screen dev board": "#EC008C",
    "Smart display panel": "#00AEEF",
    "Headless dev board": "#FFF200",
}
# label fan direction per device (screen px, y down), tuned by eye
FAN = {
    "T-Display": (0.65, 0.76),
    "T-Display-S3": (-1.0, -0.15),
    "T-Display S3 Long": (1.0, -1.0),
    "T-Display-Bar": (-1.0, -0.67),
    "T-Dongle-S3": (0.9, 0.55),
    "T-RGB": (-1.0, -1.0),
    "T-Panel S3": (-1.0, -0.4),
    "Feather ESP32-C6": (-1.0, -0.2),
    "Metro ESP32-S2": (1.0, 0.2),
}

with open(os.path.join(HERE, "anchors.json")) as fh:
    A = json.load(fh)
W, H = A["size"]

img = mpimg.imread(os.path.join(HERE, "render.png"))
fig = plt.figure(figsize=(W / 100, H / 100), dpi=100)
ax = fig.add_axes([0, 0, 1, 1])
ax.imshow(img, extent=[0, W, H, 0])
ax.set_xlim(0, W)
ax.set_ylim(H, 0)
ax.axis("off")

stroke = [pe.withStroke(linewidth=4.5, foreground=INK)]

# --- title & subtitle -------------------------------------------------------
ax.text(48, 78, "ESP32 dev boards: price × features × power",
        fontsize=25, fontweight="bold", color=WHITE, va="center",
        path_effects=stroke)
ax.text(48, 122,
        "Necker cube in one-point perspective, rendered in Blender (Cycles) — "
        "camera just outside the origin corner, aimed at (1,1,1).",
        fontsize=13.5, color=PARCH, va="center")
ax.text(48, 150,
        "1 cm Lambertian spheres in a 10 cm wireframe cube · toon outlines · "
        "WCMYK on sepia · stems drop to the z=0 floor.",
        fontsize=13.5, color=PARCH, va="center")

# --- legend -----------------------------------------------------------------
for i, (kind, color) in enumerate(KINDS.items()):
    y = 250 + i * 46
    ax.plot(1385, y, marker="o", ms=13, color=color, mec=INK, mew=1.6)
    ax.text(1415, y, kind, fontsize=14.5, color=WHITE, va="center",
            path_effects=stroke)

# --- axis titles & ticks ----------------------------------------------------
O = A["axis_ends"]["o"]


def axis_angle(end):
    return -math.degrees(math.atan2(end[1] - O[1], end[0] - O[0]))


ang_x = axis_angle(A["axis_ends"]["x"])
ax.text(1235, 1372, "PRICE (USD)", rotation=(ang_x + 90) % 180 - 90,
        rotation_mode="anchor", ha="center", va="center", fontsize=17,
        fontweight="bold", color=WHITE, path_effects=stroke)
ang_y = axis_angle(A["axis_ends"]["y"])
ax.text(590, 1392, "FEATURES (COUNT)", rotation=(ang_y + 90) % 180 - 90,
        rotation_mode="anchor", ha="center", va="center", fontsize=17,
        fontweight="bold", color=WHITE, path_effects=stroke)
zx, zy = A["axis_ends"]["z"]
ax.text(zx - 42, zy - 6, "POWER (mA, EST. ACTIVE)", ha="right", va="center",
        fontsize=17, fontweight="bold", color=WHITE, path_effects=stroke)

for tv, (x, y) in A["ticks"]["x"].items():
    ax.text(x + 6, y + 34, f"${tv}", ha="center", va="center",
            fontsize=13, color=PARCH)
for tv, (x, y) in A["ticks"]["y"].items():
    ax.text(x - 6, y + 34, tv, ha="center", va="center",
            fontsize=13, color=PARCH)
for tv, (x, y) in A["ticks"]["z"].items():
    ax.text(x + 30, y, tv, ha="left", va="center",
            fontsize=13, color=PARCH)

# --- device labels ----------------------------------------------------------
for name, d in A["devices"].items():
    cx, cy = d["center"]
    dx, dy = FAN[name]
    n = math.hypot(dx, dy)
    dist = d["r_px"] + 14
    lx, ly = cx + dx / n * dist, cy + dy / n * dist
    ax.text(lx, ly, name, ha="left" if dx > 0 else "right", va="center",
            fontsize=14.5, color=WHITE, path_effects=stroke)

out = os.path.join(HERE, "esp32-necker3d.png")
fig.savefig(out, dpi=100)
plt.close(fig)
print("wrote", out)
