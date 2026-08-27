"""Step 2b: MiDaS v2.1 small (ONNX) per view, aligned to the room-layout
prior, fused into a pano relief map.

MiDaS outputs affine-invariant inverse depth per view; on textureless walls
its global scale is unreliable, so the layout prior (layout.py) provides the
base geometry and MiDaS provides local relief: each view's disparity is
affine-fit to the prior disparity (robust, positive-scale), and the residual
(relief) is feather-blended into pano space.

Outputs:
  depth/pano_relief.npy  - fused disparity residual (1/m units)
  depth/pano_depth.npy   - refined depth = 1/(prior_disp + relief)
"""
import os

import cv2
import numpy as np
import onnxruntime as ort

from common import ROOT, pano_params, pano_dirs, view_basis, load_meta

FUSE_W, FUSE_H = 2000, 489
MIDAS_SIZE = 256
MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
DEPTH_MIN, DEPTH_MAX = 0.6, 4.5
RELIEF_CLIP = 0.35     # max |relief| in disparity units (1/m)


def run_midas(sess, img_bgr):
    rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    rgb = cv2.resize(rgb, (MIDAS_SIZE, MIDAS_SIZE), interpolation=cv2.INTER_AREA)
    x = ((rgb - MEAN) / STD).transpose(2, 0, 1)[None]
    (out,) = sess.run(None, {sess.get_inputs()[0].name: x})
    return out[0]


def main():
    meta = load_meta(os.path.join(ROOT, "views", "meta.json"))
    W, H = meta["pano_w"], meta["pano_h"]
    f_v = meta["focal_view"]
    vs = meta["view_size"]
    cx = cy = vs / 2.0

    r_prior = np.load(os.path.join(ROOT, "depth", "pano_prior.npy"))
    disp_prior = 1.0 / r_prior

    sess = ort.InferenceSession(os.path.join(ROOT, "depth", "midas_small.onnx"),
                                providers=["CPUExecutionProvider"])

    xs, ys = np.meshgrid(
        (np.arange(FUSE_W) + 0.5) * (W / FUSE_W),
        (np.arange(FUSE_H) + 0.5) * (H / FUSE_H),
    )
    dirs = pano_dirs(W, H, xs, ys)

    relief_acc = np.zeros((FUSE_H, FUSE_W), np.float32)
    wsum = np.zeros((FUSE_H, FUSE_W), np.float32)

    for view in meta["views"]:
        k, yaw = view["idx"], view["yaw_deg"]
        img = cv2.imread(view["file"])
        disp = run_midas(sess, img)
        disp = cv2.resize(disp, (vs, vs), interpolation=cv2.INTER_LINEAR)
        cv2.imwrite(os.path.join(ROOT, "depth", f"disp_{k:02d}.png"),
                    cv2.applyColorMap(
                        cv2.normalize(disp, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8),
                        cv2.COLORMAP_MAGMA))

        fwd, right, up = view_basis(yaw)
        xc = dirs @ right
        yc = dirs @ up
        zc = dirs @ fwd
        valid = zc > 0.05
        u = np.where(valid, f_v * xc / np.maximum(zc, 1e-6) + cx, -1)
        w = np.where(valid, cy - f_v * yc / np.maximum(zc, 1e-6), -1)
        inb = valid & (u >= 8) & (u < vs - 8) & (w >= 8) & (w < vs - 8)

        samp = cv2.remap(disp, u.astype(np.float32), w.astype(np.float32),
                         cv2.INTER_LINEAR, borderValue=0)
        samp = samp * np.maximum(zc, 1e-6)  # inverse perspective -> inverse range
        samp[~inb] = 0

        du = 1 - np.abs(u - cx) / cx
        dw = 1 - np.abs(w - cy) / cy
        wt = np.clip(du, 0, 1) * np.clip(dw, 0, 1)
        wt[~inb] = 0

        # robust affine fit of this view's disparity to the prior disparity
        m = wt > 0.1
        s_v = samp[m].astype(np.float64)
        p_v = disp_prior[m].astype(np.float64)
        w_r = np.ones_like(s_v)
        a, b = 1.0, 0.0
        for _ in range(3):
            A = np.stack([s_v, np.ones_like(s_v)], 1) * w_r[:, None]
            sol, *_ = np.linalg.lstsq(A, p_v * w_r, rcond=None)
            a, b = sol
            r = (a * s_v + b) - p_v
            delta = 1.4826 * np.median(np.abs(r)) * 2 + 1e-9
            w_r = np.minimum(1.0, delta / np.maximum(np.abs(r), 1e-12))
        if a <= 0:
            print(f"view {k}: non-positive scale ({a:.4f}), dropping relief")
            continue
        relief = (a * samp + b) - disp_prior
        relief = np.clip(relief, -RELIEF_CLIP, RELIEF_CLIP)
        relief[~inb] = 0
        relief_acc += relief * wt
        wsum += wt
        print(f"view {k}: a={a:.4f} b={b:.4f} relief rms={np.sqrt((relief[m]**2).mean()):.4f}")

    relief_f = np.where(wsum > 1e-3, relief_acc / np.maximum(wsum, 1e-6), 0).astype(np.float32)
    relief_f = cv2.bilateralFilter(relief_f, 7, 0.08, 7)
    np.save(os.path.join(ROOT, "depth", "pano_relief.npy"), relief_f)

    depth = 1.0 / np.clip(disp_prior + relief_f, 1 / DEPTH_MAX, 1 / DEPTH_MIN)
    np.save(os.path.join(ROOT, "depth", "pano_depth.npy"), depth.astype(np.float32))
    print("refined depth range:", depth.min(), depth.max(), "median:", np.median(depth))

    pano_small = cv2.resize(cv2.imread(os.path.join(ROOT, "source", "pano.jpg")),
                            (FUSE_W, FUSE_H))
    dviz = cv2.applyColorMap(
        cv2.normalize(-depth, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8),
        cv2.COLORMAP_MAGMA)
    rviz = cv2.applyColorMap(
        np.clip((relief_f + RELIEF_CLIP) / (2 * RELIEF_CLIP) * 255, 0, 255).astype(np.uint8),
        cv2.COLORMAP_TWILIGHT_SHIFTED)
    both = np.vstack([pano_small, dviz, rviz])
    cv2.putText(both, "refined depth = layout prior + MiDaS relief (bright = near)",
                (12, FUSE_H + 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)
    cv2.putText(both, "MiDaS relief residual (red = pops out, blue = recedes)",
                (12, 2 * FUSE_H + 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)
    cv2.imwrite(os.path.join(ROOT, "renders", "03_depth_refined.jpg"), both)
    print("depth viz written")


if __name__ == "__main__":
    main()
