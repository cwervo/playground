// ============================================================================
//  pcav.cpp -- Plant Contour / Velocity / Shadow analyser + film grader
//
//  A from-scratch computer-vision engine.  No OpenCV, no image library, no
//  math library beyond <cmath>, no <algorithm>.  Everything below -- colour
//  conversion, morphology, connected components, block motion estimation,
//  shadow segmentation, bloom, film grading, bitmap text -- is hand written
//  over a flat unsigned char buffer.
//
//  I/O contract:
//     stdin   : raw rgb24 frames, W*H*3 bytes each  (piped from a demuxer)
//     stdout  : raw rgb24 frames, W*H*3 bytes each  (piped to a muxer)
//     argv    : W H metrics.tsv boxes.tsv
//
//  Build:  g++ -O2 -ffast-math -o pcav pcav.cpp
// ============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>

typedef unsigned char u8;
typedef unsigned int  u32;

static inline int   imin(int a,int b){ return a<b?a:b; }
static inline int   imax(int a,int b){ return a>b?a:b; }
static inline float fmin_(float a,float b){ return a<b?a:b; }
static inline float fmax_(float a,float b){ return a>b?a:b; }
static inline int   clampi(int v,int lo,int hi){ return v<lo?lo:(v>hi?hi:v); }
static inline float clampf(float v,float lo,float hi){ return v<lo?lo:(v>hi?hi:v); }
static inline u8    clamp8(float v){ return (u8)clampi((int)(v+0.5f),0,255); }

// ---------------------------------------------------------------------------
//  5x7 bitmap font (columns, bit0 = top row), ASCII 0x20..0x5F.
//  Hand-embedded so no font file / renderer is needed.
// ---------------------------------------------------------------------------
static const u8 FONT[64][5] = {
{0x00,0x00,0x00,0x00,0x00},{0x00,0x00,0x5F,0x00,0x00},{0x00,0x07,0x00,0x07,0x00},
{0x14,0x7F,0x14,0x7F,0x14},{0x24,0x2A,0x7F,0x2A,0x12},{0x23,0x13,0x08,0x64,0x62},
{0x36,0x49,0x55,0x22,0x50},{0x00,0x05,0x03,0x00,0x00},{0x00,0x1C,0x22,0x41,0x00},
{0x00,0x41,0x22,0x1C,0x00},{0x14,0x08,0x3E,0x08,0x14},{0x08,0x08,0x3E,0x08,0x08},
{0x00,0x50,0x30,0x00,0x00},{0x08,0x08,0x08,0x08,0x08},{0x00,0x60,0x60,0x00,0x00},
{0x20,0x10,0x08,0x04,0x02},{0x3E,0x51,0x49,0x45,0x3E},{0x00,0x42,0x7F,0x40,0x00},
{0x42,0x61,0x51,0x49,0x46},{0x21,0x41,0x45,0x4B,0x31},{0x18,0x14,0x12,0x7F,0x10},
{0x27,0x45,0x45,0x45,0x39},{0x3C,0x4A,0x49,0x49,0x30},{0x01,0x71,0x09,0x05,0x03},
{0x36,0x49,0x49,0x49,0x36},{0x06,0x49,0x49,0x29,0x1E},{0x00,0x36,0x36,0x00,0x00},
{0x00,0x56,0x36,0x00,0x00},{0x08,0x14,0x22,0x41,0x00},{0x14,0x14,0x14,0x14,0x14},
{0x00,0x41,0x22,0x14,0x08},{0x02,0x01,0x51,0x09,0x06},{0x32,0x49,0x79,0x41,0x3E},
{0x7E,0x11,0x11,0x11,0x7E},{0x7F,0x49,0x49,0x49,0x36},{0x3E,0x41,0x41,0x41,0x22},
{0x7F,0x41,0x41,0x22,0x1C},{0x7F,0x49,0x49,0x49,0x41},{0x7F,0x09,0x09,0x09,0x01},
{0x3E,0x41,0x49,0x49,0x7A},{0x7F,0x08,0x08,0x08,0x7F},{0x00,0x41,0x7F,0x41,0x00},
{0x20,0x40,0x41,0x3F,0x01},{0x7F,0x08,0x14,0x22,0x41},{0x7F,0x40,0x40,0x40,0x40},
{0x7F,0x02,0x0C,0x02,0x7F},{0x7F,0x04,0x08,0x10,0x7F},{0x3E,0x41,0x41,0x41,0x3E},
{0x7F,0x09,0x09,0x09,0x06},{0x3E,0x41,0x51,0x21,0x5E},{0x7F,0x09,0x19,0x29,0x46},
{0x46,0x49,0x49,0x49,0x31},{0x01,0x01,0x7F,0x01,0x01},{0x3F,0x40,0x40,0x40,0x3F},
{0x1F,0x20,0x40,0x20,0x1F},{0x3F,0x40,0x38,0x40,0x3F},{0x63,0x14,0x08,0x14,0x63},
{0x07,0x08,0x70,0x08,0x07},{0x61,0x51,0x49,0x45,0x43},{0x00,0x7F,0x41,0x41,0x00},
{0x02,0x04,0x08,0x10,0x20},{0x00,0x41,0x41,0x7F,0x00},{0x04,0x02,0x01,0x02,0x04},
{0x40,0x40,0x40,0x40,0x40}
};

// ---------------------------------------------------------------------------
//  Global geometry
// ---------------------------------------------------------------------------
static int W, H, WH;           // full resolution
static int HW, HH, HWH;        // half resolution (motion estimation)
static const int BS = 16;      // motion block size, in half-res pixels
static int BX, BY, NB;         // block grid

