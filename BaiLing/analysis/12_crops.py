import numpy as np
from PIL import Image, ImageDraw
lin = np.load('data/screen_linearP3.npy')[330:1938]
def crop(name, x0,y0,x1,y1, g=3.0, zoom=2):
    a = np.clip(lin[y0:y1, x0:x1],0,1)**(1/g)
    im = Image.fromarray((a*255).astype(np.uint8))
    im = im.resize(((x1-x0)*zoom,(y1-y0)*zoom), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    for x in range(x0 - x0%50 + 50, x1, 50):
        d.line([((x-x0)*zoom,0),((x-x0)*zoom,(y1-y0)*zoom)], fill=(255,60,60)); d.text(((x-x0)*zoom+2,2),str(x),fill=(255,255,0))
    for y in range(y0 - y0%50 + 50, y1, 50):
        d.line([(0,(y-y0)*zoom),((x1-x0)*zoom,(y-y0)*zoom)], fill=(255,60,60)); d.text((2,(y-y0)*zoom+2),str(y),fill=(255,255,0))
    im.save(f'figures/{name}.png'); print(name, im.size)
crop('cropA_ceiling', 0, 0, 620, 320, g=3.2, zoom=2)
crop('cropB_leftwall', 0, 380, 340, 950, g=4.0, zoom=2)
crop('cropC_right', 860, 250, 1206, 800, g=4.0, zoom=2)
