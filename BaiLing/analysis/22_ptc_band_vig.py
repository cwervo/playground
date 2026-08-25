"""Stage 22 - (A) photon transfer curve in LINEAR light, (B) flicker banding,
(C) vignette profile shape.

(A) Poissonian-Gaussian model  var = a*mu + b  (Foi, Trimeche, Katkovnik &
    Egiazarian 2008). Must be fitted in LINEAR light; in a gamma-encoded image
    photon noise looks almost flat and the fit is meaningless.
(B) AC-powered lighting flickers at 2x mains (100/120 Hz). A rolling shutter
    prints that as horizontal banding whose spatial period gives the row
    readout time (Sheinin, Schechner & Kutulakos, CVPR 2017 / ICCP 2018).
(C) Natural vignetting follows cos^4 -> V = (1+(r/f)^2)^-2 (Kang & Weiss 2000;
    Zheng, Lin & Kang 2009). A drawn vignette is usually a smoothstep or a
    power law in normalised radius, and reaches EXACTLY zero.
"""
import numpy as np
from scipy import ndimage as ndi
from scipy.optimize import curve_fit

lin = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
rho = np.load('data/rho_map.npy'); H, W = rho.shape
ui = np.zeros((H,W), bool)
for y0,y1,x0,x1 in [(40,130,1040,1170),(1480,1580,1080,1170)]: ui[y0:y1,x0:x1]=True

# ---------- (A) linear-light PTC ----------
P = 16
def tiles(a, P=16, f=np.mean):
    hh, ww = (a.shape[0]//P)*P, (a.shape[1]//P)*P
    return f(a[:hh,:ww].reshape(hh//P,P,ww//P,P), axis=(1,3))
G = lin.mean(axis=2)
d = (G[1:-1,1:-1]*2 - G[:-2,:-2] - G[2:,2:])/np.sqrt(6.0)
hh, ww = (d.shape[0]//P)*P, (d.shape[1]//P)*P
dt  = d[:hh,:ww].reshape(hh//P,P,ww//P,P)
med = np.median(dt, axis=(1,3), keepdims=True)
mad = 1.4826*np.median(np.abs(dt-med), axis=(1,3))
crop = lambda a: a[1:-1,1:-1][:hh,:ww]
mu  = tiles(crop(G), P)
rr  = tiles(crop(rho), P)
uu  = tiles(crop(ui.astype(float)), P)
tex = tiles(crop(np.abs(ndi.gaussian_filter(G,1.)-ndi.gaussian_filter(G,4.))), P)
m = (uu<0.01)&(rr<0.85)&(tex<np.percentile(tex[(uu<0.01)&(rr<0.85)],40))
print('=== (A) PTC in linear light ===')
print(f'{"mu(linear)":>12s} {"n":>4s} {"sigma":>10s} {"var":>12s}')
pts=[]
ed = np.percentile(mu[m], np.linspace(0,100,14))
for i in range(len(ed)-1):
    s = m & (mu>=ed[i]) & (mu<ed[i+1])
    if s.sum()<8: continue
    a_, b_ = np.median(mu[s]), np.median(mad[s])
    print(f'{a_:12.6f} {s.sum():4d} {b_:10.6f} {b_**2:12.4e}')
    pts.append((a_, b_**2, s.sum()))
pts=np.array(pts)
A_ = np.c_[pts[:,0], np.ones(len(pts))]
w = np.sqrt(pts[:,2])
(sl, ic), *_ = np.linalg.lstsq(A_*w[:,None], pts[:,1]*w, rcond=None)
r = np.corrcoef(pts[:,0], pts[:,1])[0,1]
print(f'\n  var = {sl:.4e}*mu + {ic:.4e}    corr(mu,var) = {r:+.4f}')
print(f'  -> read-noise floor sigma_0 = {np.sqrt(max(ic,0)):.5f} (linear units)')
if sl>0: print(f'  -> "electrons at mu=0.1": mu/a = {0.1/sl:.1f}')
# how much of the variance is signal-dependent over the observed range?
print(f'  signal-dependent share at mu=0.3: {sl*0.3/(sl*0.3+ic):.3f}')

# ---------- (B) banding ----------
print('\n=== (B) horizontal banding / AC flicker ===')
lit = (rho<0.80)&(~ui)
rowmean = np.array([G[y][lit[y]].mean() if lit[y].sum()>200 else np.nan for y in range(H)])
good = np.isfinite(rowmean)
ys = np.nonzero(good)[0]
rm = rowmean[good]
trend = ndi.uniform_filter1d(rm, 121)
res = (rm-trend)/np.maximum(trend,1e-6)
res = (res-res.mean())*np.hanning(len(res))
S = np.abs(np.fft.rfft(res, n=1<<15)); f = np.fft.rfftfreq(1<<15)
b = (f>0.004)&(f<0.35)
k = np.argsort(S[b])[::-1][:6]
print(f'row-mean modulation rms: {np.std((rm-trend)/np.maximum(trend,1e-6)):.5f}')
print(f'{"period(rows)":>13s} {"amplitude":>11s} {"SNR":>7s}')
for j in k:
    fr=f[b][j]; print(f'{1/fr:13.2f} {S[b][j]:11.4f} {S[b][j]/np.median(S[b]):7.1f}')
# same for columns (vertical banding => not flicker)
colmean = np.array([G[:,x][lit[:,x]].mean() if lit[:,x].sum()>200 else np.nan for x in range(W)])
cg=np.isfinite(colmean); cm=colmean[cg]; ct=ndi.uniform_filter1d(cm,121)
print(f'col-mean modulation rms: {np.std((cm-ct)/np.maximum(ct,1e-6)):.5f}  (for comparison)')

# ---------- (C) vignette profile ----------
print('\n=== (C) vignette radial profile ===')
prof=[]
for a in np.arange(0.0, 1.02, 0.02):
    s = (rho>=a)&(rho<a+0.02)&(~ui)
    if s.sum()>800: prof.append((a+0.01, np.median(G[s]), s.sum()))
prof=np.array(prof)
V = prof[:,1]/np.median(prof[prof[:,0]<0.35,1])
x = prof[:,0]
def cos4(r, f, s):  return s/(1+(r/f)**2)**2
def powr(r, n, s, r0): return s*np.clip(1-(r/r0)**n, 0, None)
def smooth(r, e0, e1, s):
    t = np.clip((e1-r)/(e1-e0), 0, 1); return s*(t*t*(3-2*t))
for name, fn, p0 in (('cos^4  V=s/(1+(r/f)^2)^2', cos4, [1.0, 1.0]),
                     ('power  V=s(1-(r/r0)^n)',    powr, [3.0, 1.0, 1.05]),
                     ('smoothstep',                smooth,[0.55, 1.02, 1.0])):
    try:
        p, _ = curve_fit(fn, x, V, p0=p0, maxfev=20000)
        rms = np.sqrt(np.mean((fn(x,*p)-V)**2))
        print(f'  {name:28s} rms {rms:.4f}   params {np.round(p,4)}')
    except Exception as e:
        print(f'  {name:28s} fit failed: {e}')
print('\n  r/R    V(measured)')
for xx, vv in zip(x[::4], V[::4]): print(f'  {xx:.2f}   {vv:.4f}')
np.save('data/vig_profile.npy', np.c_[x, V])
