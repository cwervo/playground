"""Stage 20 - Manhattan vanishing points -> focal length AND pixel aspect.

The car interior is a rectilinear box, so its edges fall into three mutually
orthogonal families. For intrinsics K = diag(fx,fy,1) with the principal point
fixed at the frame centre, two orthogonal vanishing points v1,v2 satisfy
    v1^T K^-T K^-1 v2 = 0
   =>  u1*u2 * (1/fx^2) + w1*w2 * (1/fy^2) = -1
which is LINEAR in A=1/fx^2, B=1/fy^2. Three VPs give three such equations for
two unknowns - over-determined, so it both estimates fx,fy and tests itself.
k = fy/fx is the anamorphic factor: k=1 means square pixels (so an elliptical
dark surround must be painted on); k=4/3 means the frame was stretched.
(Caprile & Torre 1990; Deutscher, Isard & MacCormick 2002; Hartley & Zisserman
sec. 8.6.)
"""
import numpy as np
chains = [np.asarray(c, float) for c in np.load('data/chains.npy', allow_pickle=True)]

lines, info = [], []
for c in chains:
    if len(c) < 60: continue
    P = c - c.mean(0)
    _, S, Vt = np.linalg.svd(P, full_matrices=False)
    rms = S[1]/np.sqrt(len(c))
    span = np.ptp(P @ Vt[0])
    if rms > 1.6 or span < 90: continue          # keep only genuinely straight edges
    d = Vt[0]; n = np.array([-d[1], d[0]])
    m = c.mean(0)
    lines.append(np.array([n[0], n[1], -(n @ m)]))
    info.append((span, rms, m))
lines = np.array(lines)
print(f'straight lines kept: {len(lines)}')
for (sp, rms, m), l in zip(info, lines):
    ang = np.degrees(np.arctan2(-l[0], l[1])) % 180
    print(f'   span {sp:6.1f}  rms {rms:.2f}  mid ({m[0]:6.1f},{m[1]:6.1f})  angle {ang:6.1f}')

def dist_pt_line(l, p):
    return abs(l[0]*p[0] + l[1]*p[1] + l[2]) / np.hypot(l[0], l[1])

def ransac_vp(L, idx, iters=20000, tol=2.5, seed=0):
    rng = np.random.default_rng(seed)
    best = (0, None, None)
    for _ in range(iters):
        i, j = rng.choice(len(idx), 2, replace=False)
        v = np.cross(L[idx[i]], L[idx[j]])
        if abs(v[2]) < 1e-9: continue
        v = v/v[2]
        if not np.isfinite(v).all() or np.abs(v[:2]).max() > 6e4: continue
        # a line "passes through" v if v is close to it, scaled by how far v is
        d = np.array([dist_pt_line(L[q], v[:2]) for q in idx])
        inl = d < tol
        if inl.sum() > best[0]: best = (inl.sum(), v, inl)
    return best

remaining = list(range(len(lines)))
vps = []
for step in range(3):
    if len(remaining) < 3: break
    n, v, inl = ransac_vp(lines, remaining, seed=step)
    if v is None or n < 3: break
    members = [remaining[q] for q in np.nonzero(inl)[0]]
    # refine: least squares intersection
    A = lines[members][:, :2]; b = -lines[members][:, 2]
    w = np.array([info[q][0] for q in members])
    sol, *_ = np.linalg.lstsq(A*w[:,None], b*w, rcond=None)
    vps.append((sol, members))
    print(f'\nVP{step+1}: ({sol[0]:10.1f}, {sol[1]:10.1f})  from {len(members)} lines')
    for q in members:
        print(f'     span {info[q][0]:6.1f} rms {info[q][1]:.2f} mid '
              f'({info[q][2][0]:6.1f},{info[q][2][1]:6.1f})')
    remaining = [q for q in remaining if q not in members]
np.save('data/vps.npy', np.array([v for v,_ in vps], dtype=object), allow_pickle=True)

CX, CY = 603.0, 804.0
if len(vps) >= 2:
    print('\n--- orthogonality solve (principal point at frame centre) ---')
    V = [v for v,_ in vps]
    rows, rhs = [], []
    for i in range(len(V)):
        for j in range(i+1, len(V)):
            u1, w1 = V[i][0]-CX, V[i][1]-CY
            u2, w2 = V[j][0]-CX, V[j][1]-CY
            rows.append([u1*u2, w1*w2]); rhs.append(-1.0)
            print(f'  pair ({i+1},{j+1}): u1u2={u1*u2:14.1f}  w1w2={w1*w2:14.1f}')
    rows, rhs = np.array(rows), np.array(rhs)
    if len(rows) >= 2:
        sol, res, rank, sv = np.linalg.lstsq(rows, rhs, rcond=None)
        A, B = sol
        print(f'\n  A=1/fx^2 = {A:.6e}   B=1/fy^2 = {B:.6e}')
        if A > 0 and B > 0:
            fx, fy = 1/np.sqrt(A), 1/np.sqrt(B)
            print(f'  fx = {fx:.1f} px   fy = {fy:.1f} px   k = fy/fx = {fy/fx:.4f}')
        else:
            print('  non-physical (negative) - VP set is degenerate or not orthogonal')
        # square-pixel variant
        r2, *_ = np.linalg.lstsq(rows.sum(axis=1)[:,None], rhs, rcond=None)
        if r2[0] > 0: print(f'  square-pixel constraint: f = {1/np.sqrt(r2[0]):.1f} px')
