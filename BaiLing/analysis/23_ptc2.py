"""Stage 23 - PTC over the full dynamic range, banding significance, and a
scene-robust vignette profile.

(A) The tile PTC is repeated with a wide texture allowance and a local-plane
    detrend, so bright tiles are admitted and the dynamic range spans ~2 decades.
(B) Banding is only real if the ROW spectrum carries a NARROW line absent from
    the COLUMN spectrum (scene structure is isotropic in that sense).
(C) The vignette is recovered as a high percentile per annulus: highlights occur
    at every radius, so their envelope tracks the illumination falloff instead
    of the scene's own brightness gradient.
"""
import numpy as np
from scipy import ndimage as ndi
from scipy.optimize import curve_fit

lin = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
rho = np.load('data/rho_map.npy'); H, W = rho.shape
ui = np.zeros((H,W), bool)
for y0,y1,x0,x1 in [(40,130,1040,1170),(1480,1580,1080,1170)]: ui[y0:y1,x0:x1]=True
G = lin.mean(axis=2)

# ---------- (A) PTC, wide range ----------
P = 12
hh, ww = (H//P)*P, (W//P)*P
def tl(a): return a[:hh,:ww].reshape(hh//P,P,ww//P,P)
Gt = tl(G)
# local plane detrend inside each tile, then MAD of the residual
yy, xx = np.mgrid[0:P,0:P]
Abas = np.c_[np.ones(P*P), yy.ravel(), xx.ravel()]
Q, _ = np.linalg.qr(Abas)
flat_t = Gt.transpose(0,2,1,3).reshape(-1, P*P)
resid = flat_t - (flat_t @ Q) @ Q.T
sig = 1.4826*np.median(np.abs(resid - np.median(resid,axis=1,keepdims=True)), axis=1)
mu  = flat_t.mean(axis=1)
curv = np.abs(resid).mean(axis=1)/ (sig+1e-12)
rr  = tl(rho).mean(axis=(1,3)).ravel()
uu  = tl(ui.astype(float)).mean(axis=(1,3)).ravel()
ok = (uu<0.01)&(rr<0.85)&(curv<1.35)&(mu>1e-4)
print(f'=== (A) PTC, linear light, {ok.sum()} tiles, mu range '
      f'{mu[ok].min():.5f}..{mu[ok].max():.5f} ===')
print(f'{"mu":>11s} {"n":>5s} {"sigma":>11s} {"var":>12s}')
pts=[]
ed = np.exp(np.linspace(np.log(mu[ok].min()+1e-9), np.log(mu[ok].max()), 15))
for i in range(len(ed)-1):
    s = ok & (mu>=ed[i]) & (mu<ed[i+1])
    if s.sum()<15: continue
    a_, b_ = np.median(mu[s]), np.median(sig[s])
    print(f'{a_:11.6f} {s.sum():5d} {b_:11.6f} {b_**2:12.4e}')
    pts.append((a_, b_**2, s.sum()))
pts=np.array(pts)
Am = np.c_[pts[:,0], np.ones(len(pts))]; w=np.sqrt(pts[:,2])
(sl,ic),*_ = np.linalg.lstsq(Am*w[:,None], pts[:,1]*w, rcond=None)
print(f'\n  linear fit  var = {sl:.4e}*mu + {ic:.4e}')
print(f'  corr(mu,var) = {np.corrcoef(pts[:,0],pts[:,1])[0,1]:+.4f}')
print(f'  read floor sigma0 = {np.sqrt(max(ic,0)):.6f}')
# power-law fit var = c*mu^p  -> p=1 Poisson, p=2 multiplicative/gain noise
lp = np.polyfit(np.log(pts[:,0]), np.log(pts[:,1]), 1, w=np.sqrt(pts[:,2]))
print(f'  power law   var ~ mu^{lp[0]:.3f}   (1.0 = pure shot noise, 2.0 = multiplicative)')
print(f'  effective full-scale electrons 1/a = {1/sl:.0f} e- equivalent')
np.save('data/ptc2.npy', pts)

# ---------- (B) banding significance ----------
print('\n=== (B) banding: row vs column spectra ===')
lit = (rho<0.80)&(~ui)
def modspec(profile):
    g = np.isfinite(profile); p = profile[g]
    t = ndi.uniform_filter1d(p, 101)
    r = (p-t)/np.maximum(t,1e-6)
    r = (r-r.mean())*np.hanning(len(r))
    S = np.abs(np.fft.rfft(r, n=1<<15)); f=np.fft.rfftfreq(1<<15)
    return f, S, np.std((p-t)/np.maximum(t,1e-6))
rowm = np.array([G[y][lit[y]].mean() if lit[y].sum()>250 else np.nan for y in range(H)])
colm = np.array([G[:,x][lit[:,x]].mean() if lit[:,x].sum()>250 else np.nan for x in range(W)])
fr,Sr,vr = modspec(rowm); fc,Sc,vc = modspec(colm)
br=(fr>0.005)&(fr<0.4); bc=(fc>0.005)&(fc<0.4)
print(f'row modulation rms {vr:.4f} | col modulation rms {vc:.4f}')
print(f'row peak/median {Sr[br].max()/np.median(Sr[br]):.1f} at period '
      f'{1/fr[br][np.argmax(Sr[br])]:.1f} rows')
print(f'col peak/median {Sc[bc].max()/np.median(Sc[bc]):.1f} at period '
      f'{1/fc[bc][np.argmax(Sc[bc])]:.1f} cols')
# narrowness: width of the row peak at half power
i = np.argmax(Sr[br]); pk=Sr[br][i]
half = np.nonzero(Sr[br] > pk/2)[0]
seg = half[(half>=i-400)&(half<=i+400)]
print(f'row peak half-power width: {(fr[br][seg.max()]-fr[br][seg.min()]):.5f} cyc/row '
      f'-> Q = {fr[br][i]/max(fr[br][seg.max()]-fr[br][seg.min()],1e-9):.1f}')
print('  (a mains-flicker line is narrow, Q >> 10, and shows harmonics)')

# ---------- (C) vignette via per-annulus high percentile ----------
print('\n=== (C) vignette profile from the highlight envelope ===')
prof=[]
for a in np.arange(0.0, 1.06, 0.02):
    s = (rho>=a)&(rho<a+0.02)&(~ui)
    if s.sum()>600:
        prof.append((a+0.01, np.percentile(G[s], 92), np.percentile(G[s],75), s.sum()))
prof=np.array(prof)
norm = prof[prof[:,0]<0.30,1].mean()
V = prof[:,1]/norm; x = prof[:,0]
def cos4(r,f,s):    return s/(1+(r/f)**2)**2
def powr(r,n,s,r0): return s*np.clip(1-(r/r0)**n,0,None)
def smoothstep(r,e0,e1,s):
    t=np.clip((e1-r)/(e1-e0),0,1); return s*t*t*(3-2*t)
print(f'{"model":<34s} {"rms":>7s}  params')
for nm, fn, p0 in (('natural cos^4  s/(1+(r/f)^2)^2', cos4, [1.0,1.0]),
                   ('power  s(1-(r/r0)^n)',           powr, [4.0,1.0,1.03]),
                   ('smoothstep(e0,e1)',              smoothstep,[0.5,1.02,1.0])):
    try:
        p,_ = curve_fit(fn, x, V, p0=p0, maxfev=40000)
        print(f'{nm:<34s} {np.sqrt(np.mean((fn(x,*p)-V)**2)):7.4f}  {np.round(p,4)}')
    except Exception as e: print(f'{nm:<34s}  failed {e}')
print('\n  rho   V(p92)   V(p75)')
for row in prof[::2]:
    print(f'  {row[0]:.2f}   {row[1]/norm:.4f}   {row[2]/np.mean(prof[prof[:,0]<0.30,2]):.4f}')
np.save('data/vig_profile.npy', np.c_[x, V])
