"""Stage 28 - bootstrap the distortion estimate.

Stages 26 and 27 disagreed because each chose its own inlier set. Here the
support set is fixed once (the VP1 family), the scan is widened so any minimum
is interior, and the segments are resampled with replacement 300 times so the
uncertainty on L is measured rather than asserted.
"""
import numpy as np
from scipy.optimize import minimize
S = np.load('data/segs.npy')
mid, dirv, span = S[:,0:2], S[:,2:4], S[:,4]
CX, CY, Rc = 602.86, 799.63, 660.0
E1 = mid - dirv*(span[:,None]/2); E2 = mid + dirv*(span[:,None]/2)

def undist(P, L):
    d = P - np.array([CX, CY])
    s = (d[:,0]**2 + d[:,1]**2)/(Rc*Rc)
    return np.array([CX,CY]) + d/(1.0+L*s)[:,None]

def fit(idx, L, w=None):
    a, b = undist(E1[idx], L), undist(E2[idx], L)
    m = 0.5*(a+b); d = b-a; d/=np.linalg.norm(d,axis=1,keepdims=True)
    ww = span[idx] if w is None else w
    def cost(v):
        u = v-m; n=np.linalg.norm(u,axis=1)
        ang=np.degrees(np.arccos(np.clip(np.abs(np.einsum('ij,ij->i',u/n[:,None],d)),0,1)))
        return float(np.sum(ww*ang**2)/np.sum(ww))
    best=None
    for v0 in ([462,752],[300,700],[700,850]):
        r=minimize(cost,v0,method='Nelder-Mead',options=dict(maxiter=2500,xatol=1e-3,fatol=1e-11))
        if best is None or r.fun<best.fun: best=r
    return np.sqrt(best.fun), best.x

# fixed support set: VP1 family at L=0
V1 = np.array([461.4, 750.9])
a,b = undist(E1,0.0), undist(E2,0.0)
m=0.5*(a+b); d=b-a; d/=np.linalg.norm(d,axis=1,keepdims=True)
u=V1-m; n=np.linalg.norm(u,axis=1)
ang=np.degrees(np.arccos(np.clip(np.abs(np.einsum('ij,ij->i',u/n[:,None],d)),0,1)))
IDX = np.nonzero(ang<1.6)[0]
print(f'fixed support set: {len(IDX)} segments, span {span[IDX].sum():.0f} px, '
      f'radii {np.hypot(mid[IDX,0]-CX,mid[IDX,1]-CY).min():.0f}..'
      f'{np.hypot(mid[IDX,0]-CX,mid[IDX,1]-CY).max():.0f} px')

Ls = np.arange(-0.70, 0.22, 0.02)
R = np.array([fit(IDX, L)[0] for L in Ls])
print(f'\n{"L":>7s} {"resid(deg)":>11s}')
for L,r in zip(Ls,R):
    if abs(round(L*100)) % 6 == 0: print(f'{L:7.2f} {r:11.4f}')
i = np.argmin(R)
print(f'\npoint estimate: L = {Ls[i]:+.3f}, residual {R[i]:.4f} deg '
      f'(interior minimum: {0 < i < len(Ls)-1})')

rng = np.random.default_rng(7)
boot=[]
for t in range(300):
    w = rng.poisson(1.0, len(IDX)).astype(float)*span[IDX]
    if w.sum() <= 0: continue
    rr = np.array([fit(IDX, L, w)[0] for L in Ls])
    boot.append(Ls[np.argmin(rr)])
boot=np.array(boot)
print(f'\nbootstrap over segments (n={len(boot)}):')
print(f'  L median {np.median(boot):+.3f}   16-84 pct [{np.percentile(boot,16):+.3f}, '
      f'{np.percentile(boot,84):+.3f}]   2.5-97.5 pct [{np.percentile(boot,2.5):+.3f}, '
      f'{np.percentile(boot,97.5):+.3f}]')
print(f'  fraction of bootstraps with L < -0.25 (fisheye-like): {(boot<-0.25).mean():.3f}')
print(f'  fraction with L > -0.02 (essentially rectilinear):    {(boot>-0.02).mean():.3f}')
lo, hi = np.percentile(boot,2.5), np.percentile(boot,97.5)
print(f'\n  radial displacement at field edge r={Rc:.0f}px: '
      f'{Rc*(1/(1+np.median(boot))-1):+.0f} px '
      f'[{Rc*(1/(1+hi)-1):+.0f}, {Rc*(1/(1+lo)-1):+.0f}]')
print(f'  i.e. {100*(1/(1+np.median(boot))-1):+.1f}% barrel at the field edge')
np.save('data/boot_L.npy', boot)
