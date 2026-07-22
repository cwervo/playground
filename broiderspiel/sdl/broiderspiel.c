// ===========================================================================
// Broiderspiel — SDL2 + OpenGL (GLSL) port
//
// The same toy as the WebGL/Tk versions, but this is where "shader-accelerated
// GPU rendering" is literal:
//
//   * The falling-sand CA runs on the CPU over a small cell grid (type + life).
//   * Each frame we upload two tiny textures — RG8 "field" (type,life) for the
//     whole grid and RGB8 "bcol" for the persistent broider border — and a
//     single fullscreen-triangle FRAGMENT SHADER does ALL the coloring on the
//     GPU: element palette, per-cell hash noise, and fire/smoke gradients.
//     The CPU never touches an output pixel, which is what keeps frame time
//     (and thus FPS cost) down as the window scales up.
//   * The UI is IMMEDIATE MODE: every frame we rebuild the element-palette bar,
//     the pause banner, and the debug FPS sparkline as blended GPU primitives
//     from current state — no retained widget tree.
//
// Controls: drag=paint  1..6=element  space=pause  d=debug sparkline
//           double-click=pause + save a PPM snapshot ("share")  esc/q=quit
//
// Headless capture (used to build book figures):
//   ./broiderspiel --frames 600 --debug --out shot.ppm
// ===========================================================================
#include <GL/glew.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

// ---- elements -------------------------------------------------------------
enum { EMPTY, WALL, SAND, WATER, WOOD, PLANT, FIRE, SMOKE, STONE };
static const int BRUSHES[] = { SAND, WATER, WOOD, PLANT, FIRE, STONE };
static const int NBRUSH = 6;

// ---- global grid state ----------------------------------------------------
static int W, H, N;
static int bandX, bandY, ix0, iy0, ix1, iy1, cell;
static unsigned char *type_, *life_;   // W*H each
static unsigned char *field;           // W*H*2  (type,life) upload buffer
static unsigned char *bcol;            // W*H*3  persistent broider colours
static int frame = 0, paused = 0, debug = 0, brush = 0;
static const unsigned char BG[3] = { 12, 12, 20 };

static inline int idx(int x, int y) { return y * W + x; }
static inline int inbox(int x, int y){ return x>=ix0&&x<=ix1&&y>=iy0&&y<=iy1; }
static inline int isborder(int x,int y){ return x<bandX||x>=W-bandX||y<bandY||y>=H-bandY; }
static inline float frand(void){ return (float)rand()/(float)RAND_MAX; }

// ---- broider walkers ------------------------------------------------------
typedef struct { int top; float x,y,vx,vy,hue,dh; } Walker;
static Walker walkers[6]; static int nwalk = 0;

static void hsv(float h,float s,float v,unsigned char*out){
    h = fmodf(fmodf(h,1.f)+1.f,1.f);
    int i=(int)(h*6); float f=h*6-i, p=v*(1-s), q=v*(1-f*s), t=v*(1-(1-f)*s), r,g,b;
    switch(i%6){case 0:r=v;g=t;b=p;break;case 1:r=q;g=v;b=p;break;case 2:r=p;g=v;b=t;break;
                case 3:r=p;g=q;b=v;break;case 4:r=t;g=p;b=v;break;default:r=v;g=p;b=q;}
    out[0]=(unsigned char)(r*255); out[1]=(unsigned char)(g*255); out[2]=(unsigned char)(b*255);
}

static void seed(void){
    for(int x=ix0;x<=ix1;x++){
        if(frand()<0.55f){ type_[idx(x,iy1)]=PLANT;
            if(frand()<0.4f && iy1-1>=iy0) type_[idx(x,iy1-1)]=PLANT; }
    }
    nwalk=0;
    for(int i=0;i<3;i++){
        walkers[nwalk++]=(Walker){1, frand()*W, frand()*bandY,
            (frand()<0.5f?-1:1)*(0.6f+frand()), 0, frand(), 0.002f+frand()*0.004f};
        walkers[nwalk++]=(Walker){0, frand()*bandX, frand()*H, 0,
            (frand()<0.5f?-1:1)*(0.6f+frand()), frand(), 0.002f+frand()*0.004f};
    }
}

