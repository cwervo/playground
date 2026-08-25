"""Stage 32 - camera pose from the horizon line, and summary figures."""
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw

CX, CY = 603.0, 804.0
V_long = np.array([461.4, 750.9])      # longitudinal (car axis)
V_tran = np.array([-153.9, 917.3])     # a second horizontal direction
d = V_tran - V_long
roll = np.degrees(np.arctan2(d[1], d[0]))
roll = (roll + 90) % 180 - 90
n = np.array([-d[1], d[0]]); n = n/np.linalg.norm(n)
dist = abs(n @ (np.array([CX,CY]) - V_long))
print('=== camera pose from the horizon line ===')
print(f'  horizon passes through the two horizontal VPs')
print(f'  roll (tilt of the horizon in the frame) = {roll:+.1f} deg')
print(f'  horizon offset from the principal point = {dist:.1f} px')
print(f'  => pitch = arctan({dist:.1f}/f); for f = 700..1400 px that is '
      f'{np.degrees(np.arctan(dist/1400)):.1f}..{np.degrees(np.arctan(dist/700)):.1f} deg')
print(f'  longitudinal VP is {np.hypot(*(V_long-[CX,CY])):.0f} px from the principal point')
print(f'  => the optical axis was within arctan({np.hypot(*(V_long-[CX,CY])):.0f}/f) '
      f'= {np.degrees(np.arctan(np.hypot(*(V_long-[CX,CY]))/1400)):.0f}..'
      f'{np.degrees(np.arctan(np.hypot(*(V_long-[CX,CY]))/700)):.0f} deg of the car axis')

# ---------- figure 1: fitted support ellipse ----------
lin = np.load('data/screen_linearP3.npy')[330:1938]
cx,cy,a,b,th = np.load('data/ellipse_levelset.npy')
im = Image.fromarray((np.clip(lin,0,1)**(1/3.0)*255).astype(np.uint8)).convert('RGB')
dr = ImageDraw.Draw(im)
t = np.linspace(0,2*np.pi,1440)
for scale,col in ((1.0,(255,40,40)),(0.78,(60,200,255))):
    pts=[(cx+a*scale*np.cos(u), cy+b*scale*np.sin(u)) for u in t]
    dr.line(pts+[pts[0]], fill=col, width=3)
dr.line([(cx-30,cy),(cx+30,cy)], fill=(255,255,0), width=3)
dr.line([(cx,cy-30),(cx,cy+30)], fill=(255,255,0), width=3)
dr.line([(603-30,804),(603+30,804)], fill=(0,255,0), width=2)
dr.line([(603,804-30),(603,804+30)], fill=(0,255,0), width=2)
im.resize((603,804), Image.LANCZOS).save('figures/fig1_ellipse.png')

# ---------- figure 2: measurement panels ----------
fig, ax = plt.subplots(2,2, figsize=(11,8.5))
p = np.load('data/vig_profile.npy')
ax[0,0].plot(p[:,0], p[:,1], 'o-', ms=3, color='#c1440e')
ax[0,0].axvline(0.78, ls='--', c='k', lw=.8); ax[0,0].axvline(1.0, ls='--', c='k', lw=.8)
r = np.linspace(0,1.05,200)
ax[0,0].plot(r, 1/(1+(r/0.95)**2)**2, '--', c='#666', label=r'natural $\cos^4$')
ax[0,0].set_xlabel(r'normalised elliptical radius $\rho$'); ax[0,0].set_ylabel('relative illumination')
ax[0,0].set_title('Vignette: flat core, then a cliff'); ax[0,0].legend(fontsize=8); ax[0,0].set_ylim(-0.05,1.7)

q = np.load('data/ptc2.npy')
ax[0,1].loglog(q[:,0], q[:,1], 'o', color='#1f4e79')
xx = np.logspace(np.log10(q[:,0].min()), np.log10(q[:,0].max()), 50)
ax[0,1].loglog(xx, q[0,1]*(xx/q[0,0])**1.0, '--', c='#888', label=r'shot noise $\propto\mu$')
ax[0,1].loglog(xx, q[0,1]*(xx/q[0,0])**2.0, ':', c='#888', label=r'multiplicative $\propto\mu^2$')
ax[0,1].set_xlabel(r'mean signal $\mu$ (linear light)'); ax[0,1].set_ylabel(r'variance')
ax[0,1].set_title('Photon transfer curve'); ax[0,1].legend(fontsize=8)

ac = np.load('data/grain_ac.npy'); c = ac.shape[0]//2
ax[1,0].plot(np.arange(-6,7), ac[c, c-6:c+7], 'o-', label='horizontal', color='#1f4e79')
ax[1,0].plot(np.arange(-6,7), ac[c-6:c+7, c], 's--', label='vertical', color='#c1440e')
ax[1,0].axhline(1/np.e, ls=':', c='k', lw=.8)
ax[1,0].set_xlabel('lag (screen px)'); ax[1,0].set_ylabel('normalised autocorrelation')
ax[1,0].set_title('Grain autocorrelation: isotropic (1.016)'); ax[1,0].legend(fontsize=8)

o = np.load('data/rectilinearity.npy')
ax[1,1].plot(o[:,0], o[:,3], '-', color='#1f4e79')
i = np.argmin(o[:,3]); ax[1,1].plot(o[i,0], o[i,3], 'o', color='#c1440e')
ax[1,1].axvline(0, ls=':', c='k', lw=.8)
ax[1,1].annotate('rectilinear', (0, o[i,3]*1.9), fontsize=8, ha='center')
ax[1,1].annotate('full fisheye', (-0.35, o[i,3]*1.9), fontsize=8, ha='center')
ax[1,1].axvline(-0.35, ls=':', c='k', lw=.8)
ax[1,1].set_xlabel(r'division-model $L$ (barrel $<0$)')
ax[1,1].set_ylabel('VP concurrency residual (deg)')
ax[1,1].set_title('Distortion from 36 concurrent segments')
plt.tight_layout(); plt.savefig('figures/fig2_panels.png', dpi=140)
print('\nwrote figures/fig1_ellipse.png figures/fig2_panels.png')
