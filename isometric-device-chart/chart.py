#!/usr/bin/env python3
"""3-axis isometric (45° axonometric) chart of ESP32 dev boards.

Axes (classic R/G/B axis convention):
  X (red)   — price, USD
  Y (green) — feature count (screen, touch, WiFi, BT, TF slot, charging, ...)
  Z (blue)  — power needs, est. typical active draw in mA

Projection: military axonometric — the XY ground plane is rotated 45° and kept
undistorted (X up-right at exactly +45°, Y up-left at exactly 135°), Z is
vertical. All three axes read at full length, which gives maximum, equal
perception across the three axes. The blue Z axis is drawn on the left corner
of the grid room so it never crosses the data.

Renders a light-mode and a dark-mode PNG.
"""

import math

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
    # name, kind, price $, features, power mA, label offset (dx, dy) in data units
    ("T-Display", "Screen dev board", 18,
     ["1.14″ LCD", "WiFi", "BT", "LiPo charge"], 180, (0.014, -0.024)),
    ("T-Display-S3", "Screen dev board", 23,
     ["1.9″ LCD", "touch", "WiFi", "BLE 5", "LiPo charge"], 210, (0.014, 0.000)),
    ("T-Display S3 Long", "Screen dev board", 32,
     ["3.4″ LCD", "touch", "WiFi", "BLE 5", "LiPo charge"], 260, (0.014, 0.010)),
    ("T-Display-Bar", "Screen dev board", 30,
     ["2.25″ LCD", "touch", "WiFi", "BT", "TF slot", "LiPo charge"], 260, (-0.016, 0.010)),
    ("T-Dongle-S3", "Screen dev board", 19,
     ["0.96″ LCD", "WiFi", "BT", "TF slot", "RGB LED"], 170, (0.014, 0.016)),
    ("T-RGB", "Smart display panel", 37,
     ["2.1″ round IPS", "touch", "WiFi", "BT", "TF slot", "LiPo charge"], 300, (0.014, 0.004)),
    ("T-Panel S3", "Smart display panel", 50,
     ["3.95″ IPS", "touch", "WiFi", "BT", "TF slot", "RS-485"], 450, (0.014, 0.004)),
    ("Feather ESP32-C6", "Headless dev board", 15,
     ["WiFi 6", "BLE 5", "Zigbee/Thread", "LiPo charge", "STEMMA QT", "NeoPixel"], 100, (-0.016, 0.032)),
    ("Metro ESP32-S2", "Headless dev board", 20,
     ["WiFi", "30+ GPIO", "STEMMA QT", "LiPo charge", "NeoPixel"], 140, (0.016, -0.006)),
]

X_MAX, X_TICKS = 55.0, range(0, 60, 10)     # price $
Y_MAX, Y_TICKS = 8.0, range(0, 9, 2)        # feature count
Z_MAX, Z_TICKS = 500.0, range(0, 501, 100)  # power mA

# --- 45° military projection ------------------------------------------------
C45 = math.cos(math.radians(45))
AXIS_LEN = {"x": 1.0, "y": 1.0, "z": 0.85}  # z slightly compressed for framing


def project(x, y, z):
    """Data point -> 2D screen point. Floor axes at exactly ±45°, Z vertical."""
    xn = x / X_MAX * AXIS_LEN["x"]
    yn = y / Y_MAX * AXIS_LEN["y"]
    zn = z / Z_MAX * AXIS_LEN["z"]
    u = (xn - yn) * C45
    v = (xn + yn) * C45 + zn
    return u, v


THEMES = {
    "light": dict(
        surface="#fcfcfb", ink="#0b0b0b", ink2="#52514e", muted="#898781",
        grid="#e1e0d9", pane_alpha=0.55,
        ax_r="#c62828", ax_g="#0a7d0a", ax_b="#1e5fd0",
        pane_x="#fdeaea", pane_y="#e9f4e9", pane_z="#e8eefb",
        halo="#fcfcfb", series=0,
    ),
    "dark": dict(
        surface="#1a1a19", ink="#ffffff", ink2="#c3c2b7", muted="#898781",
        grid="#2c2c2a", pane_alpha=0.45,
        ax_r="#e66767", ax_g="#34b234", ax_b="#5b9bff",
        pane_x="#2a1d1d", pane_y="#1d271d", pane_z="#1d2331",
        halo="#1a1a19", series=1,
    ),
}


