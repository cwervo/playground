"""Shared geometry + PLY I/O for the pano -> Gaussian splat pipeline.

Coordinate system: y up, camera (pano center) at origin, eye height 1.55m
(floor near y = -1.55). Pano assumed cylindrical: theta in [-HFOV/2, +HFOV/2],
theta=0 looks down +z. Direction for pano pixel (px, py):
    theta = (px / W - 0.5) * HFOV
    v     = (H/2 - py) / f_cyl          with f_cyl = W / HFOV  (radians)
    dir   = normalize(sin t, v, cos t)
"""
import json
import os

import numpy as np

HFOV_DEG = 250.0            # estimated horizontal sweep of the phone pano
EYE_HEIGHT = 1.55           # meters, camera above floor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SH_C0 = 0.28209479177387814


def pano_params(W, H):
    hfov = np.deg2rad(HFOV_DEG)
    f_cyl = W / hfov
    return hfov, f_cyl


def pano_dirs(W, H, xs, ys):
    """Unit ray directions for pano pixel coords (xs, ys) (float arrays)."""
    hfov, f_cyl = pano_params(W, H)
    theta = (xs / W - 0.5) * hfov
    v = (H / 2.0 - ys) / f_cyl
    d = np.stack([np.sin(theta), v, np.cos(theta)], axis=-1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    return d


def view_basis(yaw_deg):
    yaw = np.deg2rad(yaw_deg)
    fwd = np.array([np.sin(yaw), 0.0, np.cos(yaw)])
    right = np.array([np.cos(yaw), 0.0, -np.sin(yaw)])
    up = np.array([0.0, 1.0, 0.0])
    return fwd, right, up


def write_ply_xyzrgb(path, pts, rgb):
    """Plain binary point-cloud PLY (positions + uchar colors)."""
    n = len(pts)
    header = (
        "ply\nformat binary_little_endian 1.0\n"
        f"element vertex {n}\n"
        "property float x\nproperty float y\nproperty float z\n"
        "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        "end_header\n"
    )
    rec = np.zeros(n, dtype=[("xyz", "<f4", 3), ("rgb", "u1", 3)])
    rec["xyz"] = pts.astype(np.float32)
    rec["rgb"] = rgb.astype(np.uint8)
    with open(path, "wb") as f:
        f.write(header.encode("ascii"))
        f.write(rec.tobytes())


def write_ply_gaussian(path, pts, normals, rgb, scales, opacity, quats):
    """Standard 3D Gaussian Splatting PLY (SH degree 0).

    scales are linear meters (stored as log), opacity linear 0..1 (stored as
    logit), quats wxyz. Readable by SuperSplat, antimatter15/splat, gsplat.
    """
    n = len(pts)
    props = (
        ["x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2",
         "opacity", "scale_0", "scale_1", "scale_2",
         "rot_0", "rot_1", "rot_2", "rot_3"]
    )
    header = (
        "ply\nformat binary_little_endian 1.0\n"
        f"element vertex {n}\n"
        + "".join(f"property float {p}\n" for p in props)
        + "end_header\n"
    )
    f_dc = (rgb.astype(np.float32) / 255.0 - 0.5) / SH_C0
    op = np.clip(opacity, 1e-4, 1 - 1e-4)
    logit = np.log(op / (1 - op)).astype(np.float32)
    data = np.concatenate(
        [
            pts.astype(np.float32),
            normals.astype(np.float32),
            f_dc,
            logit[:, None],
            np.log(np.clip(scales, 1e-5, None)).astype(np.float32),
            quats.astype(np.float32),
        ],
        axis=1,
    )
    with open(path, "wb") as f:
        f.write(header.encode("ascii"))
        f.write(data.astype("<f4").tobytes())


def read_ply_gaussian(path):
    with open(path, "rb") as f:
        header = b""
        while not header.endswith(b"end_header\n"):
            header += f.readline()
        htxt = header.decode("ascii")
        n = int([l for l in htxt.splitlines() if l.startswith("element vertex")][0].split()[-1])
        nprops = sum(1 for l in htxt.splitlines() if l.startswith("property"))
        data = np.frombuffer(f.read(n * nprops * 4), dtype="<f4").reshape(n, nprops)
    pts = data[:, 0:3]
    normals = data[:, 3:6]
    rgb = np.clip(data[:, 6:9] * SH_C0 + 0.5, 0, 1)
    opacity = 1 / (1 + np.exp(-data[:, 9]))
    scales = np.exp(data[:, 10:13])
    quats = data[:, 13:17]
    return pts, normals, rgb, opacity, scales, quats


def save_meta(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def load_meta(path):
    with open(path) as f:
        return json.load(f)
