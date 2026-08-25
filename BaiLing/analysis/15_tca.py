"""Stage 15 - lateral chromatic aberration field (independent isotropy probe).

For any rotationally symmetric lens the R-vs-B misregistration is purely RADIAL
about the optical axis and its magnitude depends only on radius (Brown 1966;
Mallon & Whelan 2007, 'Calibration and removal of lateral chromatic
aberration'). Measuring the field therefore locates the optical centre WITHOUT
using the vignette, and tells us whether the frame is isotropic: an
anamorphically stretched frame gives elliptical iso-magnitude contours.
"""
import numpy as np
from scipy import ndimage as ndi

lin = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
rho = np.load('data/rho_map.npy')
H, W = lin.shape[:2]
R = np.clip(lin[...,0],1e-6,1)**(1/2.6)
B = np.clip(lin[...,2],1e-6,1)**(1/2.6)
G = np.clip(lin[...,1],1e-6,1)**(1/2.6)

def shift_phasecorr(a, b, up=20):
    a = (a-a.mean())*np.outer(np.hanning(a.shape[0]), np.hanning(a.shape[1]))
    b = (b-b.mean())*np.outer(np.hanning(b.shape[0]), np.hanning(b.shape[1]))
    Fa, Fb = np.fft.fft2(a), np.fft.fft2(b)
    Xc = Fa*np.conj(Fb); Xc /= np.abs(Xc)+1e-12
    c = np.real(np.fft.ifft2(Xc))
    n = a.shape[0]
    j = np.unravel_index(np.argmax(c), c.shape)
    # parabolic subpixel on the 3x3 neighbourhood
    def sub(i, ax):
        im1 = c[(j[0]-1)%n, j[1]] if ax==0 else c[j[0], (j[1]-1)%n]
        ip1 = c[(j[0]+1)%n, j[1]] if ax==0 else c[j[0], (j[1]+1)%n]
        d = ip1 - 2*c[j] + im1
        return -0.5*(ip1-im1)/d if abs(d)>1e-12 else 0.0
    dy = j[0] + sub(0,0); dx = j[1] + sub(0,1)
    if dy > n/2: dy -= n
    if dx > n/2: dx -= n
    return dx, dy, c[j]

P = 64; step = 40
recs = []
for y in range(0, H-P, step):
    for x in range(0, W-P, step):
        if rho[y+P//2, x+P//2] > 0.90: continue
        gr = G[y:y+P, x:x+P]
        if gr.std() < 0.035: continue                 # need texture
        dx, dy, pk = shift_phasecorr(R[y:y+P,x:x+P], B[y:y+P,x:x+P])
        if pk < 0.06 or abs(dx) > 6 or abs(dy) > 6: continue
        recs.append((x+P/2, y+P/2, dx, dy, pk))
recs = np.array(recs)
print('TCA samples', len(recs))
np.save('data/tca.npy', recs)

# fit: displacement = alpha * (p - c) / k-scaled radius  (pure radial, linear)
from scipy.optimize import least_squares
def model(p, X, Y):
    x0, y0, alpha, beta, k = p
    dx = X-x0; dy = (Y-y0)/k
    r = np.hypot(dx, dy) + 1e-9
    s = alpha*(r/800.0) + beta*(r/800.0)**3
    return s*dx/r, s*dy/r*k

def resid(p):
    ux, uy = model(p, recs[:,0], recs[:,1])
    return np.concatenate([ux-recs[:,2], uy-recs[:,3]])

for kfix in (None, 1.0, 4/3):
    if kfix is None:
        p0 = [603, 804, 0.5, 0.5, 1.0]; lo=[300,400,-8,-8,0.7]; hi=[900,1200,8,8,1.8]
    else:
        p0 = [603, 804, 0.5, 0.5, kfix]; lo=[300,400,-8,-8,kfix-1e-9]; hi=[900,1200,8,8,kfix+1e-9]
    r = least_squares(resid, p0, bounds=(lo,hi), loss='soft_l1', f_scale=0.25)
    x0,y0,al,be,k = r.x
    rms = np.sqrt(np.mean(r.fun**2))
    tag = 'k free' if kfix is None else f'k fixed {kfix:.4f}'
    print(f'{tag:16s}: centre ({x0:7.1f},{y0:7.1f})  alpha {al:+.4f} beta {be:+.4f} '
          f'k {k:.4f}  rms {rms:.4f} px')
