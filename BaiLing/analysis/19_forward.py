"""Stage 19 - forward model: what sagitta would each lens type produce?

Barrel distortion bows a TANGENTIAL line away from the image centre; pincushion
bows it toward the centre; a radial line never bows. So the signed sagitta of a
clean tangential chain is a direct, calibrated distortion measurement.

We (a) convert each good tangential chain's sagitta into an equivalent division
parameter L, and (b) forward-model the sagitta a real fisheye would give for the
same chord geometry, under the four classical projections
(Schneider, Schwalbe & Maas 2009, ISPRS J. Photogramm. 64:259-266):
    perspective r=f tan(th)   stereographic r=2f tan(th/2)
    equidistant  r=f th       equisolid     r=2f sin(th/2)
"""
import numpy as np
chains = [np.asarray(c, float) for c in np.load('data/chains.npy', allow_pickle=True)]
chains = [c for c in chains if len(c) >= 60]
CX, CY = 602.86, 799.63
Rc = 660.0                            # semi-minor axis of the dark surround

def signed_sagitta(c):
    """+ve = bows AWAY from the image centre (barrel-like)."""
    P = c - c.mean(0)
    _, S, Vt = np.linalg.svd(P, full_matrices=False)
    t, d = P @ Vt[0], P @ Vt[1]
    o = np.argsort(t); ts, ds = t[o], d[o]
    chord = np.interp(ts, [ts[0], ts[-1]], [ds[0], ds[-1]])
    sag = ds - chord
    i = np.argmax(np.abs(sag))
    mid = c.mean(0)
    rv = np.array([mid[0]-CX, mid[1]-CY]); r = np.linalg.norm(rv)
    # outward normal component of Vt[1]
    outward = np.sign(Vt[1] @ (rv/max(r,1e-9)))
    span = ts[-1]-ts[0]
    tang = np.degrees(np.arccos(np.clip(abs(Vt[0] @ (rv/max(r,1e-9))),0,1)))
    return sag[i]*outward, span, r, tang, S[1]/np.sqrt(len(c))

rows = [signed_sagitta(c) for c in chains]
good = [(s,sp,r,tg,rm) for (s,sp,r,tg,rm) in rows if tg > 60 and sp > 150 and rm < 3.5]
print(f'clean near-tangential chains (tang>60deg, span>150, rms<3.5): {len(good)}')
print(f'{"sagitta":>9s} {"span":>7s} {"r_mid":>7s} {"tang":>6s} {"rms":>5s} {"implied L":>11s}')

def sag_of_L(L, r0, span):
    """sagitta of a tangential straight line under the division model."""
    u = np.linspace(-span/2, span/2, 401)
    x, y = r0*np.ones_like(u), u                 # undistorted, tangential at r0
    ru = np.hypot(x, y)
    # invert p_u = p_d/(1+L*(rd/Rc)^2)  -> solve for rd given ru
    rd = np.zeros_like(ru)
    for i, R in enumerate(ru):
        f = lambda t: t/(1+L*(t/Rc)**2) - R
        a, b = 1e-6, 4000.0
        for _ in range(80):
            m = 0.5*(a+b)
            if f(a)*f(m) <= 0: b = m
            else: a = m
        rd[i] = 0.5*(a+b)
    sc = rd/ru
    X, Y = x*sc, y*sc
    chord = np.interp(Y, [Y[0], Y[-1]], [X[0], X[-1]])
    dev = X - chord
    return dev[np.argmax(np.abs(dev))]

Ls = []
for s, sp, r, tg, rm in sorted(good, key=lambda z:-z[1]):
    grid = np.linspace(-0.8, 0.8, 161)
    pred = np.array([sag_of_L(L, r, sp) for L in grid])
    Lhat = np.interp(s, pred, grid) if pred[0] < s < pred[-1] or pred[-1] < s < pred[0] else np.nan
    Ls.append(Lhat)
    print(f'{s:+9.2f} {sp:7.1f} {r:7.1f} {tg:6.1f} {rm:5.2f} {Lhat:+11.4f}')
Ls = np.array([l for l in Ls if np.isfinite(l)])
print(f'\nimplied L: median {np.median(Ls):+.4f}  mean {Ls.mean():+.4f}  sd {Ls.std():.4f}')
print(f'  (L<0 = barrel;  L>0 = pincushion)')

print('\n--- what a real fisheye would give for a 230px tangential chord at r=520px ---')
r0, span = 520.0, 230.0
print(f'{"projection":>14s} {"FOV(deg)":>9s} {"f(px)":>9s} {"sagitta(px)":>12s}')
for name, g, ginv in (
    ('perspective',   lambda th,f: f*np.tan(th),          lambda r,f: np.arctan(r/f)),
    ('stereographic', lambda th,f: 2*f*np.tan(th/2),      lambda r,f: 2*np.arctan(r/(2*f))),
    ('equidistant',   lambda th,f: f*th,                  lambda r,f: r/f),
    ('equisolid',     lambda th,f: 2*f*np.sin(th/2),      lambda r,f: 2*np.arcsin(np.clip(r/(2*f),-1,1))),
):
    for fov in (75, 90, 110, 130, 150, 180):
        half = np.radians(fov/2)
        f = Rc/g(half, 1.0)                       # so that r=Rc at the field edge
        # tangential world line: great circle whose closest approach to the axis is th0
        th0 = ginv(r0, f)
        n = np.array([np.sin(th0), 0, np.cos(th0)])          # normal of the plane
        a = np.array([np.cos(th0), 0, -np.sin(th0)]); b = np.array([0,1.0,0])
        ts = np.linspace(-0.9, 0.9, 2001)
        p = np.outer(np.cos(ts), a) + np.outer(np.sin(ts), b)
        th = np.arccos(np.clip(p[:,2],-1,1)); ph = np.arctan2(p[:,1], p[:,0])
        rr = g(th, f)
        X, Y = rr*np.cos(ph), rr*np.sin(ph)
        m = np.isfinite(X) & np.isfinite(Y) & (rr < 4*Rc)
        X, Y = X[m], Y[m]
        keep = np.abs(Y) <= span/2
        if keep.sum() < 20: continue
        Xs, Ys = X[keep], Y[keep]
        chord = np.interp(Ys, [Ys[0], Ys[-1]], [Xs[0], Xs[-1]])
        dev = Xs - chord
        print(f'{name:>14s} {fov:9d} {f:9.1f} {dev[np.argmax(np.abs(dev))]:+12.2f}')
