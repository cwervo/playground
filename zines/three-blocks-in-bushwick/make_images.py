"""Derive the zine's images from the single source photograph.

The source is a phone camera-app screenshot (1206 x 2622, saved as JPEG). Coordinates below
were picked on a 920 px wide preview, so everything is scaled by S.
"""
from PIL import Image, ImageOps

SRC = "img/source-screenshot.jpg"
S = 1206 / 920

im = Image.open(SRC).convert("RGB")

def crop(box, name, scale=1, contrast=0, quality=88):
    x0, y0, x1, y1 = [int(v * S) for v in box]
    c = im.crop((x0, y0, x1, y1))
    if scale != 1:
        c = c.resize((int(c.width * scale), int(c.height * scale)), Image.LANCZOS)
    if contrast:
        c = ImageOps.autocontrast(c, cutoff=contrast)
    c.save(f"img/{name}.jpg", quality=quality, optimize=True)
    print(name, c.size)

# The viewfinder, minus the camera UI above and below it.
crop((0, 300, 920, 1385), "cover", quality=90)
# The painted wall behind the taxpayer.
crop((0, 600, 640, 900), "ghost-sign", scale=2, contrast=1)
# Sunnyvale's blue letters.
crop((40, 900, 330, 1050), "sunnyvale", scale=2)
# The CityMD sign with the camera's focus bracket.
crop((380, 860, 920, 990), "citymd", scale=2)
# The bus shelter and its lawyer.
crop((470, 1010, 640, 1260), "shelter", scale=2)
# The wet street.
crop((0, 1230, 920, 1385), "street", quality=85)
