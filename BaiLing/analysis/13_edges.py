"""Stage 13 - subpixel edge chains for plumb-line distortion estimation.

Canny-style detection with subpixel refinement (parabolic fit across the
gradient ridge), then 8-connected linking, corner splitting, and length
filtering. Chains are the raw material for Devernay-Faugeras style straightness
optimisation and for Bukhari-Dailey arc fitting.
"""
import numpy as np
from scipy import ndimage as ndi

lin = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
rho = np.load('data/rho_map.npy')
H, W = lin.shape[:2]

# perceptual-ish domain so shadow structure gets weight, then denoise
g = (np.clip(lin.mean(axis=2), 0, 1))**(1/2.6)
g = ndi.gaussian_filter(g, 1.6)

gy, gx = np.gradient(g)
mag = np.hypot(gx, gy)
ang = np.arctan2(gy, gx)

valid = rho < 0.93                       # stay off the vignette shoulder
ui = np.zeros((H,W), bool)
for y0,y1,x0,x1 in [(40,130,1040,1170),(1480,1580,1080,1170)]: ui[y0:y1,x0:x1]=True
valid &= ~ui

# non-maximum suppression
q = (np.round(ang/(np.pi/4)).astype(int)) % 4
off = {0:(0,1), 1:(1,1), 2:(1,0), 3:(1,-1)}
nms = np.zeros_like(mag, bool)
for d,(dy,dx) in off.items():
    m = (q==d) & valid
    a = np.roll(np.roll(mag, -dy, 0), -dx, 1)
    b = np.roll(np.roll(mag,  dy, 0),  dx, 1)
    nms |= m & (mag >= a) & (mag >= b)
nms[:3,:]=nms[-3:,:]=nms[:,:3]=nms[:,-3:]=False

hi = np.percentile(mag[valid], 97.5); lo = 0.4*hi
strong = nms & (mag >= hi); weak = nms & (mag >= lo)
lab, n = ndi.label(weak, structure=np.ones((3,3)))
keep = np.zeros(n+1, bool)
keep[np.unique(lab[strong])] = True; keep[0] = False
edges = keep[lab]
print(f'edge pixels: {edges.sum()}  (hi={hi:.4f})')

# subpixel offset along the gradient direction
ys, xs = np.nonzero(edges)
ux, uy = gx[ys,xs]/(mag[ys,xs]+1e-12), gy[ys,xs]/(mag[ys,xs]+1e-12)
def bilin(im, yy, xx):
    y0=np.floor(yy).astype(int); x0=np.floor(xx).astype(int)
    fy=yy-y0; fx=xx-x0
    y0=np.clip(y0,0,H-2); x0=np.clip(x0,0,W-2)
    return (im[y0,x0]*(1-fy)*(1-fx)+im[y0+1,x0]*fy*(1-fx)
           +im[y0,x0+1]*(1-fy)*fx+im[y0+1,x0+1]*fy*fx)
m0 = mag[ys,xs]
mp = bilin(mag, ys+uy, xs+ux); mm = bilin(mag, ys-uy, xs-ux)
den = (mp - 2*m0 + mm)
t = np.where(np.abs(den) > 1e-12, -0.5*(mp-mm)/den, 0.0)
t = np.clip(t, -0.7, 0.7)
px = xs + t*ux; py = ys + t*uy

# link: label connected components of the edge map, then order each by PCA walk
lab2, n2 = ndi.label(edges, structure=np.ones((3,3)))
print('raw components', n2)
idx = {}
for i,(yy,xx) in enumerate(zip(ys,xs)): idx[(yy,xx)] = i
chains = []
for cid in range(1, n2+1):
    sel = np.nonzero(lab2[ys,xs] == cid)[0]
    if len(sel) < 45: continue
    P = np.c_[px[sel], py[sel]]
    # order along the principal direction
    Pc = P - P.mean(0)
    u_,s_,vt = np.linalg.svd(Pc, full_matrices=False)
    tpar = Pc @ vt[0]
    o = np.argsort(tpar); P = P[o]
    # elongation test: reject blobs
    if s_[1]/s_[0] > 0.45: continue
    chains.append(P)
print('chains kept', len(chains), ' total pts', sum(len(c) for c in chains))
np.save('data/chains.npy', np.array(chains, dtype=object), allow_pickle=True)
for i,c in enumerate(sorted(chains, key=len, reverse=True)[:14]):
    print(f'  chain {i}: n={len(c):4d}  x {c[:,0].min():6.1f}..{c[:,0].max():6.1f}  '
          f'y {c[:,1].min():6.1f}..{c[:,1].max():6.1f}')