// ---------------------------------------------------------------------------
//  Palette -- the fixed art direction of the piece
// ---------------------------------------------------------------------------
struct RGB { float r,g,b; };
static const RGB NAVY      = {  8.f,  22.f, 104.f };  // bounding boxes
static const RGB NAVY_LIT  = { 44.f,  86.f, 208.f };  // box inner keyline
static const RGB PLANT_GRN = {  0.f, 255.f,  64.f };  // contour edges
static const RGB DK_PURPLE = { 46.f,   6.f,  78.f };  // shadow body mix
static const RGB LT_PURPLE = {150.f,  48.f, 214.f };  // shadow rim highlight
static const RGB PURE_R    = {255.f,   0.f,   0.f };
static const RGB PURE_G    = {  0.f, 255.f,   0.f };
static const RGB PURE_B    = {  0.f,   0.f, 255.f };

// ---------------------------------------------------------------------------
//  Framebuffer primitives (alpha compositing straight onto rgb24)
// ---------------------------------------------------------------------------
static inline void px(u8* f,int x,int y,RGB c,float a){
    if(x<0||y<0||x>=W||y>=H||a<=0.f) return;
    if(a>1.f) a=1.f;
    int i=(y*W+x)*3;
    f[i  ]=clamp8(f[i  ]*(1.f-a)+c.r*a);
    f[i+1]=clamp8(f[i+1]*(1.f-a)+c.g*a);
    f[i+2]=clamp8(f[i+2]*(1.f-a)+c.b*a);
}
static void fillRect(u8* f,int x0,int y0,int x1,int y1,RGB c,float a){
    for(int y=imax(y0,0);y<=imin(y1,H-1);y++)
        for(int x=imax(x0,0);x<=imin(x1,W-1);x++) px(f,x,y,c,a);
}
// style: 0 solid, 1 dashed, 2 dotted
static void strokeRect(u8* f,int x0,int y0,int x1,int y1,RGB c,float a,int t,int style){
    for(int k=0;k<t;k++){
        int a0=x0-k,a1=x1+k,b0=y0-k,b1=y1+k;
        for(int x=a0;x<=a1;x++){
            int on=1;
            if(style==1) on=((x/9)&1)==0;
            if(style==2) on=(x%5)<2;
            if(on){ px(f,x,b0,c,a); px(f,x,b1,c,a); }
        }
        for(int y=b0;y<=b1;y++){
            int on=1;
            if(style==1) on=((y/9)&1)==0;
            if(style==2) on=(y%5)<2;
            if(on){ px(f,a0,y,c,a); px(f,a1,y,c,a); }
        }
    }
}
static void corners(u8* f,int x0,int y0,int x1,int y1,RGB c,float a,int len,int t){
    for(int k=0;k<t;k++){
        for(int i=0;i<len;i++){
            px(f,x0+i,y0-k,c,a); px(f,x1-i,y0-k,c,a);
            px(f,x0+i,y1+k,c,a); px(f,x1-i,y1+k,c,a);
            px(f,x0-k,y0+i,c,a); px(f,x0-k,y1-i,c,a);
            px(f,x1+k,y0+i,c,a); px(f,x1+k,y1-i,c,a);
        }
    }
}
static int textW(const char* s,int sc){ int n=0; while(s[n])n++; return n*6*sc; }
static void drawChar(u8* f,int x,int y,char ch,RGB c,int sc,float a){
    if(ch>='a'&&ch<='z') ch-=32;
    int idx=ch-0x20; if(idx<0||idx>63) idx=0;
    for(int col=0;col<5;col++){
        u8 bits=FONT[idx][col];
        for(int row=0;row<7;row++){
            if(!((bits>>row)&1)) continue;
            for(int dy=0;dy<sc;dy++) for(int dx=0;dx<sc;dx++)
                px(f,x+col*sc+dx,y+row*sc+dy,c,a);
        }
    }
}
static void drawText(u8* f,int x,int y,const char* s,RGB c,int sc,float a){
    for(int i=0;s[i];i++) drawChar(f,x+i*6*sc,y,s[i],c,sc,a);
}
// text with a 1px dark outline so it survives any background
static void drawTextOut(u8* f,int x,int y,const char* s,RGB c,int sc,float a){
    RGB k={0,0,0};
    for(int i=0;s[i];i++){
        drawChar(f,x+i*6*sc-1,y,s[i],k,sc,a*0.75f);
        drawChar(f,x+i*6*sc+1,y,s[i],k,sc,a*0.75f);
        drawChar(f,x+i*6*sc,y-1,s[i],k,sc,a*0.75f);
        drawChar(f,x+i*6*sc,y+1,s[i],k,sc,a*0.75f);
    }
    drawText(f,x,y,s,c,sc,a);
}

// ---------------------------------------------------------------------------
//  Separable box blur on a float plane -- the only smoothing kernel used.
//  Two passes of this approximate a Gaussian well enough for bloom.
// ---------------------------------------------------------------------------
static void boxBlur(float* src,float* dst,int w,int h,int r,float* tmp){
    float inv=1.f/(2*r+1);
    for(int y=0;y<h;y++){
        const float* s=src+y*w; float* t=tmp+y*w;
        float acc=0.f;
        for(int x=-r;x<=r;x++) acc+=s[clampi(x,0,w-1)];
        for(int x=0;x<w;x++){
            t[x]=acc*inv;
            acc+=s[clampi(x+r+1,0,w-1)]-s[clampi(x-r,0,w-1)];
        }
    }
    for(int x=0;x<w;x++){
        float acc=0.f;
        for(int y=-r;y<=r;y++) acc+=tmp[clampi(y,0,h-1)*w+x];
        for(int y=0;y<h;y++){
            dst[y*w+x]=acc*inv;
            acc+=tmp[clampi(y+r+1,0,h-1)*w+x]-tmp[clampi(y-r,0,h-1)*w+x];
        }
    }
}

