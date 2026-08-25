"""Stage 27 - joint (k, L) scan on the concurrency residual.

An affine stretch preserves straightness and concurrency, so it cannot be seen
in a line-straightness test alone. But it DOES break the radial symmetry of the
distortion: the true chain is  world -> radial distortion (isotropic) -> stretch
by k. Undistorting isotropically in the stretched frame is the wrong correction,
so the residual should be minimised at the true k. With only ~6% distortion the
sensitivity is weak, so we report the whole surface rather than a point estimate.
"""
import numpy as np
from scipy.optimize import minimize
S = np.load('data/segs.npy')
mid, dirv, span = S[:,0:2], S[:,2:4], S[:,4]
CX, CY, Rc = 602.86, 799.63, 660.0
E1 = mid - dirv*(span[:,None]/2); E2 = mid + dirv*(span[:,None]/2)
inl = np.load('data/rectilinearity.npy')
# recompute the VP1 inlier set at L=0, k=1
def undist(P, L, k):
    X = P[:,0]; Y = P[:,1]/k
    dx, dy = X-CX, Y-CY/1.0
    cy = CY/k
    dy = Y-cy
    s = (dx*dx+dy*dy)/(Rc*Rc); f = 1.0+L*s
    return np.c_[CX+dx/f, cy+dy/f]
def resid(idx, L, k):
    a, b = undist(E1[idx],L,k), undist(E2[idx],L,k)
    m = 0.5*(a+b); d = b-a; d/=np.linalg.norm(d,axis=1,keepdims=True)
    def cost(v):
        w=v-m; n=np.linalg.norm(w,axis=1)
        ang=np.degrees(np.arccos(np.clip(np.abs(np.einsum('ij,ij->i',w/n[:,None],d)),0,1)))
        return float(np.sum(span[idx]*ang**2)/np.sum(span[idx]))
    best=None
    for v0 in ([462,752/k],[300,700/k]):
        r=minimize(cost,v0,method='Nelder-Mead',options=dict(maxiter=2500,xatol=1e-3,fatol=1e-10))
        if best is None or r.fun<best.fun: best=r
    return np.sqrt(best.fun), best.x
def inliers(L,k,tol=1.6):
    _, v = resid(np.arange(len(S)), L, k)
    a,b = undist(E1,L,k), undist(E2,L,k)
    m=0.5*(a+b); d=b-a; d/=np.linalg.norm(d,axis=1,keepdims=True)
    w=v-m; n=np.linalg.norm(w,axis=1)
    ang=np.degrees(np.arccos(np.clip(np.abs(np.einsum('ij,ij->i',w/n[:,None],d)),0,1)))
    return np.nonzero(ang<tol)[0]
idx = inliers(0.0, 1.0)
print(f'support set: {len(idx)} segments\n')
ks = [1.00,1.05,1.10,1.15,1.20,1.25,4/3,1.40]
Ls = np.arange(-0.30, 0.11, 0.02)
print('        ' + ''.join(f'{k:8.3f}' for k in ks) + '   <- k')
best=(9e9,None,None)
grid=np.zeros((len(Ls),len(ks)))
for i,L in enumerate(Ls):
    row=[]
    for j,k in enumerate(ks):
        r,_ = resid(idx, L, k); grid[i,j]=r; row.append(r)
        if r<best[0]: best=(r,L,k)
    print(f'L={L:+5.2f} ' + ''.join(f'{v:8.4f}' for v in row))
print(f'\nminimum {best[0]:.4f} deg at L={best[1]:+.3f}, k={best[2]:.4f}')
mn = grid.min(axis=0)
print('\nbest residual for each k (profiling out L):')
for k,v in zip(ks, mn): print(f'  k={k:.4f}: {v:.4f} deg   (L={Ls[grid[:,k==np.array(ks)].argmin()]:+.2f})')
print(f'\nspread across k = {mn.max()-mn.min():.4f} deg; '
      f'per-segment angular noise ~{best[0]:.2f} deg')
print('If the spread is comparable to the noise, k is NOT determined by this test.')
np.save('data/kscan.npy', grid)
