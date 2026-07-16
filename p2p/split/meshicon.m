// meshicon.m — random OKLAB mesh-gradient generator using metaballs.
//
// Generates a 600x600 PNG: 3 metaballs randomly placed within the inner
// 500x500 design space, each with a random OKLab color. Every pixel blends
// the ball colors in OKLab weighted by the classic metaball field r²/d²,
// then converts OKLab → sRGB. Seeded by the current date-milliseconds
// timestamp (or an explicit seed), so every build stamps a unique,
// reproducible icon.
//
// Build:  clang -O2 -fobjc-arc meshicon.m -o meshicon \
//           -framework Foundation -framework CoreGraphics -framework ImageIO
// Usage:  meshicon <out.png> [seed-ms]   (seed defaults to now, in ms)

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static uint64_t rngState;

// xorshift64* — deterministic across platforms, unlike rand()/srand().
static double frnd(void) {
    rngState ^= rngState >> 12;
    rngState ^= rngState << 25;
    rngState ^= rngState >> 27;
    return ((rngState * 2685821657736338717ULL) >> 11) * (1.0 / 9007199254740992.0);
}

typedef struct { double L, a, b; } OKLab;

static double linearToSRGB(double v) {
    v = fmin(fmax(v, 0.0), 1.0);
    return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
}

// Björn Ottosson's OKLab → linear sRGB.
static void oklabToRGB(OKLab c, double *r, double *g, double *b) {
    double l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b;
    double m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b;
    double s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b;
    double l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    *r = linearToSRGB(+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s);
    *g = linearToSRGB(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s);
    *b = linearToSRGB(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: meshicon <out.png> [seed-ms]\n");
            return 64;
        }
        uint64_t seed = argc > 2
            ? strtoull(argv[2], NULL, 10)
            : (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
        rngState = seed ^ 0x9E3779B97F4A7C15ULL;
        if (rngState == 0) rngState = 1;

        const int size = 600;
        const double inset = 50.0; // inner 500x500 design space

        struct { double x, y, r; OKLab color; } balls[3];
        for (int i = 0; i < 3; i++) {
            balls[i].x = inset + frnd() * 500.0;
            balls[i].y = inset + frnd() * 500.0;
            balls[i].r = 90.0 + frnd() * 90.0;
            double hue = frnd() * 2.0 * M_PI;
            double chroma = 0.10 + frnd() * 0.12;
            balls[i].color = (OKLab){
                0.55 + frnd() * 0.30, chroma * cos(hue), chroma * sin(hue)};
        }
        double bgHue = frnd() * 2.0 * M_PI;
        OKLab background = {0.22 + frnd() * 0.18, 0.035 * cos(bgHue), 0.035 * sin(bgHue)};

        uint8_t *pixels = malloc((size_t)size * size * 4);
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                // Background contributes a constant weight of 1 so the field
                // fades into it far from the balls.
                OKLab acc = background;
                double wsum = 1.0;
                for (int i = 0; i < 3; i++) {
                    double dx = x + 0.5 - balls[i].x, dy = y + 0.5 - balls[i].y;
                    double w = (balls[i].r * balls[i].r) / (dx * dx + dy * dy + 1.0);
                    acc.L += w * balls[i].color.L;
                    acc.a += w * balls[i].color.a;
                    acc.b += w * balls[i].color.b;
                    wsum += w;
                }
                acc.L /= wsum; acc.a /= wsum; acc.b /= wsum;

                double r, g, b;
                oklabToRGB(acc, &r, &g, &b);
                uint8_t *p = pixels + 4 * ((size_t)y * size + x);
                p[0] = (uint8_t)lrint(r * 255.0);
                p[1] = (uint8_t)lrint(g * 255.0);
                p[2] = (uint8_t)lrint(b * 255.0);
                p[3] = 255;
            }
        }

        CGDataProviderRef provider = CGDataProviderCreateWithData(
            NULL, pixels, (size_t)size * size * 4, NULL);
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef image = CGImageCreate(
            size, size, 8, 32, (size_t)size * 4, space,
            kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault,
            provider, NULL, false, kCGRenderingIntentDefault);

        NSURL *out = [NSURL fileURLWithPath:@(argv[1])];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)out, CFSTR("public.png"), 1, NULL);
        if (!dest) { fprintf(stderr, "meshicon: cannot write %s\n", argv[1]); return 1; }
        CGImageDestinationAddImage(dest, image, NULL);
        bool ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        CGImageRelease(image);
        CGColorSpaceRelease(space);
        CGDataProviderRelease(provider);
        free(pixels);

        if (!ok) { fprintf(stderr, "meshicon: write failed\n"); return 1; }
        printf("seed=%llu → %s\n", (unsigned long long)seed, argv[1]);
        return 0;
    }
}
