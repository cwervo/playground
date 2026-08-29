import { validate } from "/tmp/claude-0/bundled-skills/2.1.251/c0a8174a48b7feebbc3eb4d639328312/dataviz/scripts/validate_palette.js";
const LIGHT_SURF = "#EFF1F2", DARK_SURF = "#0E1113";
function linFromOklab(L,a,b){const l_=L+0.3963377774*a+0.2158037573*b,m_=L-0.1055613458*a-0.0638541728*b,s_=L-0.0894841775*a-1.2914855480*b;const l=l_**3,m=m_**3,s=s_**3;return[4.0767416621*l-3.3077115913*m+0.2309699292*s,-1.2684380046*l+2.6097574011*m-0.3413193965*s,-0.0041960863*l-0.7034186147*m+1.7076147010*s];}
const lin2s=c=>c<=0.0031308?12.92*c:1.055*c**(1/2.4)-0.055;
function oklchToHex(L,C,hDeg){const h=hDeg*Math.PI/180;const g=linFromOklab(L,C*Math.cos(h),C*Math.sin(h));if(g.some(v=>v<-0.001||v>1.001))return null;return "#"+g.map(v=>Math.round(Math.max(0,Math.min(1,lin2s(v)))*255).toString(16).padStart(2,"0")).join("");}
const pool=[];
for(let h=0;h<360;h+=4)for(const L of [0.54,0.58,0.62,0.66])for(const C of [0.22,0.19,0.16,0.13,0.11]){const hex=oklchToHex(L,C,h);if(hex){pool.push({hex,h,L,C});break;}}
const ROW=(r,n)=>r.report.find(x=>x[0].startsWith(n));
const isFail=st=>st===false||st==="fail";
const num=row=>{const m=/ΔE ([\d.]+)/.exec(row[2]||"");return m?parseFloat(m[1]):NaN;};
function evaluate(p){let wC=Infinity,wN=Infinity;
  for(const [mode,surface] of [["light",LIGHT_SURF],["dark",DARK_SURF]]){
    const r=validate(p,{mode,surface,pairs:"all"});
    for(const nm of ["Lightness band","Chroma floor","Normal-vision floor"]) if(isFail(ROW(r,nm)[1])) return null;
    const cvd=ROW(r,"CVD separation"); if(isFail(cvd[1])) return null;
    wC=Math.min(wC,num(cvd)); wN=Math.min(wN,num(ROW(r,"Normal-vision floor")));
  } return {wC,wN};}
const N=+process.argv[2]||6, TRIES=+process.argv[3]||120000;
const found=[];
for(let t=0;t<TRIES;t++){
  const pick=[],used=new Set();
  let guard=0;
  while(pick.length<N && guard++<400){
    const c=pool[(Math.random()*pool.length)|0];
    if(used.has(c.hex))continue;
    if(pick.some(q=>Math.min(Math.abs(q.h-c.h),360-Math.abs(q.h-c.h))<28))continue;
    used.add(c.hex);pick.push(c);
  }
  if(pick.length<N)continue;
  pick.sort((a,b)=>a.h-b.h);
  const hexes=pick.map(c=>c.hex);
  const ev=evaluate(hexes); if(!ev)continue;
  const chroma=pick.reduce((s,c)=>s+c.C,0)/N;
  found.push({hexes,...ev,chroma});
}
found.sort((a,b)=> (b.wC-a.wC) || (b.chroma-a.chroma));
const seen=new Set();
for(const f of found){
  const key=f.hexes.join();
  if(seen.has(key))continue; seen.add(key);
  console.log(`CVD ${f.wC.toFixed(1)}  norm ${f.wN.toFixed(1)}  C̄ ${f.chroma.toFixed(2)}  ${f.hexes.join(", ")}`);
  if(seen.size>=14)break;
}