// ---------------------------------------------------------------------------
//  Binary morphology: separable min (erode) / max (dilate) over a square SE.
// ---------------------------------------------------------------------------
static void morph(u8* m,u8* out,int w,int h,int r,int dilate,u8* tmp){
    for(int y=0;y<h;y++){
        for(int x=0;x<w;x++){
            u8 v=dilate?0:255;
            for(int k=-r;k<=r;k++){
                u8 s=m[y*w+clampi(x+k,0,w-1)];
                v = dilate ? (s>v?s:v) : (s<v?s:v);
            }
            tmp[y*w+x]=v;
        }
    }
    for(int y=0;y<h;y++){
        for(int x=0;x<w;x++){
            u8 v=dilate?0:255;
            for(int k=-r;k<=r;k++){
                u8 s=tmp[clampi(y+k,0,h-1)*w+x];
                v = dilate ? (s>v?s:v) : (s<v?s:v);
            }
            out[y*w+x]=v;
        }
    }
}

// ---------------------------------------------------------------------------
//  Connected components -- iterative 8-neighbour flood fill with an explicit
//  stack (no recursion, no std::stack).  Returns component bounding boxes.
// ---------------------------------------------------------------------------
struct Box { int x0,y0,x1,y1,area; };

static void components(const u8* mask,int w,int h,int minArea,
                       std::vector<Box>& outBoxes,int maxBoxes){
    std::vector<u8> seen((size_t)w*h,0);
    std::vector<int> stack; stack.reserve(4096);
    outBoxes.clear();
    for(int y=0;y<h;y++) for(int x=0;x<w;x++){
        int p=y*w+x;
        if(!mask[p]||seen[p]) continue;
        stack.clear(); stack.push_back(p); seen[p]=1;
        Box b; b.x0=b.x1=x; b.y0=b.y1=y; b.area=0;
        while(!stack.empty()){
            int q=stack.back(); stack.pop_back();
            int qx=q%w, qy=q/w; b.area++;
            if(qx<b.x0)b.x0=qx; if(qx>b.x1)b.x1=qx;
            if(qy<b.y0)b.y0=qy; if(qy>b.y1)b.y1=qy;
            for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++){
                int nx=qx+dx, ny=qy+dy;
                if(nx<0||ny<0||nx>=w||ny>=h) continue;
                int n=ny*w+nx;
                if(mask[n]&&!seen[n]){ seen[n]=1; stack.push_back(n); }
            }
        }
        if(b.area>=minArea) outBoxes.push_back(b);
    }
    // selection sort by area, descending -- lists are tiny
    for(size_t i=0;i<outBoxes.size();i++){
        size_t best=i;
        for(size_t j=i+1;j<outBoxes.size();j++)
            if(outBoxes[j].area>outBoxes[best].area) best=j;
        Box t=outBoxes[i]; outBoxes[i]=outBoxes[best]; outBoxes[best]=t;
    }
    if((int)outBoxes.size()>maxBoxes) outBoxes.resize(maxBoxes);
}

// Zero every connected blob smaller than minArea.  Shade is a region; the
// leftovers of dark paint after an opening are specks.
static void removeSmall(u8* mask,int w,int h,int minArea){
    std::vector<u8> seen((size_t)w*h,0);
    std::vector<int> stack, blob;
    for(int y=0;y<h;y++) for(int x=0;x<w;x++){
        int p=y*w+x;
        if(!mask[p]||seen[p]) continue;
        stack.clear(); blob.clear();
        stack.push_back(p); seen[p]=1;
        while(!stack.empty()){
            int q=stack.back(); stack.pop_back();
            blob.push_back(q);
            int qx=q%w, qy=q/w;
            for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++){
                int nx=qx+dx, ny=qy+dy;
                if(nx<0||ny<0||nx>=w||ny>=h) continue;
                int n=ny*w+nx;
                if(mask[n]&&!seen[n]){ seen[n]=1; stack.push_back(n); }
            }
        }
        if((int)blob.size()<minArea)
            for(size_t k=0;k<blob.size();k++) mask[blob[k]]=0;
    }
}

// merge boxes whose rectangles touch or overlap (with a slack margin)
static void mergeBoxes(std::vector<Box>& b,int slack){
    int changed=1;
    while(changed){
        changed=0;
        for(size_t i=0;i<b.size()&&!changed;i++)
            for(size_t j=i+1;j<b.size()&&!changed;j++){
                if(b[i].x0-slack<=b[j].x1 && b[j].x0-slack<=b[i].x1 &&
                   b[i].y0-slack<=b[j].y1 && b[j].y0-slack<=b[i].y1){
                    b[i].x0=imin(b[i].x0,b[j].x0); b[i].y0=imin(b[i].y0,b[j].y0);
                    b[i].x1=imax(b[i].x1,b[j].x1); b[i].y1=imax(b[i].y1,b[j].y1);
                    b[i].area+=b[j].area;
                    b.erase(b.begin()+j);
                    changed=1;
                }
            }
    }
}

// median of a small float array (insertion sort on a copy)
static float medianf(float* a,int n){
    if(n<=0) return 0.f;
    std::vector<float> c(a,a+n);
    for(int i=1;i<n;i++){ float k=c[i]; int j=i-1;
        while(j>=0&&c[j]>k){ c[j+1]=c[j]; j--; } c[j+1]=k; }
    return c[n/2];
}

