"""Stage 5 - resolve the second comb: an earlier resize in the chain.

Comb 1 (f=0.104477) = the 1080->1206 display upscale.
Comb 2 sits near 0.2488 cyc/screen-px. Referred back to the 1080 raster it is
f2*s2. If the photo was resized ONCE more before upload, that comb encodes the
pre-upload width. We measure f2 to high precision on long windows and test both
readings (upscale: W0 = 1080*(1-f); downscale: W0 = 1080*(1+f)).
"""
import numpy as np
img = np.load('data/screen_u16.npy').astype(np.float64)/65535.0
tile = img[330:1938].mean(axis=2)
s2 = 1206/1080.0

def precise_peak(prof, lo, hi):
    prof = (prof-prof.mean())*np.hanning(len(prof))
    N = 1<<20
    S = np.abs(np.fft.rfft(prof, n=N)); f = np.fft.rfftfreq(N)
    b = (f>lo)&(f<hi); j = np.argmax(S[b])
    fpk = f[b][j]
    # parabolic refinement on the padded spectrum is meaningless; instead do a
    # direct least-squares fit of a sinusoid over a fine grid
    x = np.arange(len(prof))
    grid = np.linspace(fpk-2e-3, fpk+2e-3, 4001)
    pw = np.array([abs(prof @ np.exp(-2j*np.pi*g*x)) for g in grid])
    return grid[np.argmax(pw)], S[b][j]/np.median(S[b])

print(f"{'axis':6s} {'f2(screen)':>12s} {'f2(1080 raster)':>16s} {'SNR':>6s}")
res={}
for axis, nm, ln in ((1,'horiz',1206),(0,'vert',1608)):
    d2 = np.abs(np.diff(tile[80:-80,80:-80], n=2, axis=axis)).mean(axis=1-axis)
    f2, snr = precise_peak(d2, 0.22, 0.28)
    res[nm]=f2*s2
    print(f'{nm:6s} {f2:12.6f} {f2*s2:16.6f} {snr:6.1f}')

f = 0.5*(res['horiz']+res['vert'])
print(f'\nmean f2 in the 1080 raster = {f:.6f}')
print(f'  as an UPSCALE   1-1/s1=f -> s1={1/(1-f):.6f}, pre-upload = {1080*(1-f):.2f} x {1440*(1-f):.2f}')
print(f'  as a DOWNSCALE  1/s1-1=f -> s1={1/(1+f):.6f}, pre-upload = {1080*(1+f):.2f} x {1440*(1+f):.2f}')
print('\n  nearby simple ratios for f:')
for num in range(1,20):
    for den in range(2,40):
        if abs(num/den - f) < 3e-4:
            print(f'    {num}/{den} = {num/den:.6f}  -> upscale src {1080*(1-num/den):.1f}, downscale src {1080*(1+num/den):.1f}')
