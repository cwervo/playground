"""Stage 6 - which direction was the 5/18 resize, and is there an earlier one?

Upscaling band-limits: an image enlarged from W0 to 1080 has no genuine signal
above (W0/1080)/2 cyc/1080-px; only later-added grain lives there. Downscaling
does not band-limit. We look for the shelf, and then sweep the residual
spectrum for any further comb.
"""
import numpy as np
img  = np.load('data/screen_u16.npy').astype(np.float64)/65535.0
tile = img[330:1938].mean(axis=2)
s2   = 1206/1080.0

# 1-D horizontal spectrum, averaged over many textured rows, Welch style
rows = tile[560:1360, 180:1020]
seg  = 512
acc  = np.zeros(seg//2+1)
n    = 0
for y in range(0, rows.shape[0]-1, 7):
    for x0 in range(0, rows.shape[1]-seg, seg//2):
        r = rows[y, x0:x0+seg]
        if r.mean() < 0.05: continue
        r = (r-r.mean())*np.hanning(seg)
        acc += np.abs(np.fft.rfft(r))**2; n += 1
acc /= n
f = np.fft.rfftfreq(seg)
db = 10*np.log10(acc/acc.max())
print(f'averaged {n} segments')
print('\n f(screen)  f(1080)   dB')
for i in range(8, seg//2+1, 6):
    print(f'  {f[i]:.4f}   {f[i]*s2:.4f}  {db[i]:7.2f}')

print('\npredicted band-limit if uploaded at 780 wide (upscale): '
      f'f_1080={0.5*780/1080:.4f} -> f_screen={0.5*780/1080/s2:.4f}')
print( 'predicted band-limit if 1380->1080 (downscale): none (aliased, flat to Nyquist)')

# noise floor: fit floor above 0.42 and signal slope below 0.25, find knee
hi = db[(f>0.42)].mean()
print(f'\nhigh-frequency floor ({0.42:.2f}-0.50) = {hi:.2f} dB')
k = np.where(db < hi+3)[0]
print(f'first frequency reaching floor+3dB: f_screen={f[k[0]]:.4f}  f_1080={f[k[0]]*s2:.4f}')
np.save('data/spec1d.npy', np.vstack([f, acc]))
