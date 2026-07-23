/* decode.cjs — prep step: decode the note JPEGs to a raw RGB buffer the
 * Tcl pipeline can read with zero decoding. Writes assets/noteN.raw:
 *   magic "RAW1" | uint32 BE width | uint32 BE height | width*height*3 RGB bytes
 * A from-scratch JPEG decoder is out of scope for pure Tcl, so this single
 * step provides real pixels; all cropping + PNG encoding stays in extract.tcl. */
const { chromium } = require('/opt/node22/lib/node_modules/playwright/index.js');
const fs = require('fs'), path = require('path');
const dir = path.join(__dirname, 'assets');
const notes = ['note1.jpg','note2.jpg','note3.jpg'];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  for (const n of notes) {
    const du = 'data:image/jpeg;base64,' + fs.readFileSync(path.join(dir,n)).toString('base64');
    const { w, h, rgb } = await p.evaluate(async (du) => {
      const img = new Image();
      await new Promise((r,j)=>{img.onload=r;img.onerror=j;img.src=du;});
      const TARGET_W = 720;               // committed buffer stays small & repo-friendly
      const scale = Math.min(1, TARGET_W / img.naturalWidth);
      const c = document.createElement('canvas');
      c.width = Math.round(img.naturalWidth*scale); c.height = Math.round(img.naturalHeight*scale);
      const x = c.getContext('2d'); x.drawImage(img,0,0,c.width,c.height);
      const d = x.getImageData(0,0,c.width,c.height).data;   // RGBA
      const out = new Uint8Array(c.width*c.height*3);
      for (let i=0,o=0;i<d.length;i+=4){ out[o++]=d[i]; out[o++]=d[i+1]; out[o++]=d[i+2]; }
      return { w:c.width, h:c.height, rgb: Array.from(out) };
    }, du);
    const head = Buffer.alloc(12);
    head.write('RAW1',0,'ascii'); head.writeUInt32BE(w,4); head.writeUInt32BE(h,8);
    const out = path.join(dir, n.replace('.jpg','.raw'));
    fs.writeFileSync(out, Buffer.concat([head, Buffer.from(rgb)]));
    console.log(out, w+'x'+h, (fs.statSync(out).size/1024|0)+'KB');
  }
  await b.close();
})();