def draw(mode):
    t = THEMES[mode]
    fig, ax = plt.subplots(figsize=(10.0, 11.6), dpi=200)
    fig.patch.set_facecolor(t["surface"])
    ax.set_facecolor(t["surface"])
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_xlim(-1.28, 1.28)
    ax.set_ylim(-0.30, 2.62)

    def seg(p0, p1, **kw):
        ax.plot([p0[0], p1[0]], [p0[1], p1[1]], **kw)

    # --- the three grid panes (floor z=0, wall y=0, wall x=0) --------------
    def pane(corners, color):
        ax.fill([c[0] for c in corners], [c[1] for c in corners],
                color=color, alpha=t["pane_alpha"], zorder=0, lw=0)

    O = project(0, 0, 0)
    PX = project(X_MAX, 0, 0)
    PY = project(0, Y_MAX, 0)
    ZTOP = project(0, Y_MAX, Z_MAX)                                   # left corner, top
    pane([O, PX, project(X_MAX, Y_MAX, 0), PY], t["pane_z"])          # floor
    pane([O, PX, project(X_MAX, 0, Z_MAX), project(0, 0, Z_MAX)], t["pane_x"])  # right wall (y=0)
    pane([O, PY, ZTOP, project(0, 0, Z_MAX)], t["pane_y"])            # left wall (x=0)

    gridkw = dict(color=t["grid"], lw=0.7, zorder=1)
    for xv in X_TICKS:                                    # lines along Y and Z at each x
        seg(project(xv, 0, 0), project(xv, Y_MAX, 0), **gridkw)
        seg(project(xv, 0, 0), project(xv, 0, Z_MAX), **gridkw)
    for yv in Y_TICKS:
        seg(project(0, yv, 0), project(X_MAX, yv, 0), **gridkw)
        seg(project(0, yv, 0), project(0, yv, Z_MAX), **gridkw)
    for zv in Z_TICKS:
        seg(project(0, 0, zv), project(X_MAX, 0, zv), **gridkw)
        seg(project(0, 0, zv), project(0, Y_MAX, zv), **gridkw)

    # --- R/G/B axis lines ---------------------------------------------------
    axkw = dict(lw=3.0, zorder=3, solid_capstyle="round")
    seg(O, PX, color=t["ax_r"], **axkw)                   # X — price
    seg(O, PY, color=t["ax_g"], **axkw)                   # Y — features
    seg(PY, ZTOP, color=t["ax_b"], **axkw)                # Z — power, left corner

    # tick labels
    tickkw = dict(fontsize=9, color=t["muted"], zorder=3)
    for xv in X_TICKS:
        u, v = project(xv, 0, 0)
        if xv:
            ax.text(u + 0.018, v - 0.018, f"${xv}", ha="left", va="top", **tickkw)
    for yv in Y_TICKS:
        u, v = project(0, yv, 0)
        if yv:
            ax.text(u - 0.018, v - 0.018, str(yv), ha="right", va="top", **tickkw)
    for zv in Z_TICKS:
        if zv:
            u, v = project(0, Y_MAX, zv)
            ax.text(u - 0.020, v, str(zv), ha="right", va="center", **tickkw)

    # axis titles, colored to match their axis line
    mid_x = project(X_MAX * 0.55, 0, 0)
    ax.text(mid_x[0] + 0.105, mid_x[1] - 0.080, "PRICE (USD)", rotation=45,
            ha="center", va="center", fontsize=12, fontweight="bold",
            color=t["ax_r"], zorder=3)
    mid_y = project(0, Y_MAX * 0.55, 0)
    ax.text(mid_y[0] - 0.105, mid_y[1] - 0.080, "FEATURES (COUNT)", rotation=-45,
            ha="center", va="center", fontsize=12, fontweight="bold",
            color=t["ax_g"], zorder=3)
    mid_z = project(0, Y_MAX, Z_MAX * 0.5)
    ax.text(mid_z[0] - 0.135, mid_z[1], "POWER (mA, EST. ACTIVE)", rotation=90,
            ha="center", va="center", fontsize=12, fontweight="bold",
            color=t["ax_b"], zorder=3)

    # --- data marks ---------------------------------------------------------
    for name, kind, price, features, power, (dx, dy) in DEVICES:
        color = KINDS[kind][0][t["series"]]
        marker = KINDS[kind][1]
        p = project(price, len(features), power)
        floor = project(price, len(features), 0)
        # drop line + floor shadow anchor the point in the ground plane
        seg(floor, p, color=color, lw=1.1, ls=(0, (3, 3)), alpha=0.75, zorder=4)
        ax.plot(*floor, marker=marker, ms=4.5, color=color, alpha=0.55,
                zorder=4, mew=0)
        ax.plot(*p, marker=marker, ms=11, color=color, zorder=6,
                mec=t["surface"], mew=1.6)
        ax.annotate(
            name, p, xytext=(p[0] + dx, p[1] + dy),
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
                    bbox_to_anchor=(1.0, 0.885), bbox_transform=ax.transAxes,
                    fontsize=10, labelcolor=t["ink2"])
    leg.set_zorder(8)

    ax.text(0.0, 0.995, "ESP32 dev boards: price × features × power",
            transform=ax.transAxes, fontsize=16, fontweight="bold",
            color=t["ink"], va="top")
    ax.text(0.0, 0.965,
            "45° axonometric grid · X price (red) · Y feature count (green) · "
            "Z est. active draw (blue)\nDashed drops mark each board's floor "
            "position; prices and draw are approximate.",
            transform=ax.transAxes, fontsize=10, color=t["ink2"], va="top")

    out = f"esp32-isometric-{mode}.png"
    fig.savefig(out, bbox_inches="tight", pad_inches=0.25,
                facecolor=t["surface"])
    plt.close(fig)
    return out


if __name__ == "__main__":
    import os
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    for mode in ("light", "dark"):
        print("wrote", draw(mode))
