"""Stage 11 - shadow-lifted previews with a coordinate grid, for feature picking."""
import numpy as np
from PIL import Image, ImageDraw

lin  = np.load('data/screen_linearP3.npy')[330:1938]
H, W = lin.shape[:2]

def tone(x, g):
    return np.clip(x, 0, 1)**(1.0/g)

for gname, g in (('g22', 2.2), ('g40', 4.0), ('g70', 7.0)):
    out = (tone(lin, g)*255).astype(np.uint8)
    im  = Image.fromarray(out)
    d   = ImageDraw.Draw(im)
    for x in range(0, W, 100):
        d.line([(x,0),(x,H)], fill=(255,0,0) if x%500 else (0,255,255), width=1)
        d.text((x+3, 4), str(x), fill=(255,255,0))
    for y in range(0, H, 100):
        d.line([(0,y),(W,y)], fill=(255,0,0) if y%500 else (0,255,255), width=1)
        d.text((4, y+3), str(y), fill=(255,255,0))
    im.resize((W//2, H//2), Image.LANCZOS).save(f'figures/preview_{gname}.png')
    print('wrote', f'figures/preview_{gname}.png')

# clean copy, no grid, full res
Image.fromarray((tone(lin, 3.0)*255).astype(np.uint8)).save('data/photo_lifted.png')
Image.fromarray((tone(lin, 2.2)*255).astype(np.uint8)).save('data/photo_srgb.png')
print('tile', W, 'x', H)
