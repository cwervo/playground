"""Stage 30 - is the grain autocorrelation isotropic? (the anamorphic test)

Photosite noise is white; every resize convolves it with that resize's kernel.
A frame stretched vertically by k therefore carries a noise autocorrelation
k times wider vertically than horizontally. Measuring the ratio tests the
'square crop stretched to 3:4' hypothesis directly, and unlike the plumb-line
tests it is SENSITIVE to an affine stretch (which preserves straightness).
Bootstrapped over patches for an honest error bar.
"""
import numpy as np
from scipy import ndimage as ndi
enc = np.load('data/screen_u16.npy')[330:1938].astype(np.float64)/65535.0
rho = np.load('data/rho_map.npy')
G = enc.mean(axis=2)
hp = G - ndi.gaussian_filter(G, 2.5)
lo = ndi.gaussian_filter(G, 4.0)
tex = ndi.gaussian_filter(np.abs(ndi.gaussian_filter(G,1.0)-lo), 6.0)
thr = np.percentile(tex[rho<0.75], 25)
P = 48
patches=[]
for y in range(0, G.shape[0]-P, 16):
    for x in range(0, G.shape[1]-P, 16):
        if rho[y+P//2,x+P//2] > 0.75: continue
        if tex[y+P//2,x+P//2] > thr: continue
        p = hp[y:y+P,x:x+P]; patches.append(p-p.mean())
patches=np.array(patches); print('patches', len(patches))
F = np.fft.fft2(patches, axes=(1,2))
PS = np.real(F*np.conj(F))

def widths(ps):
    ac = np.fft.fftshift(np.real(np.fft.ifft2(ps)))
    ac = ac/ac.max(); c = P//2
    def w(prof):
        k=np.nonzero(prof<1/np.e)[0]
        if not len(k) or k[0]==0: return np.nan
        j=k[0]; return np.interp(1/np.e,[prof[j],prof[j-1]],[j,j-1])
    return w(ac[c,c:]), w(ac[c:,c])

wx, wy = widths(PS.mean(axis=0))
print(f'full sample: wx {wx:.3f}  wy {wy:.3f}  ratio wy/wx {wy/wx:.4f}')
rng=np.random.default_rng(3); rat=[]
for _ in range(400):
    s = rng.integers(0, len(patches), len(patches))
    a,b = widths(PS[s].mean(axis=0))
    if np.isfinite(a) and np.isfinite(b): rat.append(b/a)
rat=np.array(rat)
print(f'bootstrap ratio wy/wx: median {np.median(rat):.4f}  '
      f'95% CI [{np.percentile(rat,2.5):.4f}, {np.percentile(rat,97.5):.4f}]')
print(f'  hypothesis k=1.0000 (no stretch)   -> {"CONSISTENT" if np.percentile(rat,2.5)<=1.0<=np.percentile(rat,97.5) else "REJECTED"}')
print(f'  hypothesis k=1.3333 (square->3:4)  -> {"CONSISTENT" if np.percentile(rat,2.5)<=4/3<=np.percentile(rat,97.5) else "REJECTED"}')
# also the reverse convention (frame squeezed horizontally)
print(f'  hypothesis k=0.7500                -> {"CONSISTENT" if np.percentile(rat,2.5)<=0.75<=np.percentile(rat,97.5) else "REJECTED"}')
np.save('data/aniso_boot.npy', rat)
