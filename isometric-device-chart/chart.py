#!/usr/bin/env python3
"""Necker-cube 3-axis chart of ESP32 dev boards, in true point perspective.

Axes (classic R/G/B axis convention), each normalized onto a unit cube:
  X (red)   — price, USD
  Y (green) — feature count (screen, touch, WiFi, BT, TF slot, charging, ...)
  Z (blue)  — power needs, est. typical active draw in mA

Projection: a pinhole camera just outside the origin corner of the unit cube,
looking along the main diagonal at (1, 1, 1). The far corner projects to the
exact center of the frame; the near corner lands slightly offset — the classic
overlapping-squares Necker cube. The camera sits a touch off the diagonal so
points near the diagonal don't all collapse onto the center pixel. The full
wireframe is drawn (Necker ambiguity); depth is carried by perspective dot
sizing and by each point's dashed drop to the z=0 floor.

Renders a light-mode and a dark-mode PNG.
"""

import math

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patheffects as pe
from matplotlib.lines import Line2D

# --- data -------------------------------------------------------------------
# Prices are street prices in USD at time of writing; power draw is an
# estimate of typical active current (WiFi on, backlight on where present).
# Feature count = len(features) below.

KINDS = {
    # kind: ((color-light, color-dark), marker)
    "Screen dev board": (("#eb6834", "#d95926"), "o"),
    "Smart display panel": (("#1baf7a", "#199e70"), "s"),
    "Headless dev board": (("#4a3aa7", "#9085e9"), "^"),
}

DEVICES = [
    # name, kind, price $, features, power mA, label offset (dx, dy) in screen units
    ("T-Display", "Screen dev board", 18,
     ["1.14″ LCD", "WiFi", "BT", "LiPo charge"], 180, (0.012, -0.014)),
    ("T-Display-S3", "Screen dev board", 23,
     ["1.9″ LCD", "touch", "WiFi", "BLE 5", "LiPo charge"], 210, (-0.013, 0.002)),
    ("T-Display S3 Long", "Screen dev board", 32,
     ["3.4″ LCD", "touch", "WiFi", "BLE 5", "LiPo charge"], 260, (0.010, 0.010)),
    ("T-Display-Bar", "Screen dev board", 30,
     ["2.25″ LCD", "touch", "WiFi", "BT", "TF slot", "LiPo charge"], 260, (-0.012, 0.008)),
    ("T-Dongle-S3", "Screen dev board", 19,
     ["0.96″ LCD", "WiFi", "BT", "TF slot", "RGB LED"], 170, (0.010, -0.002)),
    ("T-RGB", "Smart display panel", 37,
     ["2.1″ round IPS", "touch", "WiFi", "BT", "TF slot", "LiPo charge"], 300, (-0.010, 0.010)),
    ("T-Panel S3", "Smart display panel", 50,
     ["3.95″ IPS", "touch", "WiFi", "BT", "TF slot", "RS-485"], 450, (-0.010, 0.004)),
    ("Feather ESP32-C6", "Headless dev board", 15,
     ["WiFi 6", "BLE 5", "Zigbee/Thread", "LiPo charge", "STEMMA QT", "NeoPixel"], 100, (-0.010, 0.002)),
    ("Metro ESP32-S2", "Headless dev board", 20,
     ["WiFi", "30+ GPIO", "STEMMA QT", "LiPo charge", "NeoPixel"], 140, (0.010, -0.002)),
]

X_MAX, X_TICKS = 55.0, range(10, 60, 10)    # price $
Y_MAX, Y_TICKS = 8.0, range(2, 9, 2)        # feature count
Z_MAX, Z_TICKS = 500.0, range(100, 501, 100)  # power mA

# --- point-perspective camera ----------------------------------------------
# Just outside the origin corner, nudged off the exact diagonal, aimed at
# (1,1,1) so the far corner sits at the center of the frame.
CAM = np.array([-0.75, -0.55, -0.15])
TARGET = np.array([1.0, 1.0, 1.0])


def _unit(a):
    return a / np.linalg.norm(a)


FWD = _unit(TARGET - CAM)
RIGHT = _unit(np.cross(FWD, np.array([0.0, 0.0, 1.0])))
UP = np.cross(RIGHT, FWD)


def project(x, y, z):
    """Data point -> (screen u, screen v, camera depth)."""
    d = np.array([x / X_MAX, y / Y_MAX, z / Z_MAX]) - CAM
    depth = d @ FWD
    return (d @ RIGHT) / depth, (d @ UP) / depth, depth


def P(x, y, z):
    u, v, _ = project(x, y, z)
    return u, v


