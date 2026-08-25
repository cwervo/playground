"""Stage 31 - can the focal length be recovered at all?

The longitudinal VP sits ~150 px from the frame centre, i.e. the optical axis
was nearly parallel to the car. That is the classical DEGENERATE configuration
for vanishing-point calibration: lines parallel to the optical axis image as
rays through the principal point whose directions depend only on the lines'
lateral offsets, not on f (Caprile & Torre 1990). So f must come from the other
two families. We RANSAC a VP among the near-horizontal (transverse) segments
and pair it with the vertical VP, which is a well-conditioned pair if it exists.
"""
import numpy as np
from scipy.optimize import minimize
S = np.load('data/segs.npy')
mid, dirv, span = S[:,0:2], S[:,2:4], S[:,4]
CX, CY = 603.0, 804.0
ang = np.degrees(np.arctan2(dirv[:,1], dirv[:,0])) % 180

def ang_to(v,i):
    d=v-mid[i]; L=np.linalg.norm(d)
    return 90.0 if L<1e-9 else np.degrees(np.arccos(np.clip(abs((d/L)@dirv[i]),0,1)))
def ransac(idx, tol=2.0, iters=40000, seed=0):
    rng=np.random.default_rng(seed); best=(0,None,None)
    for _ in range(iters):
        i,j = rng.choice(idx,2,replace=False)
        if abs(dirv[i]@dirv[j])>0.9997: continue
        A=np.array([[dirv[i][1],-dirv[i][0]],[dirv[j][1],-dirv[j][0]]])
        b=np.array([dirv[i][1]*mid[i][0]-dirv[i][0]*mid[i][1],
                    dirv[j][1]*mid[j][0]-dirv[j][0]*mid[j][1]])
        try: v=np.linalg.solve(A,b)
        except np.linalg.LinAlgError: continue
        if not np.isfinite(v).all() or np.abs(v).max()>2e5: continue
        a=np.array([ang_to(v,q) for q in idx]); inl=a<tol
        sc=span[idx][inl].sum()
        if sc>best[0]: best=(sc,v,inl)
    return best
def refine(v, members):
    r=minimize(lambda w: sum(span[q]*ang_to(w,q)**2 for q in members), v,
               method='Nelder-Mead', options=dict(maxiter=4000,xatol=1e-3,fatol=1e-9))
    return r.x

HOR = np.nonzero((ang<28)|(ang>152))[0]
VER = np.nonzero((ang>62)&(ang<118))[0]
print(f'near-horizontal segments {len(HOR)} (span {span[HOR].sum():.0f}), '
      f'near-vertical {len(VER)} (span {span[VER].sum():.0f})')

sc,vH,inl = ransac(HOR, seed=5)
mH=[HOR[q] for q in np.nonzero(inl)[0]]
if len(mH)>=4:
    vH = refine(vH, mH)
    print(f'\ntransverse VP  = ({vH[0]:11.1f}, {vH[1]:11.1f})  {len(mH)} segs, '
          f'span {span[mH].sum():.0f}, resid {np.mean([ang_to(vH,q) for q in mH]):.2f} deg')
sc,vV,inl = ransac(VER, seed=6)
mV=[VER[q] for q in np.nonzero(inl)[0]]
if len(mV)>=4:
    vV = refine(vV, mV)
    print(f'vertical VP    = ({vV[0]:11.1f}, {vV[1]:11.1f})  {len(mV)} segs, '
          f'span {span[mV].sum():.0f}, resid {np.mean([ang_to(vV,q) for q in mV]):.2f} deg')

if len(mH)>=4 and len(mV)>=4:
    u1,w1 = vH[0]-CX, vH[1]-CY
    u2,w2 = vV[0]-CX, vV[1]-CY
    print(f'\northogonality product: u1u2 + w1w2 = {u1*u2:+.1f} + {w1*w2:+.1f} = {u1*u2+w1*w2:+.1f}')
    if u1*u2 + w1*w2 < 0:
        f = np.sqrt(-(u1*u2 + w1*w2))
        print(f'  square-pixel focal length f = {f:.1f} px (tile raster, 1206 wide)')
        print(f'  = {f/1.116667:.1f} px in the delivered 1080 raster')
        print(f'  horizontal FOV {2*np.degrees(np.arctan(1206/2/f)):.1f} deg, '
              f'vertical {2*np.degrees(np.arctan(1608/2/f)):.1f} deg, '
              f'diagonal {2*np.degrees(np.arctan(np.hypot(1206,1608)/2/f)):.1f} deg')
        print(f'  35mm-equivalent focal length = {43.267/(2*np.tan(np.radians(2*np.degrees(np.arctan(np.hypot(1206,1608)/2/f))/2))):.1f} mm')
    else:
        print('  -> POSITIVE: these two VPs cannot be images of orthogonal directions')
        print('     (the pair is degenerate or the families were mis-grouped)')
        print('     f is NOT recoverable from this image.')
