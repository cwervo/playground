"""Stage 9 - trace the support boundary and fit a conic.

Everything outside the illuminated field clips to exact zero, so the support of
non-zero pixels is the projected image circle. We trace it ray-by-ray, then fit
(a) a circle and (b) a general conic. A significantly non-unit axis ratio means
the frame has been scaled anisotropically somewhere in the chain - the image
circle itself is circular for any rotationally symmetric lens.
"""
import numpy as np
t16 = np.load('data/tile_u16.npy'); H, W = t16.shape[:2]
black = (t16 == 0).all(axis=2)

ui = np.zeros_like(black)
for y0,y1,x0,x1 in [(60,110,1060,1150), (1500,1556,1100,1150)]:
    ui[y0:y1, x0:x1] = True
lit = (~black) & (~ui)

cy0, cx0 = H/2.0, W/2.0
pts = []
for deg in np.arange(0, 360, 0.2):
    th = np.radians(deg); dy, dx = np.sin(th), np.cos(th)
    rs = np.arange(1300, 30, -0.25)
    yy = cy0 + dy*rs; xx = cx0 + dx*rs
    ok = (yy>=0)&(yy<=H-1)&(xx>=0)&(xx<=W-1)
    if ok.sum() < 50: continue
    yi = np.clip(np.round(yy[ok]),0,H-1).astype(int)
    xi = np.clip(np.round(xx[ok]),0,W-1).astype(int)
    rr = rs[ok]; L = lit[yi, xi]
    # first sustained lit run scanning inward
    j = None
    for k in range(len(L)-16):
        if L[k:k+16].mean() >= 0.95: j = k; break
    if j is None: continue
    if j == 0: continue                       # boundary is off-frame here
    y, x = cy0+dy*rr[j], cx0+dx*rr[j]
    if y<3 or y>H-4 or x<3 or x>W-4: continue # clipped by the tile edge
    pts.append((x, y, deg, rr[j]))
pts = np.array(pts)
print(f'boundary samples: {len(pts)} (of 1800 rays); '
      f'radius {pts[:,3].min():.1f}..{pts[:,3].max():.1f}')

x, y = pts[:,0], pts[:,1]
# --- circle fit (Kasa / algebraic, then Gauss-Newton geometric refine)
A = np.c_[x, y, np.ones_like(x)]; b = x**2 + y**2
sol, *_ = np.linalg.lstsq(A, b, rcond=None)
cx, cy = sol[0]/2, sol[1]/2; R = np.sqrt(sol[2] + cx**2 + cy**2)
for _ in range(50):
    d = np.hypot(x-cx, y-cy); r = d - R
    J = np.c_[-(x-cx)/d, -(y-cy)/d, -np.ones_like(d)]
    dp, *_ = np.linalg.lstsq(J, -r, rcond=None)
    cx += dp[0]; cy += dp[1]; R += dp[2]
res = np.hypot(x-cx, y-cy) - R
print(f'\nCIRCLE  centre ({cx:.2f}, {cy:.2f})  R = {R:.2f} px   '
      f'rms residual {res.std():.2f} px  max |res| {np.abs(res).max():.2f}')
print(f'        centre offset from tile centre: dx {cx-W/2:+.2f}  dy {cy-H/2:+.2f}')

# --- general conic fit  ax^2+bxy+cy^2+dx+ey+f=0  (Fitzgibbon direct ellipse)
D = np.c_[x*x, x*y, y*y, x, y, np.ones_like(x)]
S = D.T @ D
C = np.zeros((6,6)); C[0,2]=C[2,0]=2; C[1,1]=-1
ev, evec = np.linalg.eig(np.linalg.solve(S, C))
k = np.argmax(np.real(ev)); a_ = np.real(evec[:,k])
a,bb,c,d,e,f = a_
M = np.array([[a, bb/2],[bb/2, c]])
cen = np.linalg.solve(2*M, [-d, -e])
val = a*cen[0]**2 + bb*cen[0]*cen[1] + c*cen[1]**2 + d*cen[0] + e*cen[1] + f
w_, V = np.linalg.eigh(M)
ax = np.sqrt(-val/w_)
order = np.argsort(-ax); ax = ax[order]; V = V[:, order]
ang = np.degrees(np.arctan2(V[1,0], V[0,0]))
print(f'\nELLIPSE centre ({cen[0]:.2f}, {cen[1]:.2f})  semi-axes {ax[0]:.2f} / {ax[1]:.2f} px')
print(f'        axis ratio (major/minor) = {ax[0]/ax[1]:.5f}   major-axis tilt {ang:.2f} deg')
# residuals
def conic_res(px, py):
    return a*px*px + bb*px*py + c*py*py + d*px + e*py + f
g = conic_res(x,y)
gx = 2*a*x + bb*y + d; gy = bb*x + 2*c*y + e
print(f'        rms geometric residual {np.std(g/np.hypot(gx,gy)):.2f} px')
np.save('data/boundary_pts.npy', pts)
np.save('data/circle_fit.npy', np.array([cx, cy, R]))
np.save('data/ellipse_fit.npy', np.array([cen[0], cen[1], ax[0], ax[1], ang]))
print(f'\nfor reference: 4/3 = {4/3:.5f}, 1440/1080 = {1440/1080:.5f}, 5/4 = 1.25')
