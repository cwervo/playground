"""Impose a sequential A5 PDF as a saddle-stitched booklet on A4 landscape sheets.

usage: python3 impose.py out/pages.pdf out/booklet.pdf

Print the result double-sided, "flip on short edge", fold the stack in half,
staple twice on the fold. Page count is padded to a multiple of four.
"""
import sys
from pypdf import PdfReader, PdfWriter, Transformation
from pypdf.generic import RectangleObject

A5_W, A5_H = 148 / 25.4 * 72, 210 / 25.4 * 72
A4_W, A4_H = 297 / 25.4 * 72, 210 / 25.4 * 72

src = PdfReader(sys.argv[1])
n = len(src.pages)
padded = (n + 3) // 4 * 4
out = PdfWriter()

def place(sheet, idx, left):
    if idx >= n:
        return
    page = src.pages[idx]
    sheet.merge_transformed_page(page, Transformation().translate(0 if left else A5_W, 0))

# Sheet k, front: [last-2k | 1+2k]; back: [2+2k | last-1-2k]  (1-based pages)
for k in range(padded // 4):
    front = out.add_blank_page(width=A4_W, height=A4_H)
    place(front, padded - 1 - 2 * k, True)
    place(front, 2 * k, False)
    back = out.add_blank_page(width=A4_W, height=A4_H)
    place(back, 2 * k + 1, True)
    place(back, padded - 2 - 2 * k, False)

with open(sys.argv[2], "wb") as f:
    out.write(f)
print(f"{n} pages ({padded} with padding) -> {padded // 4} sheets, {len(out.pages)} sides")