// ---- sandspiel CA ---------------------------------------------------------
static inline void swap_cell(int a,int b){
    unsigned char t=type_[a]; type_[a]=type_[b]; type_[b]=t;
    t=life_[a]; life_[a]=life_[b]; life_[b]=t;
}
static void emit(int x,int y,int t){ if(inbox(x,y)&&type_[idx(x,y)]==EMPTY) type_[idx(x,y)]=t; }

static void stepSand(void){
    int bw = ix1-ix0;
    if(frame%2==0)   emit(ix0+(int)(bw*0.32f), iy0+1, SAND);
    if(frame%3==0)   emit(ix0+(int)(bw*0.68f), iy0+1, WATER);
    if(frame%220==0){ int i=idx(ix0+(int)(bw*0.5f), iy0+1); type_[i]=FIRE; life_[i]=40; }

    for(int y=iy1; y>=iy0; y--){
        int l2r = ((frame+y)&1)==0;
        for(int k=0; k<=ix1-ix0; k++){
            int x = l2r ? ix0+k : ix1-k;
            int i = y*W+x, t = type_[i];
            if(t==EMPTY||t==WALL||t==STONE||t==WOOD) continue;
            if(t==SAND){
                int d=i+W;
                if(y<iy1 && (type_[d]==EMPTY||type_[d]==WATER)){ swap_cell(i,d); continue; }
                int dir = frand()<0.5f?1:-1;
                if(y<iy1){
                    if(inbox(x+dir,y+1)&&(type_[d+dir]==EMPTY||type_[d+dir]==WATER)){ swap_cell(i,d+dir); continue; }
                    if(inbox(x-dir,y+1)&&(type_[d-dir]==EMPTY||type_[d-dir]==WATER)){ swap_cell(i,d-dir); continue; }
                }
            } else if(t==WATER){
                int d=i+W;
                if(y<iy1 && type_[d]==EMPTY){ swap_cell(i,d); continue; }
                int dir = frand()<0.5f?1:-1;
                if(y<iy1){
                    if(inbox(x+dir,y+1)&&type_[d+dir]==EMPTY){ swap_cell(i,d+dir); continue; }
                    if(inbox(x-dir,y+1)&&type_[d-dir]==EMPTY){ swap_cell(i,d-dir); continue; }
                }
                if(inbox(x+dir,y)&&type_[i+dir]==EMPTY){ swap_cell(i,i+dir); continue; }
                if(inbox(x-dir,y)&&type_[i-dir]==EMPTY){ swap_cell(i,i-dir); continue; }
            } else if(t==FIRE){
                life_[i]--;
                int ext=0, nb[4]={i-W,i+W,i-1,i+1}, nx[4]={x,x,x-1,x+1}, ny[4]={y-1,y+1,y,y};
                for(int n=0;n<4;n++){ if(!inbox(nx[n],ny[n])) continue; int nt=type_[nb[n]];
                    if((nt==WOOD||nt==PLANT)&&frand()<0.28f){ type_[nb[n]]=FIRE; life_[nb[n]]=22+(int)(frand()*22); }
                    else if(nt==WATER) ext=1; }
                if(ext){ type_[i]=SMOKE; life_[i]=26; continue; }
                if(life_[i]==0){ type_[i]= frand()<0.5f?SMOKE:EMPTY; life_[i]=30; continue; }
                int u=i-W; if(y>iy0 && type_[u]==EMPTY && frand()<0.4f){ swap_cell(i,u); continue; }
            } else if(t==SMOKE){
                if(--life_[i]==0){ type_[i]=EMPTY; continue; }
                int u=i-W, dir=frand()<0.5f?1:-1;
                if(y>iy0){
                    if(type_[u]==EMPTY){ swap_cell(i,u); continue; }
                    if(inbox(x+dir,y-1)&&type_[u+dir]==EMPTY){ swap_cell(i,u+dir); continue; }
                    if(inbox(x-dir,y-1)&&type_[u-dir]==EMPTY){ swap_cell(i,u-dir); continue; }
                }
            } else if(t==PLANT){
                if(frand()<0.12f){
                    int wat=-1, emp=-1, nb[4]={i-W,i+W,i-1,i+1}, nx[4]={x,x,x-1,x+1}, ny[4]={y-1,y+1,y,y};
                    for(int n=0;n<4;n++){ if(!inbox(nx[n],ny[n])) continue; int nt=type_[nb[n]];
                        if(nt==WATER) wat=nb[n]; else if(nt==EMPTY) emp=nb[n]; }
                    if(wat>=0&&emp>=0){ type_[emp]=PLANT; if(frand()<0.5f) type_[wat]=EMPTY; }
                }
            }
        }
    }
}

