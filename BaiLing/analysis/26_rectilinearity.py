"""Stage 26 - how rectilinear is the projection? (concurrency test)

37 straight segments spread across the frame meet at one point to 0.60 deg.
Under a fisheye projection the images of parallel 3D lines are CURVES that do
not share a common intersection, so chord-fits to them scatter badly. We
therefore scan the division-model parameter L: for each L we undistort the
segment endpoints, refit the vanishing point, and record the weighted angular
residual. The minimum locates the true distortion; the width of the valley is
the uncertainty. This also re-estimates the camera's pointing.
"""
import numpy as np
from scipy.optimize import minimize

S = np.load('data/segs.npy')
mid, dirv, span = S[:,0:2], S[:,2:4], S[:,4]
CX, CY, Rc = 602.86, 799.63, 660.0

def undist_pt(P, L):
    d = P - np.array([CX, CY])
    s = (d[...,0]**2 + d[...,1]**2)/(Rc*Rc)
    f = 1.0 + L*s
    return np.array([CX, CY]) + d/f[..., None]

# reconstruct approximate endpoints from midpoint/direction/span
E1 = mid - dirv*(span[:,None]/2)
E2 = mid + dirv*(span[:,None]/2)

def vp_fit(idx, L):
    a = undist_pt(E1[idx], L); b = undist_pt(E2[idx], L)
    m = 0.5*(a+b); d = b-a; d = d/np.linalg.norm(d, axis=1, keepdims=True)
    def cost(v):
        w = v - m; n = np.linalg.norm(w, axis=1)
        c = np.abs(np.einsum('ij,ij->i', w/n[:,None], d))
        ang = np.degrees(np.arccos(np.clip(c,0,1)))
        return float(np.sum(span[idx]*ang**2)/np.sum(span[idx]))
    best=None
    for v0 in ([462,752],[300,700],[600,800]):
        r = minimize(cost, v0, method='Nelder-Mead',
                     options=dict(maxiter=3000, xatol=1e-3, fatol=1e-10))
        if best is None or r.fun<best.fun: best=r
    return best.x, np.sqrt(best.fun)

# recover the VP1 inlier set at L=0
def inliers(v, L, tol=1.6):
    a = undist_pt(E1, L); b = undist_pt(E2, L)
    m = 0.5*(a+b); d = b-a; d/=np.linalg.norm(d,axis=1,keepdims=True)
    w = v-m; n=np.linalg.norm(w,axis=1)
    ang = np.degrees(np.arccos(np.clip(np.abs(np.einsum('ij,ij->i',w/n[:,None],d)),0,1)))
    return ang < tol, ang

v0, _ = vp_fit(np.arange(len(S)), 0.0)
inl, _ = inliers(np.array([462.0,751.6]), 0.0)
idx = np.nonzero(inl)[0]
print(f'VP1 support set: {len(idx)} segments, total span {span[idx].sum():.0f} px')
print(f'spread: x {mid[idx,0].min():.0f}..{mid[idx,0].max():.0f}  '
      f'y {mid[idx,1].min():.0f}..{mid[idx,1].max():.0f}')
print(f'radii from centre: {np.hypot(mid[idx,0]-CX, mid[idx,1]-CY).min():.0f}..'
      f'{np.hypot(mid[idx,0]-CX, mid[idx,1]-CY).max():.0f} px')

print(f'\n{"L":>8s} {"VP x":>9s} {"VP y":>9s} {"weighted ang resid (deg)":>26s}')
best=(1e9,None)
out=[]
for L in np.arange(-0.40, 0.41, 0.02):
    v, r = vp_fit(idx, L)
    out.append((L, v[0], v[1], r))
    if abs(L*100 - round(L*100)) < 1e-6 and round(L*100) % 4 == 0:
        print(f'{L:8.2f} {v[0]:9.1f} {v[1]:9.1f} {r:26.4f}')
    if r < best[0]: best=(r, L, v)
out=np.array(out)
r0 = out[np.argmin(np.abs(out[:,0]))][3]
print(f'\n  L = 0 (perfect rectilinear): residual {r0:.4f} deg')
print(f'  best L = {best[1]:+.3f}: residual {best[0]:.4f} deg')
ok = out[out[:,3] < best[0]*1.10]
print(f'  L within 10% of the minimum: [{ok[:,0].min():+.3f}, {ok[:,0].max():+.3f}]')
print(f'  => radial displacement at the field edge (r=Rc): '
      f'{Rc*(1/(1+ok[:,0].min())-1):+.1f} .. {Rc*(1/(1+ok[:,0].max())-1):+.1f} px')

# what would a fisheye look like on this test?
print('\n  For scale, the division-model L equivalent to common lenses over this field:')
for nm, Lval in (('mild wide-angle barrel', -0.05), ('strong barrel / GoPro-ish', -0.15),
                 ('full fisheye', -0.35)):
    print(f'    {nm:28s} L={Lval:+.2f} -> edge displacement '
          f'{Rc*(1/(1+Lval)-1):+.0f} px')
np.save('data/rectilinearity.npy', out)
