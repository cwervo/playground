"""Stage 2 - cut the media tile and recover the delivered raster geometry.

Instagram serves feed media as JPEG at a fixed pixel width (historically 1080)
and the phone scales it to the tile width. If we can see the source 8x8 JPEG
block lattice in the screenshot we can measure that scale factor and therefore
know how many resamplings sit between us and the sensor.
"""
import numpy as np

img = np.load('data/screen_u16.npy')
TOP, BOT = 330, 1938          # non-chrome band
tile = img[TOP:BOT]
print('tile band', tile.shape)

# trim any partially-blended boundary row
def is_edge(r):
    return tile[r].astype(np.int32).std() < 200
print('row0 std', tile[0].astype(float).std(), 'rowlast std', tile[-1].astype(float).std())

tile = img[330:1938]
H, W = tile.shape[:2]
print(f'tile {W}x{H}  aspect {W}:{H} = 1:{H/W:.4f}')
np.save('data/tile_u16.npy', tile)

g = tile.astype(np.float64).mean(axis=2)/65535.0

# --- blocking-artifact lattice: 2nd difference energy, projected on each axis
d2x = np.abs(np.diff(g, n=2, axis=1)).mean(axis=0)
d2y = np.abs(np.diff(g, n=2, axis=0)).mean(axis=1)

def lattice_spectrum(sig, name):
    s = sig - sig.mean()
    s = s * np.hanning(len(s))
    S = np.abs(np.rfft(s)) if hasattr(np,'rfft') else np.abs(np.fft.rfft(s))
    f = np.fft.rfftfreq(len(s))
    band = (f > 0.05) & (f < 0.30)
    idx = np.argsort(S[band])[::-1][:6]
    print(f'\n{name}: dominant blocking frequencies (cyc/px) -> period')
    for k in idx:
        fr = f[band][k]
        print(f'   f={fr:.5f}  period={1/fr:.4f} px   power={S[band][k]:.4f}')
    return f, S

lattice_spectrum(d2x, 'horizontal')
lattice_spectrum(d2y, 'vertical')
