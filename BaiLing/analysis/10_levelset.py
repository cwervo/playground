"""Stage 10 - level-set fit of the image-circle boundary.

Rather than tracing rays (fragile where the scene itself is dark), we fit the
ellipse that best SEPARATES exact-black from lit pixels over the whole tile.
Objective: maximise Youden's J = TPR - FPR for the predicate rho<=1, where
rho^2 = ((x-cx)cos t+(y-cy)sin t)^2/a^2 + (-(x-cx)sin t+(y-cy)cos t)^2/b^2.
Uses every pixel, so scene-dependent dark patches average out.
"""
import numpy as np
from scipy.optimize import minimize

t16 = np.load('data/tile_u16.npy'); H, W = t16.shape[:2]
black = (t16 == 0).all(axis=2)
ui = np.zeros_like(black)
for y0,y1,x0,x1 in [(60,110,1060,1150), (1500,1556,1100,1150)]: ui[y0:y1,x0:x1] = True

# subsample for speed
step = 2
Y, X = np.mgrid[0:H:step, 0:W:step].astype(np.float64)
B = black[::step, ::step]; U = ui[::step, ::step]
keep = ~U
Y, X, B = Y[keep], X[keep], B[keep]
print('pixels used', len(B), ' black frac', B.mean().round(4))

def rho(p):
    cx, cy, a, b, th = p
    ct, st = np.cos(th), np.sin(th)
    u = (X-cx)*ct + (Y-cy)*st
    v = -(X-cx)*st + (Y-cy)*ct
    return np.sqrt((u/a)**2 + (v/b)**2)

def neg_J(p):
    if min(p[2], p[3]) < 100: return 10.0
    r = rho(p)
    inside = r <= 1.0
    tpr = (inside & ~B).sum() / max((~B).sum(), 1)      # lit correctly inside
    fpr = (inside &  B).sum() / max(B.sum(), 1)         # black wrongly inside
    return -(tpr - fpr)

p0 = np.array([616.5, 794.6, 671.0, 907.8, 0.0])
best = minimize(neg_J, p0, method='Nelder-Mead',
                options=dict(maxiter=6000, xatol=1e-3, fatol=1e-7))
cx, cy, a, b, th = best.x
print(f'\nfit: centre ({cx:.2f}, {cy:.2f})  a(x) {a:.2f}  b(y) {b:.2f}  '
      f'rot {np.degrees(th):.3f} deg   Youden J = {-best.fun:.5f}')
print(f'     axis ratio b/a = {b/a:.5f}   (4/3={4/3:.5f})')
print(f'     centre offset from tile centre: dx {cx-W/2:+.2f} dy {cy-H/2:+.2f}')

# constrained variant: force a circle (b == a) to compare
def neg_J_circ(q):
    return neg_J(np.array([q[0], q[1], q[2], q[2], 0.0]))
bc = minimize(neg_J_circ, [616.5, 794.6, 780.0], method='Nelder-Mead',
              options=dict(maxiter=4000, xatol=1e-3, fatol=1e-7))
print(f'\ncircle-constrained: centre ({bc.x[0]:.2f}, {bc.x[1]:.2f}) R {bc.x[2]:.2f}  J={-bc.fun:.5f}')
print(f'   -> ellipse improves J by {(-best.fun)-(-bc.fun):.5f}')

# sharpness of the separation: profile of mean luminance vs rho
lin = np.load('data/screen_linearP3.npy')[330:1938].mean(axis=2)
Ys, Xs = np.mgrid[0:H, 0:W].astype(np.float64)
ct, st = np.cos(th), np.sin(th)
u = (Xs-cx)*ct + (Ys-cy)*st; v = -(Xs-cx)*st + (Ys-cy)*ct
R = np.sqrt((u/a)**2 + (v/b)**2)
np.save('data/rho_map.npy', R.astype(np.float32))
np.save('data/ellipse_levelset.npy', np.array([cx,cy,a,b,th]))
bins = np.arange(0.70, 1.30, 0.005)
print('\n rho     mean linear L    frac exactly black')
for i in range(len(bins)-1):
    m = (R>=bins[i]) & (R<bins[i+1]) & (~ui)
    if m.sum() > 500 and i % 4 == 0:
        print(f' {bins[i]:.3f}   {lin[m].mean():.6f}      {black[m].mean():.4f}')