// ---------------------------------------------------------------------------
//  Film grade -- a hand-rolled "Nolan" look:
//    filmic tonemap -> lifted/crushed toe -> teal shadows / amber highlights
//    -> global desaturation -> anamorphic-ish vignette -> halation -> grain
// ---------------------------------------------------------------------------
static float TONE[256];
static void buildToneLUT(){
    for(int i=0;i<256;i++){
        float x=i/255.f;
        float lin=powf(x,2.2f);                // to scene-linear
        lin*=0.78f;                            // print down ~1/3 stop
        float a=2.51f,b=0.03f,c=2.43f,d=0.59f,e=0.14f;
        float t=(lin*(a*lin+b))/(lin*(c*lin+d)+e);   // ACES-style filmic
        t=clampf(t,0.f,1.f);
        t=powf(t,1.f/2.2f);                    // back to display
        t=(t-0.5f)*1.30f+0.5f-0.035f;          // S-curve contrast, pivot 0.5
        t=clampf(t,0.f,1.f);
        t=t*0.965f+0.014f;                     // dense blacks, tiny toe lift
        TONE[i]=clampf(t,0.f,1.f);
    }
}

static inline u32 hash32(u32 v){
    v^=v>>16; v*=0x7feb352dU; v^=v>>15; v*=0x846ca68bU; v^=v>>16; return v;
}

