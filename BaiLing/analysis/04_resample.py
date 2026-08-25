"""Stage 4 - separate the resampling comb from screen-locked dither.

Two periodic components sit in the tile: f~0.1046 and f~0.2488 cyc/screen-px.
A resampling comb must (a) give the same scale on both axes, (b) imply a
plausible delivered raster, and (c) live ONLY in resampled content. A
display-side dither is locked to the screen grid at exactly 0.25 and appears in
smooth OS-rendered gradients too. We test all three.
"""
import numpy as np
img = np.load('data/screen_u16.npy').astype(np.float64)/65535.0
G   = img.mean(axis=2)

def peak_in(a, axis, lo, hi, pad=1<<16):
    d2   = np.abs(np.diff(a, n=2, axis=axis))
    prof = d2.mean(axis=1-axis)
    prof = (prof-prof.mean())*np.hanning(len(prof))
    S = np.abs(np.fft.rfft(prof, n=pad)); f = np.fft.rfftfreq(pad)
    b = (f>lo)&(f<hi); j = np.argmax(S[b])
    return f[b][j], S[b][j]/np.median(S[b])

regions = {
 'photo tile (textured)'  : G[730:1530, 200:1000],
 'photo tile (2nd patch)' : G[400:1000, 300:900],
 'header avatar strip'    : G[190:280,  30:120],
 'bottom nav blur (smooth)': G[2440:2560, 100:1100],
 'flat chrome'            : G[2050:2150, 100:1100],
}
print(f"{'region':26s} {'axis':5s} {'f~0.10':>18s} {'f~0.25':>18s}")
for nm, R in regions.items():
    for axis, an in ((1,'x'),(0,'y')):
        if R.shape[axis] < 64: continue
        f1,s1 = peak_in(R, axis, 0.05, 0.16)
        f2,s2 = peak_in(R, axis, 0.20, 0.30)
        print(f'{nm:26s} {an:5s} {f1:.5f}(SNR{s1:5.1f}) {f2:.5f}(SNR{s2:5.1f})')

print('\n--- scale implied by the f~0.1046 comb (restricted band) ---')
tile = G[330:1938]
for axis, nm, N, exact in ((1,'horiz',1206,1080),(0,'vert',1608,1440)):
    f0,_ = peak_in(tile[100:-100,60:-60], axis, 0.05, 0.16)
    s = 1/(1-f0)
    print(f'{nm}: f0={f0:.6f}  s={s:.6f}  source={N/s:.2f}px  (exact {N}/{exact}={N/exact:.6f})')
print('\n--- is the 0.25 component locked to the screen grid? phase per slab ---')
for y0 in range(400, 1800, 200):
    sl = G[y0:y0+200, 200:1000]
    d2 = np.abs(np.diff(sl, n=2, axis=1)).mean(axis=0)
    z  = np.exp(-2j*np.pi*0.25*np.arange(len(d2)))
    ph = np.angle((d2-d2.mean())@z)
    print(f'  rows {y0:4d}-{y0+200:4d}: phase of 4-px component = {np.degrees(ph):7.1f} deg')