THEMES = {
    "light": dict(
        surface="#fcfcfb", ink="#0b0b0b", ink2="#52514e", muted="#898781",
        grid="#e1e0d9", edge="#c3c2b7", pane_alpha=0.55,
        ax_r="#c62828", ax_g="#0a7d0a", ax_b="#1e5fd0",
        pane_x="#fdeaea", pane_y="#e9f4e9", pane_z="#e8eefb",
        halo="#fcfcfb", series=0,
    ),
    "dark": dict(
        surface="#1a1a19", ink="#ffffff", ink2="#c3c2b7", muted="#898781",
        grid="#2c2c2a", edge="#383835", pane_alpha=0.45,
        ax_r="#e66767", ax_g="#34b234", ax_b="#5b9bff",
        pane_x="#2a1d1d", pane_y="#1d271d", pane_z="#1d2331",
        halo="#1a1a19", series=1,
    ),
}

CUBE_EDGES = [  # unit-cube corner pairs; the three origin edges carry R/G/B
    ((0, 0, 0), (1, 0, 0)), ((0, 0, 0), (0, 1, 0)), ((0, 0, 0), (0, 0, 1)),
    ((1, 0, 0), (1, 1, 0)), ((1, 0, 0), (1, 0, 1)),
    ((0, 1, 0), (1, 1, 0)), ((0, 1, 0), (0, 1, 1)),
    ((0, 0, 1), (1, 0, 1)), ((0, 0, 1), (0, 1, 1)),
    ((1, 1, 0), (1, 1, 1)), ((1, 0, 1), (1, 1, 1)), ((0, 1, 1), (1, 1, 1)),
]


def corner(cx, cy, cz):
    return P(cx * X_MAX, cy * Y_MAX, cz * Z_MAX)