// ---- broider ---------------------------------------------------------------
static void stitch(int x,int y,unsigned char*c){
    int px[4]={x,W-1-x,x,W-1-x}, py[4]={y,y,H-1-y,H-1-y};
    for(int p=0;p<4;p++) for(int o=-1;o<=1;o++){
        int a=px[p]+o;
        if(a>=0&&a<W&&py[p]>=0&&py[p]<H&&isborder(a,py[p])){ int j=idx(a,py[p])*3; bcol[j]=c[0];bcol[j+1]=c[1];bcol[j+2]=c[2]; }
        int b2=py[p]+o;
        if(px[p]>=0&&px[p]<W&&b2>=0&&b2<H&&isborder(px[p],b2)){ int j=idx(px[p],b2)*3; bcol[j]=c[0];bcol[j+1]=c[1];bcol[j+2]=c[2]; }
    }
}
static void stepBroider(void){
    if(frame%4==0){
        for(int y=0;y<H;y++) for(int x=0;x<W;x++){ if(!isborder(x,y)) continue; int j=idx(x,y)*3;
            bcol[j]  += (BG[0]-bcol[j])  *0.05f; bcol[j+1]+= (BG[1]-bcol[j+1])*0.05f; bcol[j+2]+= (BG[2]-bcol[j+2])*0.05f; }
    }
    for(int i=0;i<nwalk;i++){ Walker*w=&walkers[i];
        w->hue=fmodf(w->hue+w->dh,1.f); unsigned char c[3]; hsv(w->hue,0.65f+frand()*0.25f,0.95f,c);
        if(w->top){ w->x+=w->vx; w->y+=(frand()-0.5f)*0.9f;
            if(w->x<0){w->x=0;w->vx=fabsf(w->vx);} if(w->x>W-1){w->x=W-1;w->vx=-fabsf(w->vx);}
            if(w->y<0)w->y=0; if(w->y>bandY-1)w->y=bandY-1;
        } else { w->y+=w->vy; w->x+=(frand()-0.5f)*0.9f;
            if(w->y<0){w->y=0;w->vy=fabsf(w->vy);} if(w->y>H-1){w->y=H-1;w->vy=-fabsf(w->vy);}
            if(w->x<0)w->x=0; if(w->x>bandX-1)w->x=bandX-1;
        }
        stitch((int)w->x,(int)w->y,c);
    }
}

// ---- GL helpers -----------------------------------------------------------
static GLuint mkshader(GLenum k,const char*s){
    GLuint sh=glCreateShader(k); glShaderSource(sh,1,&s,NULL); glCompileShader(sh);
    GLint ok; glGetShaderiv(sh,GL_COMPILE_STATUS,&ok);
    if(!ok){ char log[2048]; glGetShaderInfoLog(sh,2048,NULL,log); fprintf(stderr,"shader: %s\n",log); exit(1);} return sh;
}
static GLuint mkprog(const char*vs,const char*fs){
    GLuint p=glCreateProgram(); glAttachShader(p,mkshader(GL_VERTEX_SHADER,vs)); glAttachShader(p,mkshader(GL_FRAGMENT_SHADER,fs));
    glLinkProgram(p); GLint ok; glGetProgramiv(p,GL_LINK_STATUS,&ok);
    if(!ok){ char log[2048]; glGetProgramInfoLog(p,2048,NULL,log); fprintf(stderr,"link: %s\n",log); exit(1);} return p;
}

