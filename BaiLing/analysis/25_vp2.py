"""Stage 25 - Manhattan vanishing points -> fx, fy, and the pixel aspect k.

Sequential RANSAC with an ANGULAR consistency test (a segment supports v if the
angle between its direction and the direction from its midpoint to v is small),
weighted by segment length. Then, with the principal point pinned to the frame
centre, each orthogonal VP pair gives the linear constraint
    u1*u2 * A + w1*w2 * B = -1,     A = 1/fx^2, B = 1/fy^2
(Caprile & Torre 1990; Hartley & Zisserman sec. 8.6). Three VPs over-determine
(A,B), so the fit checks itself, and k = fy/fx is the anamorphic factor.
"""
import numpy as np
S = np.load('data/segs.npy')
mid = S[:,0:2]; dirv = S[:,2:4]; span = S[:,4]
N = len(S); print('segments', N)
CX, CY = 603.0, 804.0

def ang_to_vp(v, i):
    d = v - mid[i]; L = np.linalg.norm(d)
    if L < 1e-9: return 90.0
    c = abs((d/L) @ dirv[i])
    return np.degrees(np.arccos(np.clip(c,0,1)))

def ransac_vp(idx, iters=30000, tol=1.6, seed=0):
    rng = np.random.default_rng(seed); best=(0,None,None)
    for _ in range(iters):
        i,j = rng.choice(idx, 2, replace=False)
        if abs(dirv[i] @ dirv[j]) > 0.9995: continue
        A = np.array([[dirv[i][1], -dirv[i][0]],[dirv[j][1], -dirv[j][0]]])
        b = np.array([dirv[i][1]*mid[i][0]-dirv[i][0]*mid[i][1],
                      dirv[j][1]*mid[j][0]-dirv[j][0]*mid[j][1]])
        try: v = np.linalg.solve(A,b)
        except np.linalg.LinAlgError: continue
        if not np.isfinite(v).all() or np.abs(v).max() > 1e5: continue
        a = np.array([ang_to_vp(v,q) for q in idx])
        inl = a < tol
        sc = span[idx][inl].sum()
        if sc > best[0]: best=(sc, v, inl)
    return best

def refine(v, members, iters=200):
    """minimise sum_i span_i * angle(seg_i, v)^2"""
    from scipy.optimize import minimize
    def cost(v):
        return sum(span[q]*ang_to_vp(v,q)**2 for q in members)
    r = minimize(cost, v, method='Nelder-Mead',
                 options=dict(maxiter=4000, xatol=1e-3, fatol=1e-9))
    return r.x

rem = list(range(N)); vps=[]
for step in range(3):
    if len(rem) < 4: break
    sc, v, inl = ransac_vp(rem, seed=step)
    if v is None: break
    members = [rem[q] for q in np.nonzero(inl)[0]]
    if len(members) < 4: break
    v = refine(v, members)
    a = np.array([ang_to_vp(v,q) for q in members])
    print(f'\nVP{step+1} = ({v[0]:11.1f}, {v[1]:11.1f})   {len(members)} segments, '
          f'total span {span[members].sum():.0f}px, mean angular residual {a.mean():.2f} deg')
    for q in sorted(members, key=lambda z:-span[z])[:8]:
        print(f'     span {span[q]:6.1f} mid ({mid[q][0]:6.1f},{mid[q][1]:6.1f}) '
              f'dir ({dirv[q][0]:+.3f},{dirv[q][1]:+.3f}) resid {ang_to_vp(v,q):.2f}deg')
    vps.append((v, members))
    rem = [q for q in rem if q not in members]

print('\n--- orthogonality: principal point pinned to frame centre ---')
V=[v for v,_ in vps]
rows=[]; labs=[]
for i in range(len(V)):
    for j in range(i+1,len(V)):
        u1,w1 = V[i][0]-CX, V[i][1]-CY
        u2,w2 = V[j][0]-CX, V[j][1]-CY
        rows.append([u1*u2, w1*w2]); labs.append((i+1,j+1))
        print(f'  pair {labs[-1]}: u1u2 = {u1*u2:14.1f}   w1w2 = {w1*w2:14.1f}')
rows=np.array(rows); rhs=-np.ones(len(rows))
if len(rows)>=2:
    sol,res,rank,sv = np.linalg.lstsq(rows, rhs, rcond=None)
    A,B = sol
    print(f'\n  A = 1/fx^2 = {A:.5e}    B = 1/fy^2 = {B:.5e}')
    if A>0 and B>0:
        fx,fy = 1/np.sqrt(A), 1/np.sqrt(B)
        print(f'  fx = {fx:8.1f} px    fy = {fy:8.1f} px    k = fy/fx = {fy/fx:.4f}')
        print(f'  residual of the over-determined system: {rows@sol - rhs}')
        Wt,Ht = 1206.0, 1608.0
        print(f'\n  horizontal FOV = {2*np.degrees(np.arctan(Wt/2/fx)):.1f} deg')
        print(f'  vertical   FOV = {2*np.degrees(np.arctan(Ht/2/fy)):.1f} deg')
    else:
        print('  -> negative: the recovered VPs are not a consistent orthogonal triple')
    r2,*_ = np.linalg.lstsq(rows.sum(axis=1)[:,None], rhs, rcond=None)
    if r2[0]>0:
        f=1/np.sqrt(r2[0])
        print(f'\n  square-pixel constraint (k=1): f = {f:.1f} px  '
              f'-> HFOV {2*np.degrees(np.arctan(1206/2/f)):.1f} deg, '
              f'VFOV {2*np.degrees(np.arctan(1608/2/f)):.1f} deg')
np.save('data/vps2.npy', np.array([v for v,_ in vps]))