def draw(mode):
    t = THEMES[mode]
    fig, ax = plt.subplots(figsize=(10.0, 10.8), dpi=200)
    fig.patch.set_facecolor(t["surface"])
    ax.set_facecolor(t["surface"])
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_xlim(-0.68, 0.68)
    ax.set_ylim(-0.52, 0.74)

    def seg(p0, p1, **kw):
        ax.plot([p0[0], p1[0]], [p0[1], p1[1]], **kw)

    # --- far faces (the three meeting at (1,1,1)): tinted panes + grids ----
    def pane(corners, color):
        ax.fill([c[0] for c in corners], [c[1] for c in corners],
                color=color, alpha=t["pane_alpha"], zorder=0, lw=0)

    pane([corner(1, 0, 0), corner(1, 1, 0), corner(1, 1, 1), corner(1, 0, 1)], t["pane_x"])
    pane([corner(0, 1, 0), corner(1, 1, 0), corner(1, 1, 1), corner(0, 1, 1)], t["pane_y"])
    pane([corner(0, 0, 1), corner(1, 0, 1), corner(1, 1, 1), corner(0, 1, 1)], t["pane_z"])

    gridkw = dict(color=t["grid"], lw=0.7, zorder=1)
    for xv in X_TICKS:                       # on faces y=1 and z=1
        seg(P(xv, Y_MAX, 0), P(xv, Y_MAX, Z_MAX), **gridkw)
        seg(P(xv, 0, Z_MAX), P(xv, Y_MAX, Z_MAX), **gridkw)
    for yv in Y_TICKS:                       # on faces x=1 and z=1
        seg(P(X_MAX, yv, 0), P(X_MAX, yv, Z_MAX), **gridkw)
        seg(P(0, yv, Z_MAX), P(X_MAX, yv, Z_MAX), **gridkw)
    for zv in Z_TICKS:                       # on faces x=1 and y=1
        seg(P(X_MAX, 0, zv), P(X_MAX, Y_MAX, zv), **gridkw)
        seg(P(0, Y_MAX, zv), P(X_MAX, Y_MAX, zv), **gridkw)

    # --- Necker wireframe: all 12 edges, R/G/B on the origin edges ---------
    for a, b in CUBE_EDGES:
        seg(corner(*a), corner(*b), color=t["edge"], lw=1.1, zorder=2)
    axkw = dict(lw=3.0, zorder=3, solid_capstyle="round")
    O = corner(0, 0, 0)
    seg(O, corner(1, 0, 0), color=t["ax_r"], **axkw)      # X — price
    seg(O, corner(0, 1, 0), color=t["ax_g"], **axkw)      # Y — features
    seg(O, corner(0, 0, 1), color=t["ax_b"], **axkw)      # Z — power

    # --- ticks & axis titles, offset perpendicular, away from the center ---
    def away(p0, p1, frac, dist):
        """Point at `frac` along p0->p1, pushed `dist` off-axis away from (0,0)."""
        mx, my = (p0[0] + (p1[0] - p0[0]) * frac, p0[1] + (p1[1] - p0[1]) * frac)
        du, dv = p1[0] - p0[0], p1[1] - p0[1]
        n = np.array([dv, -du]) / math.hypot(du, dv)
        if n @ np.array([mx, my]) < 0:
            n = -n
        return (mx + n[0] * dist, my + n[1] * dist), math.degrees(math.atan2(dv, du))

    tickkw = dict(fontsize=9, color=t["muted"], zorder=3)
    ends = {"x": corner(1, 0, 0), "y": corner(0, 1, 0), "z": corner(0, 0, 1)}
    for xv in X_TICKS:
        (u, v), _ = away(O, ends["x"], xv / X_MAX, 0.020)
        ax.text(u, v, f"${xv}", ha="center", va="top", **tickkw)
    for yv in Y_TICKS:
        (u, v), _ = away(O, ends["y"], yv / Y_MAX, 0.020)
        ax.text(u, v, str(yv), ha="center", va="top", **tickkw)
    for zv in Z_TICKS:
        (u, v), _ = away(O, ends["z"], zv / Z_MAX, 0.030)
        ax.text(u, v, str(zv), ha="left", va="center", **tickkw)

    for key, label, color, frac, dist in [
        ("x", "PRICE (USD)", t["ax_r"], 0.62, 0.055),
        ("y", "FEATURES (COUNT)", t["ax_g"], 0.62, 0.055),
    ]:
        (u, v), ang = away(O, ends[key], frac, dist)
        ang = (ang + 90) % 180 - 90          # keep text upright
        ax.text(u, v, label, rotation=ang, rotation_mode="anchor",
                ha="center", va="center", fontsize=11.5, fontweight="bold",
                color=color, zorder=3)
    zu, zv_ = ends["z"]                      # horizontal, beside the axis top
    ax.text(zu - 0.05, zv_ + 0.028, "POWER (mA, EST. ACTIVE)",
            ha="right", va="center", fontsize=11.5, fontweight="bold",
            color=t["ax_b"], zorder=3)

    # --- data marks, far-to-near so nearer points draw on top --------------
    marks = []
    for name, kind, price, features, power, off in DEVICES:
        u, v, depth = project(price, len(features), power)
        marks.append((depth, name, kind, price, features, power, (u, v), off))
    marks.sort(key=lambda m: -m[0])

    for depth, name, kind, price, features, power, (u, v), (dx, dy) in marks:
        color = KINDS[kind][0][t["series"]]
        marker = KINDS[kind][1]
        ms = 21.0 / depth                    # perspective-scaled dot size
        floor = P(price, len(features), 0)
        seg(floor, (u, v), color=color, lw=1.1, ls=(0, (3, 3)), alpha=0.75, zorder=4)
        ax.plot(*floor, marker=marker, ms=ms * 0.4, color=color, alpha=0.55,
                zorder=4, mew=0)
        ax.plot(u, v, marker=marker, ms=ms, color=color, zorder=6,
                mec=t["surface"], mew=1.6)
        ax.annotate(
            name, (u, v), xytext=(u + dx, v + dy),
            ha="left" if dx > 0 else "right", va="center",
            fontsize=9.5, color=t["ink"], zorder=7,
            path_effects=[pe.withStroke(linewidth=2.6, foreground=t["halo"])])

    # --- legend, title ------------------------------------------------------
    handles = [
        Line2D([], [], marker=m, ls="", ms=9, color=colors[t["series"]],
               mec=t["surface"], mew=1.2, label=k)
        for k, (colors, m) in KINDS.items()
    ]
    leg = ax.legend(handles=handles, loc="upper right", frameon=False,
                    bbox_to_anchor=(1.0, 0.90), bbox_transform=ax.transAxes,
                    fontsize=10, labelcolor=t["ink2"])
    leg.set_zorder(8)

    ax.text(0.0, 0.995, "ESP32 dev boards: price × features × power",
            transform=ax.transAxes, fontsize=16, fontweight="bold",
            color=t["ink"], va="top")
    ax.text(0.0, 0.962,
            "Necker cube in one-point perspective — camera just outside the "
            "origin corner, aimed at (1,1,1).\nX price (red) · "
            "Y feature count (green) · Z est. active draw (blue) · nearer "
            "points draw larger; dashed drops hit the z=0 floor.",
            transform=ax.transAxes, fontsize=10, color=t["ink2"], va="top")

    out = f"esp32-necker-{mode}.png"
    fig.savefig(out, bbox_inches="tight", pad_inches=0.25,
                facecolor=t["surface"])
    plt.close(fig)
    return out


if __name__ == "__main__":
    import os
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    for mode in ("light", "dark"):
        print("wrote", draw(mode))
