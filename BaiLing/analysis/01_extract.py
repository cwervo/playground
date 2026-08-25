"""Stage 1 - decode the screenshot at full 16-bit depth and isolate the photo.

The capture is a 1206x2622 16-bit Display-P3 PNG (cICP 12/13/0/1) - an iPhone
screenshot of an Instagram feed post. The photograph under study is the media
tile; everything above and below it is app chrome. We find the tile by row
statistics: chrome rows are flat near-black with sparse antialiased text, media
rows carry broadband structure.
"""
import numpy as np, zlib, struct, json

def decode_png16(path):
    raw = open(path, 'rb').read()
    i, idat, hdr = 8, [], None
    while i < len(raw):
        ln = struct.unpack('>I', raw[i:i+4])[0]; typ = raw[i+4:i+8]
        if typ == b'IHDR': hdr = struct.unpack('>IIBBBBB', raw[i+8:i+8+13])
        elif typ == b'IDAT': idat.append(raw[i+8:i+8+ln])
        i += 12 + ln
    w, h, depth, ctype = hdr[0], hdr[1], hdr[2], hdr[3]
    assert (depth, ctype) == (16, 2), (depth, ctype)
    data = zlib.decompress(b''.join(idat))
    bpp, stride = 6, w*6
    out = np.zeros((h, stride), np.uint8); prev = np.zeros(stride, np.uint8)
    p = 0
    for y in range(h):
        ft = data[p]; p += 1
        line = np.frombuffer(data[p:p+stride], np.uint8).copy(); p += stride
        if ft == 1:
            for x in range(bpp, stride): line[x] = (line[x] + line[x-bpp]) & 0xFF
        elif ft == 2: line = (line + prev) & 0xFF
        elif ft == 3:
            for x in range(stride):
                a = line[x-bpp] if x >= bpp else 0
                line[x] = (line[x] + ((int(a)+int(prev[x]))>>1)) & 0xFF
        elif ft == 4:
            for x in range(stride):
                a = int(line[x-bpp]) if x >= bpp else 0
                b = int(prev[x]); c = int(prev[x-bpp]) if x >= bpp else 0
                pp = a+b-c; pa,pb,pc = abs(pp-a),abs(pp-b),abs(pp-c)
                pr = a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[x] = (line[x] + pr) & 0xFF
        out[y] = line; prev = line
    return out.view('>u2').reshape(h, w, 3).astype(np.uint16)

img = decode_png16('data/screenshot_source.png')
print('decoded', img.shape, img.dtype, img.min(), img.max())
np.save('data/screen_u16.npy', img)

# Display-P3 with sRGB transfer (cICP 12/13/0/1) -> decode to linear P3
def srgb_to_linear(v):
    return np.where(v <= 0.04045, v/12.92, ((v+0.055)/1.055)**2.4)

enc = img.astype(np.float64)/65535.0
lin = srgb_to_linear(enc)
np.save('data/screen_linearP3.npy', lin.astype(np.float32))

# luminance in P3 primaries
Y = 0.2289746*lin[...,0] + 0.6917385*lin[...,1] + 0.0792869*lin[...,2]
np.save('data/screen_lumaP3.npy', Y.astype(np.float32))

# --- locate the media tile ---
g = enc.mean(axis=2)                       # gamma-domain grey, good for edges
row_energy = np.abs(np.diff(g, axis=1)).mean(axis=1)   # horizontal texture per row
row_ink    = (g > 0.06).mean(axis=1)

thr = 0.25 * row_energy.max()
active = row_energy > np.percentile(row_energy, 40)
print('\nrow  energy    ink')
for r in range(300, 2000, 25):
    print(f'{r:5d} {row_energy[r]:.5f} {row_ink[r]:.4f}')
np.save('data/row_energy.npy', row_energy)
