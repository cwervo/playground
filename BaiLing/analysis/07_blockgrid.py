"""Stage 7 - find every JPEG 8x8 block lattice surviving in the tile.

Each JPEG generation in the chain leaves an 8-px lattice in ITS OWN raster;
after later rescaling that lattice appears at a fractional screen period
P = 8 * (1206 / W_of_that_generation). Scanning P continuously and scoring
phase coherence therefore reads off the width of every JPEG stage.
(Method after Fan & de Queiroz 2003; Li, Luo & Huang, blocking-artefact
periodicity for double-JPEG / rescale detection.)
"""
import numpy as np
img  = np.load('data/screen_u16.npy').astype(np.float64)/65535.0
tile = img[330:1938].mean(axis=2)

def profile(a, axis):
    d2 = np.abs(np.diff(a, n=2, axis=axis)).mean(axis=1-axis)
    return d2 - d2.mean()

def coherence(prof, P):
    x = np.arange(len(prof))
    return abs(prof @ np.exp(-2j*np.pi*x/P)) / (np.abs(prof).sum()+1e-12)

for axis, nm, L in ((1,'horizontal',1206), (0,'vertical',1608)):
    pr = profile(tile[60:-60, 60:-60], axis)
    Ps = np.linspace(4.5, 20.0, 12000)
    C  = np.array([coherence(pr, P) for P in Ps])
    # local maxima
    pk = [i for i in range(2, len(C)-2) if C[i] == C[i-2:i+3].max()]
    pk.sort(key=lambda i: -C[i])
    print(f'\n--- {nm} (tile width {L}) : top block-lattice periods ---')
    print(f"{'period(px)':>11s} {'coh':>8s} {'implied JPEG raster width':>26s}")
    for i in pk[:8]:
        P = Ps[i]
        print(f'{P:11.4f} {C[i]:8.5f} {8*L/P:26.1f}')
    print('  predictions:')
    for w, lab in ((1080,'delivered IG JPEG'), (780,'upload @780 (hyp A)'),
                   (1380,'upload @1380 (hyp B)')):
        ww = w if axis==1 else int(round(w*4/3))
        print(f'    {lab:22s} raster {ww:5d} -> period {8*L/ww:7.4f} px')
