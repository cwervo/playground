"""Step 1: decompose the cylindrical pano into overlapping pinhole views."""
import os

import cv2
import numpy as np

from common import ROOT, pano_params, view_basis, save_meta

VIEW_FOV_DEG = 60.0
VIEW_SIZE = 704
N_VIEWS = 9


def main():
    pano = cv2.imread(os.path.join(ROOT, "source", "pano.jpg"))
    H, W = pano.shape[:2]
    hfov, f_cyl = pano_params(W, H)

    half = np.rad2deg(hfov) / 2.0
    margin = VIEW_FOV_DEG / 2.0 * 0.75  # let edge views hang slightly past the pano edge
    yaws = np.linspace(-half + margin, half - margin, N_VIEWS)

    f_v = (VIEW_SIZE / 2.0) / np.tan(np.deg2rad(VIEW_FOV_DEG) / 2.0)
    cx = cy = VIEW_SIZE / 2.0

    i, j = np.meshgrid(np.arange(VIEW_SIZE), np.arange(VIEW_SIZE))
    meta = {"pano_w": W, "pano_h": H, "view_size": VIEW_SIZE,
            "view_fov_deg": VIEW_FOV_DEG, "focal_view": f_v, "views": []}

    os.makedirs(os.path.join(ROOT, "views"), exist_ok=True)
    for k, yaw in enumerate(yaws):
        fwd, right, up = view_basis(yaw)
        d = (fwd[None, None] + ((i - cx) / f_v)[..., None] * right[None, None]
             + ((cy - j) / f_v)[..., None] * up[None, None])
        d /= np.linalg.norm(d, axis=-1, keepdims=True)
        theta = np.arctan2(d[..., 0], d[..., 2])
        px = (theta / hfov + 0.5) * W
        v = d[..., 1] / np.sqrt(d[..., 0] ** 2 + d[..., 2] ** 2)
        py = H / 2.0 - v * f_cyl
        view = cv2.remap(pano, px.astype(np.float32), py.astype(np.float32),
                         cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
        out = os.path.join(ROOT, "views", f"view_{k:02d}.jpg")
        cv2.imwrite(out, view, [cv2.IMWRITE_JPEG_QUALITY, 95])
        meta["views"].append({"idx": k, "yaw_deg": float(yaw), "file": out})
        print(f"view {k}: yaw {yaw:+.1f} deg -> {out}")

    save_meta(os.path.join(ROOT, "views", "meta.json"), meta)

    # contact sheet for progress reporting
    thumbs = []
    for k in range(N_VIEWS):
        t = cv2.imread(os.path.join(ROOT, "views", f"view_{k:02d}.jpg"))
        t = cv2.resize(t, (280, 280))
        cv2.putText(t, f"{k}: {yaws[k]:+.0f} deg", (8, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        thumbs.append(t)
    rows = [np.hstack(thumbs[r * 3:(r + 1) * 3]) for r in range(3)]
    cv2.imwrite(os.path.join(ROOT, "renders", "01_decomposed_views.jpg"), np.vstack(rows))
    print("contact sheet written")


if __name__ == "__main__":
    main()
