"""Stage 24 - dense straight-segment extraction (Douglas-Peucker split).

Long edge chains mix several structures and curved objects; splitting them into
maximal straight pieces (as in Devernay & Faugeras' polygonal approximation
step) yields far more usable lines for vanishing-point estimation.
"""
import numpy as np
from scipy import ndimage as ndi

lin = np.load('data/screen_linearP3.npy')[330:1938].astype(np.float64)
rho = np.load('data/rho_map.npy'); H, W = rho.shape
g = (np.clip(lin.mean(axis=2),0,1))**(1/2.6)
g = ndi.gaussian_filter(g, 1.4)
gy, gx = np.gradient(g); mag = np.hypot(gx, gy); ang = np.arctan2(gy, gx)
valid = rho < 0.95
for y0,y1,x0,x1 in [(40,130,1040,1170),(1480,1580,1080,1170)]: valid[y0:y1,x0:x1]=False

q = (np.round(ang/(np.pi/4)).astype(int)) % 4
nms = np.zeros_like(mag, bool)
for d,(dy,dx) in {0:(0,1),1:(1,1),2:(1,0),3:(1,-1)}.items():
    m = (q==d)&valid
    nms |= m & (mag >= np.roll(np.roll(mag,-dy,0),-dx,1)) & (mag >= np.roll(np.roll(mag,dy,0),dx,1))
nms[:3]=nms[-3:]=False; nms[:,:3]=nms[:,-3:]=False
hi = np.percentile(mag[valid], 90.0); lo = 0.35*hi
strong = nms&(mag>=hi); weak = nms&(mag>=lo)
lab,n = ndi.label(weak, structure=np.ones((3,3)))
keep=np.zeros(n+1,bool); keep[np.unique(lab[strong])]=True; keep[0]=False
edges = keep[lab]
print('edge px', edges.sum())

ys,xs = np.nonzero(edges)
ux,uy = gx[ys,xs]/(mag[ys,xs]+1e-12), gy[ys,xs]/(mag[ys,xs]+1e-12)
def bil(im,yy,xx):
    y0=np.clip(np.floor(yy).astype(int),0,H-2); x0=np.clip(np.floor(xx).astype(int),0,W-2)
    fy=yy-y0; fx=xx-x0
    return (im[y0,x0]*(1-fy)*(1-fx)+im[y0+1,x0]*fy*(1-fx)+im[y0,x0+1]*(1-fy)*fx+im[y0+1,x0+1]*fy*fx)
m0=mag[ys,xs]; mp=bil(mag,ys+uy,xs+ux); mm=bil(mag,ys-uy,xs-ux)
den=mp-2*m0+mm
t=np.clip(np.where(np.abs(den)>1e-12, -0.5*(mp-mm)/den, 0.0), -0.7, 0.7)
px, py = xs+t*ux, ys+t*uy

lab2,n2 = ndi.label(edges, structure=np.ones((3,3)))
def order_chain(P):
    Pc=P-P.mean(0); _,_,Vt=np.linalg.svd(Pc,full_matrices=False)
    return P[np.argsort(Pc@Vt[0])]
def dp_split(P, tol=2.0, minlen=40):
    out=[]
    def rec(a,b):
        if b-a < 12: return
        A,B = P[a], P[b-1]
        d = B-A; L=np.hypot(*d)
        if L < 1e-6: return
        nvec=np.array([-d[1],d[0]])/L
        dev=np.abs((P[a:b]-A)@nvec)
        i=int(np.argmax(dev))
        if dev[i] > tol and 6 < i < (b-a-6):
            rec(a,a+i+1); rec(a+i,b)
        elif L >= minlen:
            out.append((a,b))
    rec(0,len(P)); return out

segs=[]
for cid in range(1,n2+1):
    sel=np.nonzero(lab2[ys,xs]==cid)[0]
    if len(sel)<25: continue
    P=order_chain(np.c_[px[sel],py[sel]])
    for a,b in dp_split(P):
        Q=P[a:b]
        Qc=Q-Q.mean(0); _,S,Vt=np.linalg.svd(Qc,full_matrices=False)
        rms=S[1]/np.sqrt(len(Q)); span=np.ptp(Qc@Vt[0])
        if rms>1.8 or span<40: continue
        segs.append((Q.mean(0), Vt[0], span, rms, len(Q)))
print('straight segments:', len(segs))
sp=np.array([s[2] for s in segs])
print(f'  span: median {np.median(sp):.0f}  max {sp.max():.0f}  >100px: {(sp>100).sum()}')
np.save('data/segs.npy', np.array(
    [[m[0],m[1],d[0],d[1],s,r,n] for m,d,s,r,n in segs]))