static const char* FIELD_VS =
"#version 330 core\n"
"out vec2 v_uv;\n"
"void main(){ vec2 v[3]=vec2[](vec2(-1,-1),vec2(3,-1),vec2(-1,3));\n"
"  vec2 p=v[gl_VertexID]; v_uv=vec2((p.x+1.0)*0.5,(1.0-p.y)*0.5); gl_Position=vec4(p,0,1);}";
static const char* FIELD_FS =
"#version 330 core\n"
"in vec2 v_uv; out vec4 o;\n"
"uniform sampler2D u_field; uniform sampler2D u_bcol;\n"
"uniform vec2 u_grid; uniform vec4 u_box;\n" // box = ix0,iy0,ix1,iy1
"float hash(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }\n"
"void main(){\n"
"  vec2 cell = floor(v_uv*u_grid);\n"
"  bool box = cell.x>=u_box.x && cell.x<=u_box.z && cell.y>=u_box.y && cell.y<=u_box.w;\n"
"  if(!box){ o=vec4(texture(u_bcol,v_uv).rgb,1.0); return; }\n"
"  vec2 f = texture(u_field,v_uv).rg; int t=int(f.r*255.0+0.5); float life=f.g*255.0;\n"
"  float n=(hash(cell)-0.5);\n"
"  vec3 c;\n"
"  if(t==0)      c=vec3(12,12,20)/255.0;\n"
"  else if(t==1) c=vec3(80,84,96)/255.0;\n"
"  else if(t==2) c=vec3(198,176,88)/255.0 + n*0.10;\n"      // SAND
"  else if(t==3) c=vec3(40,96,200)/255.0 + n*0.08;\n"       // WATER
"  else if(t==4) c=vec3(110,66,38)/255.0 + n*0.07;\n"       // WOOD
"  else if(t==5) c=vec3(46,150,60)/255.0 + n*0.12;\n"       // PLANT
"  else if(t==6){ float k=clamp(life/40.0,0.0,1.0); c=vec3(255.0,90.0+k*150.0,20.0+k*60.0)/255.0; }\n" // FIRE
"  else if(t==7){ float k=clamp(life/30.0,0.0,1.0); float g=(60.0+k*45.0)/255.0; c=vec3(g,g,g+0.02); }\n" // SMOKE
"  else          c=vec3(104,104,112)/255.0 + n*0.08;\n"     // STONE
"  o=vec4(c,1.0);\n"
"}";

static const char* UI_VS =
"#version 330 core\n"
"layout(location=0) in vec2 a_pos; layout(location=1) in vec4 a_col;\n"
"uniform vec2 u_res; out vec4 v_col;\n"
"void main(){ vec2 p=a_pos/u_res*2.0-1.0; p.y=-p.y; gl_Position=vec4(p,0,1); v_col=a_col; }";
static const char* UI_FS =
"#version 330 core\n"
"in vec4 v_col; out vec4 o; void main(){ o=v_col; }";

// ---- immediate-mode primitive batch --------------------------------------
typedef struct { float x,y,r,g,b,a; } Vtx;
static Vtx *uiv=NULL; static int uin=0, uicap=0;
static void push(float x,float y,float r,float g,float b,float a){
    if(uin>=uicap){ uicap=uicap?uicap*2:4096; uiv=realloc(uiv,uicap*sizeof(Vtx)); }
    uiv[uin++]=(Vtx){x,y,r,g,b,a};
}
static void rect(float x,float y,float w,float h,float r,float g,float b,float a){
    push(x,y,r,g,b,a); push(x+w,y,r,g,b,a); push(x+w,y+h,r,g,b,a);
    push(x,y,r,g,b,a); push(x+w,y+h,r,g,b,a); push(x,y+h,r,g,b,a);
}
// 3x5 digit font (rows top->bottom, 3 bits each) for the FPS readout
static const unsigned short DIG[10]={
0x7B6F,0x2492,0x73E7,0x73CF,0x5BC9,0x79CF,0x79EF,0x7249,0x7BEF,0x7BC9};
static void digit(int d,float x,float y,float s){
    unsigned short m=DIG[d%10];
    for(int r=0;r<5;r++) for(int c=0;c<3;c++) if(m&(1<<(14-(r*3+c)))) rect(x+c*s,y+r*s,s,s,1,1,1,0.9f);
}
static void number(int v,float x,float y,float s){
    char b[16]; int n=snprintf(b,16,"%d",v);
    for(int i=0;i<n;i++){ digit(b[i]-'0',x+i*4*s,y,s); }
}

