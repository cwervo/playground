"""Stage 14 - plumb-line estimation of radial distortion + anamorphic factor.

Inverse chain applied to each edge point:
  1. un-stretch:  X = x,  Y = y/k
  2. division model about (x0,y0):
        p_u = c + (p_d-c)/(1 + L1*s + L2*s^2),  s = |p_d-c|^2 / Rref^2
Straight world lines must straighten. To avoid the trivial optimum where the
map contracts everything to a point, straightness is measured SCALE-FREE as
sv2/sv1 of each chain's point cloud. A trimmed mean over chains rejects edges
that are genuinely curved in the world (grab rails, faces, spectacle rims).
Brown 1971 (plumb-line); Devernay & Faugeras 2001; Fitzgibbon 2001 (division).
"""
import numpy as np
from scipy.optimize import minimize

chains = [np.asarray(c, float) for c in np.load('data/chains.npy', allow_pickle=True)]
chains = [c for c in chains if len(c) >= 60]
Rref, NC = 800.0, len(chains)
print('chains used:', NC)

def undistort(P, x0, y0, L1, L2, k):
    X = P[:,0]; Y = P[:,1]/k
    dx, dy = X-x0, Y-y0
    s = (dx*dx+dy*dy)/(Rref*Rref)
    f = 1.0 + L1*s + L2*s*s
    f = np.where(np.abs(f) < 1e-3, 1e-3, f)
    return np.c_[x0+dx/f, y0+dy/f]

def straightness(Q):
    Qc = Q - Q.mean(0)
    sv = np.linalg.svd(Qc, compute_uv=False)
    return sv[1]/(sv[0]+1e-12), sv[1]/np.sqrt(len(Q)), sv[0]

BND = [(430,780),(560,1050),(-0.60,0.60),(-0.50,0.50)]
def objective(p, k, trim=0.55, report=False):
    for v,(a,b) in zip(p,BND):
        if not (a <= v <= b): return 1e3
    x0,y0,L1,L2 = p
    out = []
    for c in chains:
        Q = undistort(c, x0, y0, L1, L2, k)
        r, rms, ext = straightness(Q)
        out.append((r, rms, ext, len(c)))
    out = np.array(out)
    o = np.argsort(out[:,0]); m = o[:max(8,int(trim*NC))]
    val = float(np.average(out[m,0]**2, weights=out[m,3]))
    if report: return val, out, m
    return val

print(f'\n{"k":>7s} {"x0":>8s} {"y0(orig)":>9s} {"L1":>9s} {"L2":>9s} {"straightness":>13s} {"rms_perp(px)":>13s}')
res = {}
for k in [1.00,1.05,1.10,1.15,1.20,1.25,4/3,1.40]:
    best=None
    for L1g in (-0.30,-0.15,0.0,0.15,0.30):
        for c0 in ((603,804),(560,760),(650,850)):
            p0=np.array([c0[0], c0[1]/k, L1g, 0.0])
            r=minimize(objective,p0,args=(k,),method='Nelder-Mead',
                       options=dict(maxiter=2500,xatol=1e-4,fatol=1e-12))
            if best is None or r.fun<best.fun: best=r
    x0,y0,L1,L2=best.x
    v,out,m = objective(best.x,k,report=True)
    res[k]=(best.fun,best.x,np.average(out[m,1],weights=out[m,3]))
    print(f'{k:7.4f} {x0:8.2f} {y0*k:9.2f} {L1:9.5f} {L2:9.5f} {np.sqrt(v):13.6f} {res[k][2]:13.4f}')

base = objective([603,804,0.0,0.0],1.0)
print(f'\nNO-CORRECTION baseline straightness = {np.sqrt(base):.6f}')
kb=min(res,key=lambda k:res[k][0])
print(f'best k = {kb:.4f}  straightness {np.sqrt(res[kb][0]):.6f}  '
      f'(improvement vs baseline {100*(1-np.sqrt(res[kb][0]/base)):.1f}%)')
np.save('data/plumb.npy', np.array([[k,res[k][0],*res[k][1],res[k][2]] for k in res]))
