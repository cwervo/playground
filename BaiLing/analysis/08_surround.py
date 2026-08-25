"""Stage 8 - is the dark surround an optical image circle or a painted mask?

Discriminators:
  * a MASK forces values to a constant (usually exactly 0) with zero variance;
  * an OPTICAL cutoff leaves residual flare/veiling glare and, crucially,
    leaves the SENSOR NOISE running (variance > 0, and correlated with the
    codec's block structure, not with scene content).
We examine the four corners of the tile.
"""
import numpy as np
img16 = np.load('data/screen_u16.npy')
tile16 = img16[330:1938]
lin  = np.load('data/screen_linearP3.npy')[330:1938]
enc  = tile16.astype(np.float64)/65535.0
H, W = enc.shape[:2]

def report(name, sl):
    b = tile16[sl]
    e = enc[sl]
    print(f'\n{name}  block {b.shape[0]}x{b.shape[1]}')
    for c, ch in enumerate('RGB'):
        v = b[..., c]
        print(f'   {ch}: min {v.min():6d} max {v.max():6d} mean {v.mean():8.1f} '
              f'std {v.std():7.2f}  #distinct {np.unique(v).size:5d}  '
              f'frac==0 {(v==0).mean():.4f}')
    g = e.mean(axis=2)
    print(f'   grey mean {g.mean():.5f}  std {g.std():.5f}')

corner = 200
report('top-left    ', (np.s_[0:corner], np.s_[0:corner]))
report('top-right   ', (np.s_[0:corner], np.s_[W-corner:W]))
report('bottom-left ', (np.s_[H-corner:H], np.s_[0:corner]))
report('bottom-right', (np.s_[H-corner:H], np.s_[W-corner:W]))
report('centre ref  ', (np.s_[700:900], np.s_[500:700]))

# how black is blackest? and is there a floor pedestal?
g = enc.mean(axis=2)
print('\nglobal tile: min', g.min(), ' 0.1th pct', np.percentile(g,0.1),
      ' 1st pct', np.percentile(g,1), ' frac exactly 0:', (tile16==0).all(axis=2).mean())