// ---- fps history ----------------------------------------------------------
#define FPS_CAP 4096
static float fpsHist[FPS_CAP*2]; static int fpsN=0;
static void recordFps(float dt){
    if(dt<=0) return;
    float v=1.f/dt; if(v>1000.f) v=1000.f;   // clamp timer-resolution spikes
    if(fpsN>=FPS_CAP*2){ for(int i=0;i<FPS_CAP;i++) fpsHist[i]=(fpsHist[i*2]+fpsHist[i*2+1])*0.5f; fpsN=FPS_CAP; }
    fpsHist[fpsN++]=v;
}
static void sparkline(int winW,int winH){
    float bandH = winH*0.10f; if(bandH<8) bandH=8;
    float y0 = winH - bandH;
    rect(0,y0,winW,bandH, 0,0,0, 0.35f);                 // dim band
    if(fpsN==0) return;
    float mx=60; for(int i=0;i<fpsN;i++) if(fpsHist[i]>mx) mx=fpsHist[i];
    float colw = (float)winW/winW; (void)colw;
    float prevY=-1;
    for(int x=0;x<winW;x++){
        int a=(int)((long)x*fpsN/winW), b=(int)((long)(x+1)*fpsN/winW); if(b<=a) b=a+1;
        float s=0; int c=0; for(int j=a;j<b&&j<fpsN;j++){ s+=fpsHist[j]; c++; }
        float avg = c? s/c : fpsHist[fpsN-1];
        float yy = y0 + bandH*(1.0f - (avg<mx?avg/mx:1.0f));
        rect(x, yy, 1, (winH-yy), 40/255.f,230/255.f,120/255.f, 0.5f);          // area
        if(prevY>=0){ float lo=prevY<yy?prevY:yy, hi=prevY<yy?yy:prevY;
            rect(x,lo,1,(hi-lo)+1, 180/255.f,255/255.f,210/255.f,0.7f); }        // ridge
        prevY=yy;
    }
    float refY = y0 + bandH*(1.0f - (60<mx?60/mx:1.0f));
    for(int x=0;x<winW;x+=3) rect(x,refY,2,1, 1,90/255.f,90/255.f,0.5f);         // 60fps ref
    // live fps number
    int cur=(int)(fpsHist[fpsN-1]+0.5f);
    number(cur, 6, y0+4, bandH>40?4:3);
}
static void palette_bar(int mx,int my,int click){
    // immediate-mode element selector, top-left; returns selection via globals
    float sw=26, pad=6, x0=10, y0=10;
    unsigned char sc[3];
    int cols[6][3]={{198,176,88},{40,96,200},{110,66,38},{46,150,60},{230,90,40},{104,104,112}};
    for(int i=0;i<NBRUSH;i++){
        float x=x0+i*(sw+pad), y=y0;
        int hot = mx>=x&&mx<=x+sw&&my>=y&&my<=y+sw;
        if(click&&hot) brush=i;
        if(brush==i) rect(x-3,y-3,sw+6,sw+6, 1,1,1,0.9f);       // selection ring
        (void)sc;
        rect(x,y,sw,sw, cols[i][0]/255.f,cols[i][1]/255.f,cols[i][2]/255.f, 1.0f);
    }
}

