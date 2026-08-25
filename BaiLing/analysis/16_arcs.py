"""Stage 16 - closed-form radial distortion from circular arcs (+ anamorphic k).

Under the one-parameter division model with centre c and parameter L, a straight
world line images as a CIRCLE, and for every such circle with centre (a,b) and
radius R:

        (x0-a)^2 + (y0-b)^2 - R^2 = 1/L        (the same constant for all arcs)

Differencing pairs of arcs linearises in (x0,y0), giving a closed-form solution;
RANSAC over arcs rejects edges that are genuinely curved in the world (grab
rails, spectacle rims, faces).
References: Strand & Hayman (2005); Bukhari & Dailey (2013), JMIV 45:31-45.

The frame is first un-stretched by k (Y = y/k). If the frame is isotropic the
best k is 1; if a square frame was squeezed into 3:4 the best k is 4/3.
"""
import numpy as np

chains = [np.asarray(c, float) for c in np.load('data/chains.npy', allow_pickle=True)]
chains = [c for c in chains if len(c) >= 60]
print('chains:', len(chains))


def taubin(P):
    """Taubin algebraic circle fit - unbiased for short arcs."""
    x, y = P[:, 0], P[:, 1]
    mx, my = x.mean(), y.mean()
    u, v = x - mx, y - my
    z = u * u + v * v
    zm = z.mean()
    Z = np.c_[z - zm, u, v]
    _, _, Vt = np.linalg.svd(Z, full_matrices=False)
    a_, b_, c_ = Vt[-1]
    if abs(a_) < 1e-14:
        return None
    cx, cy = -b_ / (2 * a_), -c_ / (2 * a_)
    R2 = cx * cx + cy * cy + zm
    if R2 <= 0:
        return None
    R = np.sqrt(R2)
    cx += mx
    cy += my
    res = np.hypot(x - cx, y - cy) - R
    return cx, cy, R, res.std()


def arcs_for(k):
    out = []
    for c in chains:
        P = np.c_[c[:, 0], c[:, 1] / k]
        f = taubin(P)
        if f is None:
            continue
        a, b, R, rms = f
        if rms > 1.2 or R > 20000 or R < 40:
            continue
        span = np.linalg.norm(P.max(0) - P.min(0))
        sag = R - np.sqrt(max(R * R - (span / 2) ** 2, 0.0)) if span < 2 * R else R
        if sag < 2.0 or span < 70:
            continue
        out.append((a, b, R, rms, len(c), span, sag))
    return np.array(out)


def solve_center(A):
    q = A[:, 0] ** 2 + A[:, 1] ** 2 - A[:, 2] ** 2
    M, rhs = [], []
    for i in range(len(A)):
        for j in range(i + 1, len(A)):
            M.append([2 * (A[j, 0] - A[i, 0]), 2 * (A[j, 1] - A[i, 1])])
            rhs.append(q[j] - q[i])
    M, rhs = np.array(M), np.array(rhs)
    if len(M) < 2 or np.linalg.matrix_rank(M) < 2:
        return None
    (x0, y0), *_ = np.linalg.lstsq(M, rhs, rcond=None)
    K = np.mean((x0 - A[:, 0]) ** 2 + (y0 - A[:, 1]) ** 2 - A[:, 2] ** 2)
    return x0, y0, K


def ransac(A, iters=6000, tol=6.0, seed=1):
    rng = np.random.default_rng(seed)
    n = len(A)
    if n < 4:
        return None
    best = (0, None, None)
    for _ in range(iters):
        s = rng.choice(n, 3, replace=False)
        r = solve_center(A[s])
        if r is None:
            continue
        x0, y0, K = r
        if not (250 < x0 < 950 and 250 < y0 < 1400):
            continue
        e = np.abs((x0 - A[:, 0]) ** 2 + (y0 - A[:, 1]) ** 2 - A[:, 2] ** 2 - K) / (2 * A[:, 2])
        inl = e < tol
        if inl.sum() > best[0]:
            best = (inl.sum(), (x0, y0, K), inl)
    if best[1] is None:
        return None
    inl = best[2]
    for _ in range(3):
        r = solve_center(A[inl])
        if r is None:
            break
        x0, y0, K = r
        e = np.abs((x0 - A[:, 0]) ** 2 + (y0 - A[:, 1]) ** 2 - A[:, 2] ** 2 - K) / (2 * A[:, 2])
        inl = e < tol
    return (x0, y0, K), inl, e


Rref2 = 800.0 ** 2
print(f'\n{"k":>7s} {"#arcs":>6s} {"#inl":>5s} {"x0":>8s} {"y0(orig)":>9s} '
      f'{"1/L":>13s} {"L*Rref^2":>10s} {"inlier rms":>11s}')
best_overall = None
for k in [1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 4 / 3, 1.40]:
    A = arcs_for(k)
    if len(A) < 4:
        print(f'{k:7.4f} {len(A):6d}   -- too few arcs')
        continue
    out = ransac(A)
    if out is None:
        print(f'{k:7.4f} {len(A):6d}   -- no consensus')
        continue
    (x0, y0, K), inl, e = out
    L = 1.0 / K
    print(f'{k:7.4f} {len(A):6d} {inl.sum():5d} {x0:8.2f} {y0*k:9.2f} '
          f'{K:13.1f} {L*Rref2:10.5f} {e[inl].mean():11.3f}')
    score = inl.sum() - e[inl].mean()
    if best_overall is None or score > best_overall[0]:
        best_overall = (score, k, x0, y0, K, L, len(A), int(inl.sum()))

print('\nbest (score, k, x0, y0, 1/L, L, n_arcs, n_inliers):')
print(' ', best_overall)
if best_overall:
    _, k, x0, y0, K, L, na, ni = best_overall
    np.save('data/arc_fit.npy', np.array([k, x0, y0, K, L, na, ni]))
    print(f'\n  sign of L: {"negative -> BARREL" if L < 0 else "positive -> PINCUSHION"}')
    print(f'  L in units of 1/px^2: {L:.6e};  L*R^2 at R=660px: {L*660**2:+.4f}')
