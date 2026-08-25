"""Stage 18 - the correct plumb-line test: bowing vs TANGENTIALITY.

A world line whose image passes through the principal point stays straight under
ANY rotationally symmetric distortion; only the tangential component bows. So
straightness of the ceiling lines (which converge near the centre) proves
nothing. We therefore
  (a) classify every chain by the angle between it and the local radial
      direction, and
  (b) profile the objective over the single division-model parameter L with the
      centre fixed, which removes the contraction degeneracy entirely.
"""
import numpy as np
chains = [np.asarray(c, float) for c in np.load('data/chains.npy', allow_pickle=True)]
chains = [c for c in chains if len(c) >= 60]
CX, CY = 602.86, 799.63
Rref = 660.0                      # semi-minor of the dark surround, tile px

def descr(c):
    P = c - c.mean(0)
    _, S, Vt = np.linalg.svd(P, full_matrices=False)
    t = P @ Vt[0]; d = P @ Vt[1]
    span = t.max()-t.min()
    o = np.argsort(t); ts, ds = t[o], d[o]
    chord = np.interp(ts, [ts[0], ts[-1]], [ds[0], ds[-1]])
    sag = ds - chord; i = np.argmax(np.abs(sag))
    mid = c.mean(0)
    rv = np.array([mid[0]-CX, mid[1]-CY]); r = np.linalg.norm(rv)
    rad = rv/max(r,1e-9)
    cosang = abs(Vt[0] @ rad)
    tang = np.degrees(np.arccos(np.clip(cosang,0,1)))   # 0=radial, 90=tangential
    return span, S[1]/np.sqrt(len(c)), sag[i], r, tang

D = np.array([descr(c) for c in chains])
long = (D[:,0] > 140) & (D[:,3] > 200)
print(f'chains with span>140 and r>200: {long.sum()}')
print(f'\n{"span":>7s} {"rms":>6s} {"sagitta":>8s} {"r_mid":>7s} {"tangentiality":>13s}')
for row in D[long][np.argsort(-D[long][:,0])]:
    print(f'{row[0]:7.1f} {row[1]:6.2f} {row[2]:+8.2f} {row[3]:7.1f} {row[4]:13.1f}')

for lo, hi, lab in ((0,25,'near-RADIAL  '), (25,60,'oblique      '), (60,90,'near-TANGENT ')):
    m = long & (D[:,4] >= lo) & (D[:,4] < hi)
    if m.sum():
        print(f'\n{lab} ({lo}-{hi} deg): n={m.sum():2d}  '
              f'median |sag|={np.median(np.abs(D[m,2])):6.2f} px  '
              f'median rms={np.median(D[m,1]):5.2f} px  '
              f'median |sag|/span={np.median(np.abs(D[m,2]/D[m,0])):.4f}')

# ---- 1-D profile over L, centre fixed ----
def undist(P, L):
    dx, dy = P[:,0]-CX, P[:,1]-CY
    s = (dx*dx+dy*dy)/(Rref*Rref)
    f = 1.0 + L*s
    return np.c_[CX+dx/f, CY+dy/f]

use = [chains[i] for i in np.nonzero(long & (D[:,4] > 30))[0]]     # exclude radial
print(f'\nprofiling L on {len(use)} non-radial chains (trimmed 60%)')
def cost(L):
    v = []
    for c in use:
        Q = undist(c, L)
        Qc = Q - Q.mean(0)
        sv = np.linalg.svd(Qc, compute_uv=False)
        v.append(sv[1]/np.sqrt(len(c)))
    v = np.sort(np.array(v))
    return v[:max(4,int(0.6*len(v)))].mean()
Ls = np.linspace(-0.60, 0.60, 121)
C = np.array([cost(L) for L in Ls])
i = np.argmin(C)
print(f'\n{"L":>7s} {"trimmed rms(px)":>16s}')
for j in range(0, 121, 5): print(f'{Ls[j]:7.3f} {C[j]:16.4f}')
print(f'\nbest L = {Ls[i]:+.3f}  cost {C[i]:.4f}   (L=0 cost {C[60]:.4f})')
# 1-sigma-ish interval: where cost rises 5% above minimum
ok = np.nonzero(C < C[i]*1.05)[0]
print(f'L within 5% of minimum: [{Ls[ok[0]]:+.3f}, {Ls[ok[-1]]:+.3f}]')
np.save('data/Lprofile.npy', np.vstack([Ls, C]))
np.save('data/chain_descr.npy', D)