// ---- allocation -----------------------------------------------------------
static void alloc_grid(int winW,int winH){
    cell = (int)ceilf((float)(winW>winH?winW:winH)/300.0f); if(cell<1) cell=1;
    W=winW/cell; H=winH/cell; if(W<16)W=16; if(H<16)H=16; N=W*H;
    type_=calloc(N,1); life_=calloc(N,1); field=calloc(N*2,1); bcol=malloc(N*3);
    for(int i=0;i<N;i++){ bcol[i*3]=BG[0]; bcol[i*3+1]=BG[1]; bcol[i*3+2]=BG[2]; }
    bandX=(int)roundf(0.04f*W); if(bandX<1)bandX=1;
    bandY=(int)roundf(0.04f*H); if(bandY<1)bandY=1;
    int mx=(int)roundf(0.08f*W), my=(int)roundf(0.08f*H);
    ix0=mx; ix1=W-1-mx; iy0=my; iy1=H-1-my;
}

static void write_ppm(const char*path,int w,int h){
    unsigned char*px=malloc(w*h*3);
    glReadPixels(0,0,w,h,GL_RGB,GL_UNSIGNED_BYTE,px);
    FILE*f=fopen(path,"wb"); fprintf(f,"P6\n%d %d\n255\n",w,h);
    for(int y=h-1;y>=0;y--) fwrite(px+y*w*3,1,w*3,f);   // flip: GL origin is bottom-left
    fclose(f); free(px); printf("wrote %s (%dx%d, %d fps samples)\n",path,w,h,fpsN);
}

