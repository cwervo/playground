"""Stage 17 - how straight are the long scene edges, as shot?

If the lens carried appreciable radial distortion, long straight edges far from
the optical centre would bow by many pixels. We measure, per chain, the maximum
signed sagitta from the best-fit straight line, and correlate it with distance
from the frame centre - the signature any radial model must produce.
"""
import numpy as np
chains = [np.asarray(c, float) for c in np.load('data/chains.npy', allow_pickle=True)]
chains = sorted([c for c in chains if len(c) >= 60], key=len, reverse=True)
cx0, cy0 = 602.86, 799.63          # level-set centre of the dark surround

print(f'{"n":>5s} {"span":>7s} {"rms":>6s} {"maxsag":>7s} {"r_mid":>7s} '
      f'{"sag/span":>9s} {"orient":>7s}  extent')
rows = []
for c in chains[:40]:
    P = c - c.mean(0)
    U, S, Vt = np.linalg.svd(P, full_matrices=False)
    t = P @ Vt[0]; d = P @ Vt[1]
    span = t.max()-t.min()
    # signed sagitta: deviation at the arc midpoint relative to the chord
    o = np.argsort(t); ts, ds = t[o], d[o]
    chord = np.interp(ts, [ts[0], ts[-1]], [ds[0], ds[-1]])
    sag = ds - chord
    imax = np.argmax(np.abs(sag))
    mid = c.mean(0)
    r = np.hypot(mid[0]-cx0, mid[1]-cy0)
    ori = np.degrees(np.arctan2(Vt[0][1], Vt[0][0])) % 180
    rows.append((len(c), span, d.std(), sag[imax], r, sag[imax]/span, ori))
    print(f'{len(c):5d} {span:7.1f} {d.std():6.2f} {sag[imax]:+7.2f} {r:7.1f} '
          f'{sag[imax]/span:+9.4f} {ori:7.1f}  x[{c[:,0].min():.0f},{c[:,0].max():.0f}] '
          f'y[{c[:,1].min():.0f},{c[:,1].max():.0f}]')

rows = np.array(rows)
sel = rows[:,1] > 150
print(f'\nchains with span>150 px: {sel.sum()}')
print(f'  median |sagitta|            = {np.median(np.abs(rows[sel,3])):.2f} px')
print(f'  median |sagitta|/span       = {np.median(np.abs(rows[sel,5])):.5f}')
print(f'  median rms from straight    = {np.median(rows[sel,2]):.2f} px')
print(f'  fraction with |sagitta|<2px = {(np.abs(rows[sel,3])<2).mean():.2f}')

# What sagitta WOULD a real fisheye produce? equidistant lens, f = R_circle/(pi/2)
for fov in (100, 120, 150, 180):
    f_eq = 660.0/np.radians(fov/2)      # px, equidistant, half-diagonal 660
    # a straight line whose closest approach to the axis is r0, spanning +-s
    for r0, s in ((300, 250),):
        # image of a line: compare mid vs chord in the equidistant projection
        th = np.arctan(np.linspace(-s, s, 201)/f_eq)
        pass
print('\n(see stage 18 for the forward-model sagitta prediction)')
np.save('data/straightness.npy', rows)
