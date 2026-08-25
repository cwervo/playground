"""Stage 29 - grain autocorrelation -> the EFFECTIVE sample spacing.

Sensor noise is white at the photosite; every subsequent resize convolves it
with the interpolation kernel. So the width of the noise autocorrelation,
measured on the screen raster, reveals how many screen pixels one original
sample now covers - i.e. the true resolving power behind the delivered file
(cf. Popescu & Farid 2005; Kirchner 2008 on resampling and noise correlation).
"""
import numpy as np
from scipy import ndimage as ndi
lin = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
enc = np.load('data/screen_u16.npy')[330:1938].astype(np.float64)/65535.0
rho = np.load('data/rho_map.npy')
G = enc.mean(axis=2)
hp = G - ndi.gaussian_filter(G, 2.5)             # high-pass = noise + fine detail

# flat patches only, so "detail" is negligible
lo = ndi.gaussian_filter(G, 4.0)
tex = ndi.gaussian_filter(np.abs(ndi.gaussian_filter(G,1.0)-lo), 6.0)
P = 48
acc = np.zeros((P,P)); n = 0
for y in range(0, G.shape[0]-P, 24):
    for x in range(0, G.shape[1]-P, 24):
        if rho[y+P//2, x+P//2] > 0.75: continue
        t = tex[y+P//2, x+P//2]
        if t > np.percentile(tex[rho<0.75], 25): continue
        p = hp[y:y+P, x:x+P]
        p = p - p.mean()
        F = np.fft.fft2(p)
        acc += np.real(np.fft.ifft2(F*np.conj(F))); n += 1
acc /= n
ac = np.fft.fftshift(acc); ac /= ac.max()
c = P//2
print(f'patches averaged: {n}')
print('\nnoise autocorrelation (normalised), central 9x9:')
print('        ' + ''.join(f'{d:+7d}' for d in range(-4,5)))
for dy in range(-4,5):
    print(f'  dy={dy:+2d} ' + ''.join(f'{ac[c+dy, c+dx]:+7.3f}' for dx in range(-4,5)))

def width(prof):
    """half-width at 1/e of the 1-D autocorrelation slice"""
    x = np.arange(len(prof))
    k = np.nonzero(prof < 1/np.e)[0]
    if not len(k): return np.nan
    j = k[0]
    if j == 0: return 0.0
    return np.interp(1/np.e, [prof[j], prof[j-1]], [j, j-1])
wx = width(ac[c, c:]); wy = width(ac[c:, c])
print(f'\n1/e half-width: horizontal {wx:.2f} screen px, vertical {wy:.2f} screen px')
s2 = 1206/1080.0
print(f'  in the delivered 1080-raster: {wx/s2:.2f} x {wy/s2:.2f} px')
# equivalent independent-sample count
print(f'\nequivalent independent samples across the frame:')
for nm, w in (('horizontal', wx), ('vertical', wy)):
    print(f'  {nm}: {1206/max(w,1e-6):.0f} (screen 1206) '
          f'/ {1080/max(wx/s2,1e-6) if nm=="horizontal" else 1440/max(wy/s2,1e-6):.0f} (delivered)')

# radial noise power spectrum, to see the kernel
F = np.fft.fftshift(np.abs(np.fft.fft2(np.fft.ifftshift(acc))))
f1 = np.fft.fftshift(np.fft.fftfreq(P))
print('\nnoise power vs spatial frequency (horizontal slice, dB rel. DC):')
row = F[c]; row = row/row.max()
for j in range(c, P):
    if (j-c) % 2 == 0:
        print(f'  f={f1[j]:.4f} cyc/screen-px  ({f1[j]*s2:.4f} cyc/1080-px)  '
              f'{10*np.log10(max(row[j],1e-12)):7.2f} dB')
np.save('data/grain_ac.npy', ac)