int main(int argc,char**argv){
    int winW=960, winH=600, batch=0; const char*out="broiderspiel.ppm";
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--frames")) batch=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--out")) out=argv[++i];
        else if(!strcmp(argv[i],"--debug")) debug=1;
        else if(!strcmp(argv[i],"--size")){ winW=atoi(argv[++i]); winH=atoi(argv[++i]); }
    }
    srand((unsigned)time(NULL));
    if(SDL_Init(SDL_INIT_VIDEO)!=0){ fprintf(stderr,"SDL: %s\n",SDL_GetError()); return 1; }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION,3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION,3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER,1);
    SDL_Window*win=SDL_CreateWindow("Broiderspiel — SDL/OpenGL",
        SDL_WINDOWPOS_CENTERED,SDL_WINDOWPOS_CENTERED,winW,winH,
        SDL_WINDOW_OPENGL|(batch?SDL_WINDOW_HIDDEN:SDL_WINDOW_SHOWN));
    if(!win){ fprintf(stderr,"win: %s\n",SDL_GetError()); return 1; }
    SDL_GLContext ctx=SDL_GL_CreateContext(win);
    if(!ctx){ fprintf(stderr,"ctx: %s\n",SDL_GetError()); return 1; }
    glewExperimental=GL_TRUE; glewInit();
    SDL_GL_SetSwapInterval(batch?0:1);

    alloc_grid(winW,winH); seed();

    GLuint progF=mkprog(FIELD_VS,FIELD_FS), progU=mkprog(UI_VS,UI_FS);
    GLuint vaoF; glGenVertexArrays(1,&vaoF);
    GLuint vaoU,vboU; glGenVertexArrays(1,&vaoU); glGenBuffers(1,&vboU);
    glBindVertexArray(vaoU); glBindBuffer(GL_ARRAY_BUFFER,vboU);
    glEnableVertexAttribArray(0); glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,sizeof(Vtx),(void*)0);
    glEnableVertexAttribArray(1); glVertexAttribPointer(1,4,GL_FLOAT,GL_FALSE,sizeof(Vtx),(void*)(2*sizeof(float)));

    GLuint texF,texB;
    glGenTextures(1,&texF); glBindTexture(GL_TEXTURE_2D,texF);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D,0,GL_RG8,W,H,0,GL_RG,GL_UNSIGNED_BYTE,NULL);
    glGenTextures(1,&texB); glBindTexture(GL_TEXTURE_2D,texB);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D,0,GL_RGB8,W,H,0,GL_RGB,GL_UNSIGNED_BYTE,NULL);
    glPixelStorei(GL_UNPACK_ALIGNMENT,1);

    glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);

    int running=1, mdown=0, mx=0,my=0; Uint32 lastClick=0;
    Uint64 prev=SDL_GetPerformanceCounter(); double freq=(double)SDL_GetPerformanceFrequency();

    for(int f=0; running && (!batch || f<batch); f++){
        int click=0;
        if(!batch){
            SDL_Event e;
            while(SDL_PollEvent(&e)){
                if(e.type==SDL_QUIT) running=0;
                else if(e.type==SDL_KEYDOWN){
                    SDL_Keycode k=e.key.keysym.sym;
                    if(k==SDLK_ESCAPE||k==SDLK_q) running=0;
                    else if(k==SDLK_SPACE) paused=!paused;
                    else if(k==SDLK_d) debug=!debug;
                    else if(k>=SDLK_1 && k<=SDLK_6) brush=k-SDLK_1;
                }
                else if(e.type==SDL_MOUSEBUTTONDOWN && e.button.button==SDL_BUTTON_LEFT){
                    mdown=1; mx=e.button.x; my=e.button.y; click=1;
                    Uint32 now=SDL_GetTicks();
                    if(now-lastClick<300){ paused=1; write_ppm("broiderspiel-share.ppm",winW,winH); } // "share"
                    lastClick=now;
                }
                else if(e.type==SDL_MOUSEBUTTONUP) mdown=0;
                else if(e.type==SDL_MOUSEMOTION){ mx=e.motion.x; my=e.motion.y; }
            }
            if(mdown){   // paint
                int gx=mx/cell, gy=my/cell, t=BRUSHES[brush], r=(t==FIRE?1:2);
                for(int dy=-r;dy<=r;dy++) for(int dx=-r;dx<=r;dx++){
                    int x=gx+dx,y=gy+dy; if(inbox(x,y)){ int i=idx(x,y); type_[i]=t; if(t==FIRE) life_[i]=40; } }
            }
        }

        Uint64 nowc=SDL_GetPerformanceCounter(); double dt=(nowc-prev)/freq; prev=nowc;
        recordFps((float)dt);

        if(!paused){ stepSand(); stepBroider(); frame++; }

        // pack field (type,life) for GPU coloring
        for(int i=0;i<N;i++){ field[i*2]=type_[i]; field[i*2+1]=life_[i]; }

        // ---- draw: shader colours the whole grid on the GPU ----
        glViewport(0,0,winW,winH); glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(progF);
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D,texF);
        glTexSubImage2D(GL_TEXTURE_2D,0,0,0,W,H,GL_RG,GL_UNSIGNED_BYTE,field);
        glActiveTexture(GL_TEXTURE1); glBindTexture(GL_TEXTURE_2D,texB);
        glTexSubImage2D(GL_TEXTURE_2D,0,0,0,W,H,GL_RGB,GL_UNSIGNED_BYTE,bcol);
        glUniform1i(glGetUniformLocation(progF,"u_field"),0);
        glUniform1i(glGetUniformLocation(progF,"u_bcol"),1);
        glUniform2f(glGetUniformLocation(progF,"u_grid"),(float)W,(float)H);
        glUniform4f(glGetUniformLocation(progF,"u_box"),(float)ix0,(float)iy0,(float)ix1,(float)iy1);
        glBindVertexArray(vaoF); glDrawArrays(GL_TRIANGLES,0,3);

        // ---- immediate-mode UI + sparkline as blended GPU primitives ----
        uin=0;
        palette_bar(mx,my,click);
        if(paused) rect(0,0,winW,winH, 0,0,0,0.18f);       // dim while paused
        if(debug)  sparkline(winW,winH);
        if(uin>0){
            glUseProgram(progU);
            glUniform2f(glGetUniformLocation(progU,"u_res"),(float)winW,(float)winH);
            glBindVertexArray(vaoU); glBindBuffer(GL_ARRAY_BUFFER,vboU);
            glBufferData(GL_ARRAY_BUFFER,uin*sizeof(Vtx),uiv,GL_STREAM_DRAW);
            glDrawArrays(GL_TRIANGLES,0,uin);
        }

        if(batch){ if(f==batch-1){ glFinish(); write_ppm(out,winW,winH); } }
        else SDL_GL_SwapWindow(win);
    }

    SDL_GL_DeleteContext(ctx); SDL_DestroyWindow(win); SDL_Quit();
    return 0;
}
