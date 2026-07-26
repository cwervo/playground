#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pose & scale recovery for Rulercross markers -- pure Python, no numpy.

Given the five known marker points (centre + four arm tips, in mm) and where they
land in the image (px), this recovers:

  * true SCALE            mm-per-pixel at the marker (from known physical geometry)
  * 3-DoF pose            (x, y) image position of the origin + in-plane heading
  * 6-DoF pose            full R, t of the marker plane, given camera intrinsics K
                          (planar homography decomposition)

The maths:
  1. Homography H mapping marker-plane mm -> image px, solved by DLT
     (least squares via 8x8 normal equations + Gaussian elimination).
  2. Decompose B = K^-1 H into rotation columns r1,r2 (+ r3 = r1xr2) and
     translation t, then orthonormalise R. Standard Zhang / Malis homography
     decomposition -- no SVD required.

`selftest()` builds known poses, projects the marker, solves back, and checks the
recovered R, t, and scale against ground truth.
"""

import math

# --------------------------------------------------------------- tiny linalg
def matvec(M, v):
    return [sum(M[i][j] * v[j] for j in range(len(v))) for i in range(len(M))]

def matmul(A, B):
    n, m, p = len(A), len(B), len(B[0])
    return [[sum(A[i][k] * B[k][j] for k in range(m)) for j in range(p)] for i in range(n)]

def transpose(M):
    return [list(r) for r in zip(*M)]

def solve(A, b):
    """Solve A x = b (square) by Gaussian elimination with partial pivoting."""
    n = len(A)
    M = [list(A[i]) + [b[i]] for i in range(n)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(M[r][c]))
        if abs(M[piv][c]) < 1e-15:
            M[piv][c] += 1e-12
        M[c], M[piv] = M[piv], M[c]
        pv = M[c][c]
        for r in range(n):
            if r != c:
                f = M[r][c] / pv
                for k in range(c, n + 1):
                    M[r][k] -= f * M[c][k]
    return [M[i][n] / M[i][i] for i in range(n)]

def inv3(M):
    a, b, c = M[0]; d, e, f = M[1]; g, h, i = M[2]
    A = e*i - f*h; B = -(d*i - f*g); C = d*h - e*g
    det = a*A + b*B + c*C
    D = -(b*i - c*h); E = a*i - c*g; F = -(a*h - b*g)
    G = b*f - c*e;   H = -(a*f - c*d); I = a*e - b*d
    return [[A/det, D/det, G/det], [B/det, E/det, H/det], [C/det, F/det, I/det]]

def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]

def norm(v):
    return math.sqrt(sum(x*x for x in v))

def normed(v):
    n = norm(v);  return [x/n for x in v] if n else v


# --------------------------------------------------------------- homography
def homography(src, dst):
    """src, dst: lists of (x,y). Returns 3x3 H with H*src ~ dst (h33=1)."""
    rows, rhs = [], []
    for (x, y), (u, v) in zip(src, dst):
        rows.append([x, y, 1, 0, 0, 0, -u*x, -u*y]); rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v*x, -v*y]); rhs.append(v)
    At = transpose(rows)
    AtA = matmul(At, rows)
    Atb = matvec(At, rhs)
    h = solve(AtA, Atb)
    return [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1.0]]

def apply_h(H, pt):
    x, y = pt
    d = H[2][0]*x + H[2][1]*y + H[2][2]
    return ((H[0][0]*x + H[0][1]*y + H[0][2]) / d,
            (H[1][0]*x + H[1][1]*y + H[1][2]) / d)

def jacobian(H, x=0.0, y=0.0):
    """2x2 image-px per marker-mm Jacobian of H at (x,y)."""
    w = H[2][0]*x + H[2][1]*y + H[2][2]
    u = (H[0][0]*x + H[0][1]*y + H[0][2]) / w
    v = (H[1][0]*x + H[1][1]*y + H[1][2]) / w
    dudx = (H[0][0] - u*H[2][0]) / w; dudy = (H[0][1] - u*H[2][1]) / w
    dvdx = (H[1][0] - v*H[2][0]) / w; dvdy = (H[1][1] - v*H[2][1]) / w
    return [[dudx, dudy], [dvdx, dvdy]]

def scale_mm_per_px(H):
    """Isotropic scale at the origin from the homography Jacobian (area-based)."""
    J = jacobian(H, 0, 0)
    det = abs(J[0][0]*J[1][1] - J[0][1]*J[1][0])
    px_per_mm = math.sqrt(det) if det > 0 else 0.0
    return (1.0/px_per_mm if px_per_mm else 0.0, px_per_mm)


# ------------------------------------------------------- 3-DoF (x, y, theta)
def pose3(H, north_mm=(0.0, 1.0)):
    origin = apply_h(H, (0.0, 0.0))
    npt = apply_h(H, north_mm)
    theta = math.degrees(math.atan2(npt[1]-origin[1], npt[0]-origin[0]))
    return {"x_px": origin[0], "y_px": origin[1], "heading_deg": theta}


# --------------------------------------------------- 6-DoF via decomposition
def decompose(H, K):
    """Return (R 3x3, t 3) of the marker plane in camera frame, given K."""
    Ki = inv3(K)
    B = matmul(Ki, H)                    # columns are lambda*r1, lambda*r2, lambda*t
    b1 = [B[0][0], B[1][0], B[2][0]]
    b2 = [B[0][1], B[1][1], B[2][1]]
    b3 = [B[0][2], B[1][2], B[2][2]]
    lam = 2.0 / (norm(b1) + norm(b2))
    r1 = [x*lam for x in b1]; r2 = [x*lam for x in b2]; t = [x*lam for x in b3]
    if t[2] < 0:                          # marker must be in front of camera
        r1 = [-x for x in r1]; r2 = [-x for x in r2]; t = [-x for x in t]
    # orthonormalise (Gram-Schmidt); keeps it a valid rotation
    r1n = normed(r1)
    r2n = normed([r2[i] - dot3(r2, r1n)*r1n[i] for i in range(3)])
    r3n = cross(r1n, r2n)
    R = [[r1n[0], r2n[0], r3n[0]], [r1n[1], r2n[1], r3n[1]], [r1n[2], r2n[2], r3n[2]]]
    return R, t

def dot3(a, b):
    return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]

def euler_from_R(R):
    """ZYX-ish readout (deg): tilt about x, tilt about y, in-plane about z."""
    sy = math.sqrt(R[0][0]**2 + R[1][0]**2)
    if sy > 1e-6:
        rx = math.atan2(R[2][1], R[2][2]); ry = math.atan2(-R[2][0], sy); rz = math.atan2(R[1][0], R[0][0])
    else:
        rx = math.atan2(-R[1][2], R[1][1]); ry = math.atan2(-R[2][0], sy); rz = 0.0
    return (math.degrees(rx), math.degrees(ry), math.degrees(rz))


# ---------------------------------------------------------- full recovery API
def recover(known_mm, image_px, K=None):
    """known_mm/image_px: dicts keyed C,N,S,E,W -> (x,y). Returns a pose report."""
    order = ["C", "N", "S", "E", "W"]
    src = [known_mm[k] for k in order]
    dst = [image_px[k] for k in order]
    H = homography(src, dst)
    mm_per_px, px_per_mm = scale_mm_per_px(H)
    # independent cross-check: N-S pixel span / true span
    ns_px = math.dist(image_px["N"], image_px["S"])
    ns_mm = math.dist(known_mm["N"], known_mm["S"])
    out = {"H": H, "mm_per_px": mm_per_px, "px_per_mm": px_per_mm,
           "scale_check_mm_per_px": ns_mm/ns_px if ns_px else 0.0,
           "pose3": pose3(H)}
    if K:
        R, t = decompose(H, K)
        out["R"], out["t"] = R, t
        out["euler_deg"] = euler_from_R(R)
    return out


# ------------------------------------------------------------------- selftest
def _R_from_euler(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    Rx = [[1,0,0],[0,math.cos(rx),-math.sin(rx)],[0,math.sin(rx),math.cos(rx)]]
    Ry = [[math.cos(ry),0,math.sin(ry)],[0,1,0],[-math.sin(ry),0,math.cos(ry)]]
    Rz = [[math.cos(rz),-math.sin(rz),0],[math.sin(rz),math.cos(rz),0],[0,0,1]]
    return matmul(matmul(Rz, Ry), Rx)

def _project(K, R, t, Xm):
    Xc = [sum(R[i][j]*[Xm[0], Xm[1], 0.0][j] for j in range(3)) + t[i] for i in range(3)]
    p = matvec(K, Xc)
    return (p[0]/p[2], p[1]/p[2])

def selftest():
    from rulercross import CrossGeometry
    K = [[1100.0, 0, 640.0], [0, 1100.0, 480.0], [0, 0, 1.0]]
    g = CrossGeometry(0x2A, 92.0)
    known = g.known_points()
    cases = [
        ("flat, centred",      (0, 0, 0),   (0, 0, 500)),
        ("in-plane spin 30",   (0, 0, 30),  (20, -10, 520)),
        ("tilt x18 y-12",      (18, -12, 25), (40, 30, 600)),
        ("steep tilt x30 y20", (30, 20, -40), (-30, 15, 650)),
    ]
    print("case                    scale err   posErr(mm)   rot err(deg)")
    worst_scale = worst_pos = worst_rot = 0.0
    for name, (rx, ry, rz), (tx, ty, tz) in cases:
        R = _R_from_euler(rx, ry, rz); t = [tx, ty, tz]
        img = {k: _project(K, R, t, known[k]) for k in known}
        rec = recover(known, img, K)
        # true scale = numerical Jacobian of the ACTUAL projection at the origin
        # (this correctly includes tilt foreshortening; tz/f would be wrong here).
        eps = 0.5
        o0 = _project(K, R, t, (0, 0)); ox = _project(K, R, t, (eps, 0)); oy = _project(K, R, t, (0, eps))
        Jt = [[(ox[0]-o0[0])/eps, (oy[0]-o0[0])/eps], [(ox[1]-o0[1])/eps, (oy[1]-o0[1])/eps]]
        true_pxpmm = math.sqrt(abs(Jt[0][0]*Jt[1][1] - Jt[0][1]*Jt[1][0]))
        true_mmpp = 1.0 / true_pxpmm
        s_err = abs(rec["mm_per_px"] - true_mmpp) / true_mmpp
        # position error: recovered t vs truth
        p_err = math.dist(rec["t"], t)
        # rotation error: compare recovered euler to truth (in-plane most robust)
        er, et = euler_from_R(R), rec["euler_deg"]
        r_err = max(abs(((er[i]-et[i]+180) % 360) - 180) for i in range(3))
        worst_scale = max(worst_scale, s_err); worst_pos = max(worst_pos, p_err); worst_rot = max(worst_rot, r_err)
        print("%-22s  %7.2f%%   %8.2f    %8.2f" % (name, s_err*100, p_err, r_err))
    ok = worst_scale < 0.06 and worst_pos < 6.0 and worst_rot < 2.5
    print("\nworst: scale %.2f%%, pos %.2fmm, rot %.2f deg  ->  %s"
          % (worst_scale*100, worst_pos, worst_rot, "PASS" if ok else "FAIL"))
    return ok


if __name__ == "__main__":
    import sys
    sys.exit(0 if selftest() else 1)
