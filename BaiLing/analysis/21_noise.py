"""Stage 21 - noise field: photon transfer curve, and noise vs vignette depth.

Two questions:
 (1) Does the noise obey a sensor's photon transfer curve, var = mu/g + var_read
     (Janesick; Healey & Kondepudy 1994; Foi et al. 2008 Poissonian-Gaussian)?
 (2) Does the noise ATTENUATE inside the dark surround?
     Optical falloff scales the photon flux, so shot noise falls with the
     signal. A grain layer laid on AFTER a synthetic vignette keeps its
     amplitude where the picture has gone black. That is the decisive test of
     whether the dark surround is optical or painted.
Noise is estimated from a high-pass residual, robustly (MAD), on 16x16 tiles.
"""
import numpy as np
from scipy import ndimage as ndi

lin  = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
enc  = np.load('data/screen_u16.npy')[330:1938].astype(np.float64)/65535.0
rho  = np.load('data/rho_map.npy')
H, W = rho.shape
ui = np.zeros((H,W), bool)
for y0,y1,x0,x1 in [(40,130,1040,1170),(1480,1580,1080,1170)]: ui[y0:y1,x0:x1]=True

def noise_map(ch, P=16):
    """MAD of the diagonal Laplacian residual, per PxP tile -> sigma."""
    # 2nd difference along the diagonal decorrelates JPEG's 8x8 structure less
    d = (ch[1:-1,1:-1]*2 - ch[:-2,:-2] - ch[2:,2:]) / np.sqrt(6.0)
    hh, ww = (d.shape[0]//P)*P, (d.shape[1]//P)*P
    t = d[:hh,:ww].reshape(hh//P, P, ww//P, P)
    med = np.median(t, axis=(1,3), keepdims=True)
    mad = np.median(np.abs(t-med), axis=(1,3))
    return 1.4826*mad

def mean_map(ch, P=16):
    hh, ww = (ch.shape[0]//P)*P, (ch.shape[1]//P)*P
    return ch[:hh,:ww].reshape(hh//P,P,ww//P,P).mean(axis=(1,3))

P = 16
G_enc = enc.mean(axis=2)
sig  = noise_map(G_enc, P)
mu   = mean_map(G_enc[1:-1,1:-1], P)
rr   = mean_map(rho[1:-1,1:-1], P)
uu   = mean_map(ui[1:-1,1:-1].astype(float), P)
tex  = mean_map(np.abs(ndi.gaussian_filter(G_enc,1.0)[1:-1,1:-1]
                       - ndi.gaussian_filter(G_enc,4.0)[1:-1,1:-1]), P)
ok = (uu < 0.01)
print('tiles', ok.sum())

print('\n=== (2) noise vs vignette depth (all tiles, flat ones only) ===')
flat = ok & (tex < np.percentile(tex[ok], 35))
print(f'{"rho band":>12s} {"n":>5s} {"mean level":>11s} {"sigma":>9s} {"sigma/mean":>11s}')
bands = [(0.0,0.3),(0.3,0.5),(0.5,0.7),(0.7,0.8),(0.8,0.86),(0.86,0.90),
         (0.90,0.94),(0.94,0.97),(0.97,1.00),(1.00,1.05),(1.05,1.15),(1.15,1.40)]
prof=[]
for a,b in bands:
    m = flat & (rr>=a) & (rr<b)
    if m.sum() < 6: 
        print(f'{a:5.2f}-{b:4.2f} {m.sum():5d}   (too few)'); continue
    print(f'{a:5.2f}-{b:4.2f} {m.sum():5d} {np.median(mu[m]):11.5f} '
          f'{np.median(sig[m]):9.5f} {np.median(sig[m])/max(np.median(mu[m]),1e-9):11.4f}')
    prof.append((0.5*(a+b), np.median(mu[m]), np.median(sig[m]), m.sum()))
np.save('data/noise_vs_rho.npy', np.array(prof))

print('\n=== (1) photon transfer curve, bright interior (rho<0.8) ===')
inn = ok & (rr < 0.80) & (tex < np.percentile(tex[ok & (rr<0.80)], 40))
print(f'{"mu band":>13s} {"n":>5s} {"mu":>9s} {"sigma":>9s} {"var":>11s}')
pts=[]
edges = np.percentile(mu[inn], np.linspace(0,100,13))
for i in range(len(edges)-1):
    m = inn & (mu>=edges[i]) & (mu<edges[i+1])
    if m.sum() < 8: continue
    mm, ss = np.median(mu[m]), np.median(sig[m])
    print(f'{edges[i]:6.4f}-{edges[i+1]:5.4f} {m.sum():5d} {mm:9.5f} {ss:9.5f} {ss**2:11.3e}')
    pts.append((mm, ss**2, m.sum()))
pts=np.array(pts)
if len(pts) >= 4:
    A = np.c_[pts[:,0], np.ones(len(pts))]
    sol, *_ = np.linalg.lstsq(A*np.sqrt(pts[:,2])[:,None], pts[:,1]*np.sqrt(pts[:,2]), rcond=None)
    slope, icpt = sol
    print(f'\n  var = {slope:.5e} * mu + {icpt:.5e}')
    print(f'  slope/intercept ratio: {slope/max(icpt,1e-12):.2f}')
    print(f'  correlation of var with mu: {np.corrcoef(pts[:,0], pts[:,1])[0,1]:+.4f}')
np.save('data/ptc.npy', pts)
