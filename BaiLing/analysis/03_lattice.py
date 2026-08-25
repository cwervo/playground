"""Stage 3 - how many pixels does the delivered image really have?

An image upsampled by factor s carries NO energy above f = 0.5/s cyc/px in the
screen raster; the spectrum shows a hard shelf there (Popescu & Farid 2005,
'Exposing digital forgeries by detecting traces of resampling'). We find the
shelf, and cross-check with the 1-D axis spectra.
"""
import numpy as np
img  = np.load('data/screen_u16.npy').astype(np.float64)/65535.0
tile = img[330:1938].mean(axis=2)

# a bright, richly textured square well inside the disc
patch = tile[520:1032, 340:852]
print('patch', patch.shape, 'mean', patch.mean().round(4))

win = np.outer(np.hanning(patch.shape[0]), np.hanning(patch.shape[1]))
P   = np.abs(np.fft.fftshift(np.fft.fft2(patch*win)))**2
n   = patch.shape[0]
fy, fx = np.meshgrid(np.fft.fftshift(np.fft.fftfreq(n)),
                     np.fft.fftshift(np.fft.fftfreq(n)), indexing='ij')

# radial average
r  = np.hypot(fx, fy)
bins = np.linspace(0, 0.7071, 200)
idx  = np.digitize(r.ravel(), bins)
prof = np.array([P.ravel()[idx==i].mean() if (idx==i).any() else np.nan
                 for i in range(1, len(bins))])
fr   = 0.5*(bins[1:]+bins[:-1])

lp = 10*np.log10(prof)
print('\nradial power spectrum (dB) vs frequency (cyc/screen-px)')
for i in range(0, 145, 5):
    print(f'  f={fr[i]:.4f}   {lp[i]:8.2f}')

# locate the steepest drop between 0.25 and 0.50
sel = (fr > 0.22) & (fr < 0.52)
d   = np.gradient(lp[sel], fr[sel])
fcut = fr[sel][np.argmin(d)]
print(f'\nsteepest roll-off at f = {fcut:.4f} cyc/px  -> implied upscale s = {0.5/fcut:.4f}')
print(f'   implied delivered width = {1206*fcut/0.5:.1f} px')
for w in (720, 750, 1080, 1200, 1440):
    print(f'   if delivered width {w}: s={1206/w:.4f}, expected shelf at f={0.5*w/1206:.4f}')

# axis spectra (nearest/bilinear upsampling leaves replica peaks at k/s)
for ax, nm in ((1,'horizontal'), (0,'vertical')):
    d1 = np.diff(patch, axis=ax)
    s  = d1.mean(axis=1-ax); s = (s-s.mean())*np.hanning(len(s))
    S  = np.abs(np.fft.rfft(s)); f = np.fft.rfftfreq(len(s))
    k  = np.argsort(S[(f>0.05)])[::-1][:5]
    print(f'\n{nm} replica peaks:', [(round(float(f[f>0.05][j]),4), round(float(1/f[f>0.05][j]),3)) for j in k])
np.save('data/radial_spectrum.npy', np.vstack([fr, prof]))