int main(int argc,char** argv){
    if(argc<5){ fprintf(stderr,"usage: pcav W H metrics.tsv boxes.tsv\n"); return 1; }
    W=atoi(argv[1]); H=atoi(argv[2]); WH=W*H;
    HW=W/2; HH=H/2; HWH=HW*HH;
    BX=HW/BS; BY=HH/BS; NB=BX*BY;
    FILE* fm=fopen(argv[3],"w");
    FILE* fb=fopen(argv[4],"w");
    fprintf(fm,"frame\ttime\tcamMag\tcamDx\tcamDy\tmeanMag\tmaxMag\thiFrac\tloFrac\t"
               "localEnergy\tplantArea\tplantN\tplantCx\tplantCy\tshadowFrac\t"
               "shadowChange\tshadowCx\tshadowCy\tluma\n");
    fprintf(fb,"frame\tkind\tx\ty\tw\th\tarea\n");
    buildToneLUT();

    std::vector<u8>  src((size_t)WH*3), dst((size_t)WH*3);
    std::vector<u8>  luma(WH), half(HWH), prevHalf(HWH,0);
    std::vector<u8>  gmask(WH), gtmp(WH), gtmp2(WH);
    std::vector<u8>  smask(WH), prevSmask(WH,0), stmp(WH);
    std::vector<float> hi(WH), bl(WH), tmpf(WH), sfl(WH), sblur(WH);
    std::vector<float> mvx(NB,0.f), mvy(NB,0.f), mvm(NB,0.f);
    std::vector<u8>  hiBlk(NB,0), loBlk(NB,0);
    std::vector<Box> plantBoxes, hiBoxes, loBoxes;

    const float FPS = 30000.f/1001.f;
    int frame=0;
    int havePrev=0;
    float smoothCam=0.f, smoothLocal=0.f, smoothShadow=0.f;
    char buf[256];

    while(fread(&src[0],1,(size_t)WH*3,stdin)==(size_t)WH*3){
        // ---------------------------------------------------------------
        // 1. Luma + half-res luma pyramid level
        // ---------------------------------------------------------------
        double lumaSum=0.0;
        for(int i=0;i<WH;i++){
            int r=src[i*3],g=src[i*3+1],b=src[i*3+2];
            int y=(r*77+g*150+b*29)>>8;            // Rec.601 in fixed point
            luma[i]=(u8)y; lumaSum+=y;
        }
        float lumaMean=(float)(lumaSum/WH);
        for(int y=0;y<HH;y++) for(int x=0;x<HW;x++){
            int p=(2*y)*W+2*x;
            half[y*HW+x]=(u8)((luma[p]+luma[p+1]+luma[p+W]+luma[p+W+1])>>2);
        }

        // ---------------------------------------------------------------
        // 2. Plant mask -- chromatic green dominance.
        //    gn = (2G-R-B)/(R+G+B) isolates foliage; the extra G>1.06*R test
        //    rejects the yellow carton and warm brick, which also score high
        //    on plain green-excess.
        // ---------------------------------------------------------------
        for(int i=0;i<WH;i++){
            float r=src[i*3],g=src[i*3+1],b=src[i*3+2];
            float sum=r+g+b+1.f;
            float gn=(2.f*g-r-b)/sum;
            gmask[i]=(gn>0.085f && g>1.055f*r && g>b*1.02f && g>34.f)?255:0;
        }
        morph(&gmask[0],&gtmp[0],W,H,2,0,&gtmp2[0]);   // erode  (kill speckle)
        morph(&gtmp[0],&gmask[0],W,H,3,1,&gtmp2[0]);   // dilate (rejoin leaf)
        morph(&gmask[0],&gtmp[0],W,H,2,0,&gtmp2[0]);   // erode  (restore size)
        memcpy(&gmask[0],&gtmp[0],WH);

        double gArea=0,gcx=0,gcy=0;
        for(int y=0;y<H;y++) for(int x=0;x<W;x++)
            if(gmask[y*W+x]){ gArea++; gcx+=x; gcy+=y; }
        if(gArea>0){ gcx/=gArea; gcy/=gArea; }

        // ---------------------------------------------------------------
        // 3. Shadow mask -- luma below an adaptive floor derived from the
        //    frame's own mean, so it tracks exposure changes as we walk in.
        // ---------------------------------------------------------------
        // A shadow is not simply "dark": dark paint is dark too.  Estimate the
        // illumination field with a wide blur of the luma, call a pixel shaded
        // when it sits well under its own local illumination, then open the
        // mask with a large structuring element so thin dark marks -- graffiti
        // strokes, cracks, wet stains -- drop out and only broad shade zones
        // survive.
        float shT=lumaMean*0.88f;
        for(int i=0;i<WH;i++) sfl[i]=(float)luma[i];
        boxBlur(&sfl[0],&sblur[0],W,H,150,&tmpf[0]);       // illumination field
        for(int i=0;i<WH;i++)
            smask[i]=(luma[i] < 0.80f*sblur[i] && luma[i] < shT)?255:0;
        // Erode hard first: a graffiti stroke is thinner than a shadow, so it
        // disappears here.  Kill whatever fragments survive, then dilate the
        // real regions back out.
        morph(&smask[0],&stmp[0],W,H,10,0,&gtmp2[0]);
        removeSmall(&stmp[0],W,H,1100);
        morph(&stmp[0],&smask[0],W,H,14,1,&gtmp2[0]);
        morph(&smask[0],&stmp[0],W,H,4,0,&gtmp2[0]);
        memcpy(&smask[0],&stmp[0],WH);
        double sArea=0,scx=0,scy=0,sChange=0;
        for(int y=0;y<H;y++) for(int x=0;x<W;x++){
            int i=y*W+x;
            if(smask[i]){ sArea++; scx+=x; scy+=y; }
            if(havePrev && smask[i]!=prevSmask[i]) sChange++;
        }
        if(sArea>0){ scx/=sArea; scy/=sArea; }
        float shadowFrac=(float)(sArea/WH);
        float shadowChange=havePrev?(float)(sChange/WH):0.f;

        // ---------------------------------------------------------------
        // 4. Block motion estimation -- three-step (logarithmic) search,
        //    SAD over 16x16 half-res blocks, start step 8 => +/-15 px.
        // ---------------------------------------------------------------
        float camDx=0.f,camDy=0.f,camMag=0.f,meanMag=0.f,maxMag=0.f,localE=0.f;
        if(havePrev){
            for(int by=0;by<BY;by++) for(int bx=0;bx<BX;bx++){
                int ox=bx*BS, oy=by*BS;
                int bestX=0,bestY=0; long bestSAD=-1;
                int cx=0,cy=0;
                for(int step=8;step>=1;step>>=1){
                    for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++){
                        int tx=cx+dx*step, ty=cy+dy*step;
                        long sad=0;
                        for(int y=0;y<BS;y+=2){
                            int sy=clampi(oy+y+ty,0,HH-1);
                            const u8* a=&half[(oy+y)*HW+ox];
                            const u8* b=&prevHalf[sy*HW];
                            for(int x=0;x<BS;x+=2){
                                int sx=clampi(ox+x+tx,0,HW-1);
                                int d=(int)a[x]-(int)b[sx];
                                sad+=d<0?-d:d;
                            }
                            if(bestSAD>=0 && sad>bestSAD) break;
                        }
                        if(bestSAD<0||sad<bestSAD){ bestSAD=sad; bestX=tx; bestY=ty; }
                    }
                    cx=bestX; cy=bestY;
                }
                int b=by*BX+bx;
                mvx[b]=(float)bestX*2.f;              // back to full-res px
                mvy[b]=(float)bestY*2.f;
                mvm[b]=sqrtf(mvx[b]*mvx[b]+mvy[b]*mvy[b]);
            }
            camDx=medianf(&mvx[0],NB);                // dominant = camera
            camDy=medianf(&mvy[0],NB);
            camMag=sqrtf(camDx*camDx+camDy*camDy);
            double sum=0;
            for(int b=0;b<NB;b++){
                sum+=mvm[b];
                if(mvm[b]>maxMag) maxMag=mvm[b];
                float rx=mvx[b]-camDx, ry=mvy[b]-camDy;   // parallax / subject
                localE+=sqrtf(rx*rx+ry*ry);
            }
            meanMag=(float)(sum/NB);
            localE/=NB;
        }
        // Zone thresholds come from the frame's own magnitude distribution
        // (88th / 14th percentile) so they stay meaningful whether the
        // operator is holding still or swinging the phone.
        float hiT=1e9f, loT=-1.f;
        if(havePrev){
            std::vector<float> srt(mvm);
            for(int i=1;i<NB;i++){ float k=srt[i]; int j=i-1;
                while(j>=0&&srt[j]>k){ srt[j+1]=srt[j]; j--; } srt[j+1]=k; }
            hiT=fmax_(srt[(int)(NB*0.88f)], meanMag*1.30f+1.5f);
            loT=fmin_(srt[(int)(NB*0.14f)], meanMag*0.45f);
        }
        int nHi=0,nLo=0;
        for(int b=0;b<NB;b++){
            hiBlk[b]=(havePrev&&mvm[b]>=hiT)?255:0;
            loBlk[b]=(havePrev&&mvm[b]<=loT)?255:0;
        }
        // keep only dense cores: a block survives if >=3 of its 8 neighbours
        // share its class.  Cheap substitute for a full morphological open.
        {
            std::vector<u8> hc(hiBlk), lc(loBlk);
            for(int by=0;by<BY;by++) for(int bx=0;bx<BX;bx++){
                int b=by*BX+bx, nh=0, nl=0;
                for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++){
                    if(!dx&&!dy) continue;
                    int nx=bx+dx, ny=by+dy;
                    if(nx<0||ny<0||nx>=BX||ny>=BY) continue;
                    nh+=hc[ny*BX+nx]?1:0; nl+=lc[ny*BX+nx]?1:0;
                }
                if(hc[b]&&nh<3) hiBlk[b]=0;
                if(lc[b]&&nl<4) loBlk[b]=0;
            }
            for(int b=0;b<NB;b++){ nHi+=hiBlk[b]?1:0; nLo+=loBlk[b]?1:0; }
        }
        smoothCam   = smoothCam*0.6f   + camMag*0.4f;
        smoothLocal = smoothLocal*0.6f + localE*0.4f;
        smoothShadow= smoothShadow*0.5f+ shadowChange*0.5f;

        // ---------------------------------------------------------------
        // 5. Halation source: isolate highlights, blur twice, keep for later
        // ---------------------------------------------------------------
        for(int i=0;i<WH;i++){
            float l=TONE[luma[i]];
            hi[i]=l>0.70f?(l-0.70f)*3.2f:0.f;
        }
        boxBlur(&hi[0],&bl[0],W,H,9,&tmpf[0]);
        boxBlur(&bl[0],&hi[0],W,H,15,&tmpf[0]);

        // ---------------------------------------------------------------
        // 6. Grade every pixel
        // ---------------------------------------------------------------
        float cxF=W*0.5f, cyF=H*0.5f, invR=1.f/sqrtf(cxF*cxF+cyF*cyF);
        for(int y=0;y<H;y++){
            for(int x=0;x<W;x++){
                int i=y*W+x;
                float r=TONE[src[i*3]], g=TONE[src[i*3+1]], b=TONE[src[i*3+2]];
                float l=0.299f*r+0.587f*g+0.114f*b;

                // split tone: teal into shadow, amber-steel into highlight
                float sw=(1.f-l); sw*=sw*0.80f;
                float hw=l*l*0.42f;
                r=r*(1.f-sw)+ (r*0.30f)*sw;
                g=g*(1.f-sw)+ (g*0.78f+0.030f)*sw;
                b=b*(1.f-sw)+ (b*0.98f+0.058f)*sw;
                r=r*(1.f-hw)+(r*1.02f+0.052f)*hw;
                g=g*(1.f-hw)+(g*0.97f+0.020f)*hw;
                b=b*(1.f-hw)+(b*0.84f)*hw;

                // global desaturation, then a push back along cyan/orange
                float l2=0.299f*r+0.587f*g+0.114f*b;
                r=l2+(r-l2)*0.55f; g=l2+(g-l2)*0.55f; b=l2+(b-l2)*0.55f;
                float co=(r-b)*0.22f;         // orange-vs-teal axis
                r+=co; b-=co;

                // halation, warm
                float hh=hi[i]*0.26f;
                r+=hh*1.00f; g+=hh*0.72f; b+=hh*0.52f;

                // vignette
                float dx=(x-cxF), dy=(y-cyF);
                float rr=sqrtf(dx*dx+dy*dy)*invR;
                float vg=1.f-0.62f*powf(rr,2.2f);
                r*=vg; g*=vg; b*=vg;

                // grain, stronger in the toe
                u32 hsh=hash32((u32)(i*2654435761u)^(u32)(frame*40503u));
                float gr=(((int)(hsh&255))-128)/128.f*0.020f*(1.f-l*0.8f);
                r+=gr; g+=gr; b+=gr;

                dst[i*3  ]=clamp8(clampf(r,0.f,1.f)*255.f);
                dst[i*3+1]=clamp8(clampf(g,0.f,1.f)*255.f);
                dst[i*3+2]=clamp8(clampf(b,0.f,1.f)*255.f);
            }
        }

        // ---------------------------------------------------------------
        // 7. Shadow zones -> dark purple body mix + lighter purple rim
        // ---------------------------------------------------------------
        // Blur the binary mask into a soft occupancy field so the purple
        // follows the light falloff instead of the staircase of the mask,
        // and take the rim as the field's 0.46 iso-contour.
        for(int i=0;i<WH;i++) sfl[i]=smask[i]?1.f:0.f;
        boxBlur(&sfl[0],&sblur[0],W,H,11,&tmpf[0]);
        for(int y=0;y<H;y++) for(int x=0;x<W;x++){
            int i=y*W+x;
            float w=sblur[i];
            if(w<=0.02f) continue;
            float depth=clampf((shT-luma[i])/fmax_(shT,1.f),0.f,1.f);
            float ww=w*w*(3.f-2.f*w);                     // smoothstep
            px(&dst[0],x,y,DK_PURPLE,(0.17f+0.45f*depth)*ww);
            float d=w-0.46f; if(d<0) d=-d;
            if(d<0.19f) px(&dst[0],x,y,LT_PURPLE,(1.f-d/0.19f)*0.52f);
        }

        // ---------------------------------------------------------------
        // 8. Plant contour edges in bright green (mask boundary, 2 px)
        // ---------------------------------------------------------------
        for(int y=0;y<H;y++) for(int x=0;x<W;x++){
            int i=y*W+x;
            if(!gmask[i]) continue;
            int edge = (x==0||y==0||x==W-1||y==H-1) ? 1 :
                       (!gmask[i-1]||!gmask[i+1]||!gmask[i-W]||!gmask[i+W]);
            if(!edge) continue;
            px(&dst[0],x,y,PLANT_GRN,0.95f);
            px(&dst[0],x+1,y,PLANT_GRN,0.55f);
            px(&dst[0],x,y+1,PLANT_GRN,0.55f);
            px(&dst[0],x-1,y,PLANT_GRN,0.25f);
            px(&dst[0],x,y-1,PLANT_GRN,0.25f);
        }

        // ---------------------------------------------------------------
        // 9. Bounding boxes: plant clusters, high-velocity, low-velocity
        // ---------------------------------------------------------------
        components(&gmask[0],W,H,900,plantBoxes,8);
        mergeBoxes(plantBoxes,26);
        if((int)plantBoxes.size()>3) plantBoxes.resize(3);
        components(&hiBlk[0],BX,BY,4,hiBoxes,8);
        mergeBoxes(hiBoxes,0);
        for(size_t k=0;k<hiBoxes.size();){          // reject sprawling zones
            Box& hb=hiBoxes[k];
            int a=(hb.x1-hb.x0+1)*(hb.y1-hb.y0+1);
            if(a>NB*0.42f || hb.area*3<a) hiBoxes.erase(hiBoxes.begin()+k);
            else k++;
        }
        if((int)hiBoxes.size()>2) hiBoxes.resize(2);
        components(&loBlk[0],BX,BY,10,loBoxes,8);
        mergeBoxes(loBoxes,0);
        for(size_t k=0;k<loBoxes.size();){
            Box& lb=loBoxes[k];
            int a=(lb.x1-lb.x0+1)*(lb.y1-lb.y0+1);
            if(a>NB*0.42f || lb.area*3<a) loBoxes.erase(loBoxes.begin()+k);
            else k++;
        }
        if((int)loBoxes.size()>1) loBoxes.resize(1);

        // -- label helper: "KIND" then X / Y / W / H in pure R, G, B ------
        // Labels claim space as they are drawn; a later label that would
        // land on an earlier one steps down until it finds clear frame.
        int usedN=0; int usedR[12][4];
        // -- label: "KIND" then X / Y / W / H in pure R, G and B --------
        #define LABEL(bx0,by0,kind,X,Y,Wd,Ht)                                  \
        {                                                                      \
            char p0[24],p1[24],p2[24],p3[24];                                  \
            snprintf(p0,sizeof p0,"X%d",(X)); snprintf(p1,sizeof p1,"Y%d",(Y));\
            snprintf(p2,sizeof p2,"W%d",(Wd)); snprintf(p3,sizeof p3,"H%d",(Ht));\
            int lw=textW(kind,2)+textW(p0,2)+textW(p1,2)+textW(p2,2)+          \
                   textW(p3,2)+4*7;                                            \
            int lx=bx0, ly=(by0)-26;                                           \
            if(ly<64) ly=(by0)+8; if(ly<64) ly=64; if(ly>H-24) ly=H-24;        \
            if(lx+lw>W-7) lx=W-7-lw;                                           \
            if(lx<7) lx=7;                                                     \
            for(int gg=0;gg<24;gg++){                                          \
                int hit=0;                                                     \
                for(int u=0;u<usedN;u++)                                       \
                    if(lx-5<=usedR[u][2] && usedR[u][0]<=lx+lw+4 &&            \
                       ly-5<=usedR[u][3] && usedR[u][1]<=ly+18) { hit=1; break; } \
                if(!hit) break;                                                \
                ly+=26;                                                        \
                if(ly>H-40){ ly=64; break; }                                   \
            }                                                                  \
            if(usedN<12){ usedR[usedN][0]=lx-5; usedR[usedN][1]=ly-5;          \
                          usedR[usedN][2]=lx+lw+4; usedR[usedN][3]=ly+18; usedN++; } \
            fillRect(&dst[0],lx-5,ly-5,lx+lw+4,ly+18,NAVY,0.82f);              \
            strokeRect(&dst[0],lx-5,ly-5,lx+lw+4,ly+18,NAVY_LIT,0.9f,1,0);     \
            int cxp=lx;                                                        \
            drawTextOut(&dst[0],cxp,ly,kind,NAVY_LIT,2,1.f); cxp+=textW(kind,2)+7;\
            drawTextOut(&dst[0],cxp,ly,p0,PURE_R,2,1.f);     cxp+=textW(p0,2)+7;\
            drawTextOut(&dst[0],cxp,ly,p1,PURE_G,2,1.f);     cxp+=textW(p1,2)+7;\
            drawTextOut(&dst[0],cxp,ly,p2,PURE_B,2,1.f);     cxp+=textW(p2,2)+7;\
            drawTextOut(&dst[0],cxp,ly,p3,PURE_B,2,1.f);                       \
        }

        for(size_t k=0;k<plantBoxes.size();k++){
            Box& b=plantBoxes[k];
            strokeRect(&dst[0],b.x0,b.y0,b.x1,b.y1,NAVY,0.95f,3,0);
            strokeRect(&dst[0],b.x0-3,b.y0-3,b.x1+3,b.y1+3,NAVY_LIT,0.75f,1,0);
            corners(&dst[0],b.x0,b.y0,b.x1,b.y1,PLANT_GRN,0.9f,14,1);
            LABEL(b.x0,b.y0,"PLANT",b.x0,b.y0,b.x1-b.x0+1,b.y1-b.y0+1);
            fprintf(fb,"%d\tPLANT\t%d\t%d\t%d\t%d\t%d\n",frame,b.x0,b.y0,
                    b.x1-b.x0+1,b.y1-b.y0+1,b.area);
        }
        for(size_t k=0;k<hiBoxes.size();k++){
            Box b=hiBoxes[k];
            int x0=b.x0*BS*2, y0=b.y0*BS*2, x1=(b.x1+1)*BS*2-1, y1=(b.y1+1)*BS*2-1;
            strokeRect(&dst[0],x0,y0,x1,y1,NAVY,0.9f,3,1);
            corners(&dst[0],x0,y0,x1,y1,NAVY_LIT,0.9f,18,2);
            LABEL(x0,y0,"VEL-HI",x0,y0,x1-x0+1,y1-y0+1);
            fprintf(fb,"%d\tVEL-HI\t%d\t%d\t%d\t%d\t%d\n",frame,x0,y0,x1-x0+1,y1-y0+1,b.area);
        }
        for(size_t k=0;k<loBoxes.size();k++){
            Box b=loBoxes[k];
            int x0=b.x0*BS*2, y0=b.y0*BS*2, x1=(b.x1+1)*BS*2-1, y1=(b.y1+1)*BS*2-1;
            strokeRect(&dst[0],x0,y0,x1,y1,NAVY,0.75f,2,2);
            LABEL(x0,y0,"VEL-LO",x0,y0,x1-x0+1,y1-y0+1);
            fprintf(fb,"%d\tVEL-LO\t%d\t%d\t%d\t%d\t%d\n",frame,x0,y0,x1-x0+1,y1-y0+1,b.area);
        }

        // motion vector ticks on the fast blocks
        for(int by=0;by<BY;by++) for(int bx=0;bx<BX;bx++){
            int b=by*BX+bx; if(!hiBlk[b]) continue;
            if(((bx+by)&1)) continue;
            int ox=(bx*BS+BS/2)*2, oy=(by*BS+BS/2)*2;
            float sc=1.6f;
            int ex=ox+(int)(mvx[b]*sc), ey=oy+(int)(mvy[b]*sc);
            int steps=imax(abs(ex-ox),abs(ey-oy));
            for(int s=0;s<=steps;s++){
                int lx=ox+(ex-ox)*s/imax(steps,1);
                int ly=oy+(ey-oy)*s/imax(steps,1);
                px(&dst[0],lx,ly,NAVY_LIT,0.45f);
            }
            px(&dst[0],ox,oy,PURE_B,0.8f);
        }

        // ---------------------------------------------------------------
        // 10. HUD -- readout of everything driving the score
        // ---------------------------------------------------------------
        float t=frame/FPS;
        fillRect(&dst[0],0,0,W-1,58,NAVY,0.92f);
        strokeRect(&dst[0],0,0,W-1,58,NAVY_LIT,0.6f,1,0);
        snprintf(buf,sizeof buf,"PCAV F%04d T%d.%02dS",frame,(int)t,(int)(t*100)%100);
        drawTextOut(&dst[0],10,8,buf,NAVY_LIT,2,1.f);
        snprintf(buf,sizeof buf,"VEL%d.%02d",(int)smoothCam,(int)(smoothCam*100)%100);
        drawTextOut(&dst[0],10,32,buf,PURE_R,2,1.f);
        snprintf(buf,sizeof buf,"LOC%d.%02d",(int)smoothLocal,(int)(smoothLocal*100)%100);
        drawTextOut(&dst[0],10+textW("VEL0.00",2)+10,32,buf,PURE_G,2,1.f);
        snprintf(buf,sizeof buf,"SHD%d",(int)(shadowFrac*100));
        drawTextOut(&dst[0],10+2*(textW("VEL0.00",2)+10),32,buf,PURE_B,2,1.f);
        snprintf(buf,sizeof buf,"LEAF%d",(int)(gArea*1000.0/WH));
        drawTextOut(&dst[0],10+3*(textW("VEL0.00",2)+10),32,buf,PLANT_GRN,2,1.f);

        // velocity meter along the bottom
        int mw=W-40, mx0=20, my0=H-30;
        fillRect(&dst[0],mx0-3,my0-3,mx0+mw+3,my0+15,NAVY,0.55f);
        int fill=(int)(clampf(smoothCam/14.f,0.f,1.f)*mw);
        for(int x=0;x<fill;x++){
            float f2=(float)x/mw;
            RGB c={255.f*f2,255.f*(1.f-f2*0.4f),90.f};
            fillRect(&dst[0],mx0+x,my0,mx0+x,my0+11,c,0.85f);
        }
        int shx=(int)(clampf(smoothShadow*9.f,0.f,1.f)*mw);
        for(int x=0;x<shx;x++) fillRect(&dst[0],mx0+x,my0+12,mx0+x,my0+12,LT_PURPLE,0.9f);
        strokeRect(&dst[0],mx0-3,my0-3,mx0+mw+3,my0+15,NAVY_LIT,0.7f,1,0);

        // plant centroid crosshair
        if(gArea>0){
            int px0=(int)gcx, py0=(int)gcy;
            for(int k=-12;k<=12;k++){
                px(&dst[0],px0+k,py0,PLANT_GRN,0.75f);
                px(&dst[0],px0,py0+k,PLANT_GRN,0.75f);
            }
        }
        // shadow centroid marker
        if(sArea>0){
            int sx0=(int)scx, sy0=(int)scy;
            strokeRect(&dst[0],sx0-9,sy0-9,sx0+9,sy0+9,LT_PURPLE,0.85f,1,2);
        }

        // ---------------------------------------------------------------
        // 11. Emit
        // ---------------------------------------------------------------
        fwrite(&dst[0],1,(size_t)WH*3,stdout);
        fprintf(fm,"%d\t%.4f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.4f\t%.4f\t%.4f\t"
                   "%.5f\t%d\t%.1f\t%.1f\t%.4f\t%.5f\t%.1f\t%.1f\t%.2f\n",
                frame,t,camMag,camDx,camDy,meanMag,maxMag,
                (float)nHi/NB,(float)nLo/NB,localE,
                (float)(gArea/WH),(int)plantBoxes.size(),(float)gcx,(float)gcy,
                shadowFrac,shadowChange,(float)scx,(float)scy,lumaMean);

        memcpy(&prevHalf[0],&half[0],HWH);
        memcpy(&prevSmask[0],&smask[0],WH);
        havePrev=1;
        frame++;
        if((frame%25)==0) fprintf(stderr,"  pcav: %d frames\n",frame);
    }
    fclose(fm); fclose(fb);
    fprintf(stderr,"  pcav: done, %d frames\n",frame);
    return 0;
}
