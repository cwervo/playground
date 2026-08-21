// nvm.hpp — NeuroVM: a display-file bytecode for physiological reports.
//
// ---------------------------------------------------------------------------
// WHY A BYTECODE AND NOT JUST A JSON BLOB
// ---------------------------------------------------------------------------
// Sketchpad (Sutherland, 1963) did not store a picture. It stored a *display
// file*: a list of instructions that were re-executed on every refresh, so the
// drawing and the model it came from were the same object. Alan Kay's version
// of the same idea is that you should ship the interpreter, not the image,
// because meaning should be bound as late as possible. Engelbart's version is
// that the analyst has to be able to restructure the view without leaving the
// view.
//
// So: the C++ engine does the numerics exactly once and emits a .nvm file that
// is simultaneously
//   (a) the derived data          -- the symbol table
//   (b) the drawing program       -- the code section, immediate-mode
//   (c) the argument              -- PANEL / ANCHOR / NOTE / EDGE / CITE / FLAG
//
// Four independent hosts execute the same bytes:
//   tcl/nvm.tcl + tcl/explore.tcl   -> Tk canvas, live exploration
//   web/dashboard.html              -> HTML canvas, immediate mode at 60 Hz
//   physical/plot.tcl               -> SVG for a pen plotter / laser cutter
//   physical/solid.tcl              -> OpenSCAD for a 3D-printed data solid
//
// If a host disagrees with another host, the bytecode is the referee. That is
// the whole point: one artifact, many renderings, no re-derivation.
//
// ---------------------------------------------------------------------------
// CONTAINER (all integers little-endian)
// ---------------------------------------------------------------------------
//   off size field
//    0   4   magic  'N' 'V' 'M' '1'
//    4   2   version               (currently 1)
//    6   2   flags                 (bit0: meta section present)
//    8   4   strOff                offset of the string pool
//   12   4   strCount
//   16   4   strLen
//   20   4   symOff                offset of the symbol table
//   24   4   symCount
//   28   4   codeOff
//   32   4   codeLen
//   36   4   metaOff               JSON sidecar (derived stats, provenance)
//   40   4   metaLen
//   44   4   crc32                 CRC-32/ISO-HDLC over the code section only
//   48   4   entryPC               code-relative start address
//   52   4   canvasW               author's design-space width
//   56   4   canvasH               author's design-space height
//   60   4   reserved              must be 0
//   64  ..   sections in the order strings, symbols, code, meta
//
// String pool entry:  u16 byteLen, then that many UTF-8 bytes (no terminator).
// Symbol entry (28B): u16 nameIdx, u16 labelIdx, u16 flags, u16 pad,
//                     f32 value, f32 z, f32 dist, f32 refLo, f32 refHi
//                     flags bit0..1 = severity (0 ok, 1 borderline, 2 deviant,
//                                               3 not measured)
//                     flags bit2    = value is valid (0 => value is NaN)
//                     flags bit3..5 = domain id, for colour-by-domain
//                     flags bit6    = reference band present
//
// `z`    is the signed deviation in normative SD where a normative SD exists,
//        otherwise a reference-width-normalised pseudo-z (see analyze.cpp).
// `dist` is how far past the nearer reference edge the value sits, in units of
//        reference-band width. dist <= 0 means inside the band. This is the
//        number that tells you whether a red flag is a hairline miss (0.02) or
//        a real one (1.4), and every host is required to show it.
// ---------------------------------------------------------------------------
#pragma once

#include <cmath>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <vector>

namespace nvm {

// ---------------------------------------------------------------------------
// Instruction set
// ---------------------------------------------------------------------------
enum Op : uint8_t {
    // -- stack and constants -------------------------------------------------
    OP_HALT   = 0x00,
    OP_PUSHF  = 0x01,  // f32   -> push
    OP_PUSHI  = 0x02,  // i32   -> push (as float)
    OP_PUSHS  = 0x03,  // u16   -> push string index (as float, exact to 2^24)
    OP_DUP    = 0x04,
    OP_DROP   = 0x05,
    OP_SWAP   = 0x06,
    OP_OVER   = 0x07,

    // -- arithmetic ----------------------------------------------------------
    OP_ADD    = 0x10,
    OP_SUB    = 0x11,
    OP_MUL    = 0x12,
    OP_DIV    = 0x13,
    OP_NEG    = 0x14,
    OP_ABS    = 0x15,
    OP_MIN    = 0x16,
    OP_MAX    = 0x17,
    OP_CLAMP  = 0x18,  // v lo hi -> clamped
    OP_LERP   = 0x19,  // a b t   -> a+(b-a)t
    OP_MAP    = 0x1A,  // v i0 i1 o0 o1 -> remapped, the workhorse of plotting

    // -- data access (u16 symbol id) ----------------------------------------
    OP_LOADV  = 0x20,  // raw measured value
    OP_LOADZ  = 0x21,  // signed normative deviation
    OP_LOADD  = 0x22,  // distance past reference edge, in band widths

    // -- graphics state ------------------------------------------------------
    OP_RGBA   = 0x30,  // u8 r, u8 g, u8 b, u8 a
    OP_LINEW  = 0x31,  // f32
    OP_FONT   = 0x32,  // u16 nameIdx, f32 size
    OP_PUSHMAT= 0x33,
    OP_POPMAT = 0x34,
    OP_TRANS  = 0x35,  // (x y)
    OP_SCALE  = 0x36,  // (sx sy)
    OP_ROT    = 0x37,  // (radians)

    // -- immediate-mode drawing ---------------------------------------------
    OP_CLEAR  = 0x40,
    OP_MOVETO = 0x41,  // (x y)
    OP_LINETO = 0x42,  // (x y)
    OP_PATH   = 0x43,  // begin path
    OP_CLOSE  = 0x44,
    OP_STROKE = 0x45,
    OP_FILL   = 0x46,
    OP_RECT   = 0x47,  // (x y w h)
    OP_CIRCLE = 0x48,  // (x y r)
    OP_ARC    = 0x49,  // (x y r a0 a1)
    OP_TEXT   = 0x4A,  // u16 strIdx, u8 anchor(0 left 1 centre 2 right); (x y)

    // -- semantic layer ------------------------------------------------------
    OP_PANEL  = 0x50,  // u16 idIdx, u16 titleIdx
    OP_ENDPAN = 0x51,
    OP_ANCHOR = 0x52,  // u16 idIdx  -- primitives until the next ANCHOR are a hit target
    OP_NOTE   = 0x53,  // u16 plainIdx, u16 fullIdx  -- the two registers of explanation
    OP_EDGE   = 0x54,  // u16 aIdx, u16 bIdx, u16 hypIdx, f32 weight, i8 sign
    OP_FLAG   = 0x55,  // u8 severity
    OP_CITE   = 0x56,  // u16 strIdx

    // -- control -------------------------------------------------------------
    OP_JMP    = 0x60,  // i16 relative to the byte after the operand
    OP_JZ     = 0x61,  // i16, taken when the popped value is 0
    OP_CALL   = 0x62,  // u16 absolute code offset
    OP_RET    = 0x63,
};

inline const char* opName(uint8_t op) {
    switch (op) {
        case OP_HALT:   return "HALT";
        case OP_PUSHF:  return "PUSHF";
        case OP_PUSHI:  return "PUSHI";
        case OP_PUSHS:  return "PUSHS";
        case OP_DUP:    return "DUP";
        case OP_DROP:   return "DROP";
        case OP_SWAP:   return "SWAP";
        case OP_OVER:   return "OVER";
        case OP_ADD:    return "ADD";
        case OP_SUB:    return "SUB";
        case OP_MUL:    return "MUL";
        case OP_DIV:    return "DIV";
        case OP_NEG:    return "NEG";
        case OP_ABS:    return "ABS";
        case OP_MIN:    return "MIN";
        case OP_MAX:    return "MAX";
        case OP_CLAMP:  return "CLAMP";
        case OP_LERP:   return "LERP";
        case OP_MAP:    return "MAP";
        case OP_LOADV:  return "LOADV";
        case OP_LOADZ:  return "LOADZ";
        case OP_LOADD:  return "LOADD";
        case OP_RGBA:   return "RGBA";
        case OP_LINEW:  return "LINEW";
        case OP_FONT:   return "FONT";
        case OP_PUSHMAT:return "PUSHMAT";
        case OP_POPMAT: return "POPMAT";
        case OP_TRANS:  return "TRANS";
        case OP_SCALE:  return "SCALE";
        case OP_ROT:    return "ROT";
        case OP_CLEAR:  return "CLEAR";
        case OP_MOVETO: return "MOVETO";
        case OP_LINETO: return "LINETO";
        case OP_PATH:   return "PATH";
        case OP_CLOSE:  return "CLOSE";
        case OP_STROKE: return "STROKE";
        case OP_FILL:   return "FILL";
        case OP_RECT:   return "RECT";
        case OP_CIRCLE: return "CIRCLE";
        case OP_ARC:    return "ARC";
        case OP_TEXT:   return "TEXT";
        case OP_PANEL:  return "PANEL";
        case OP_ENDPAN: return "ENDPANEL";
        case OP_ANCHOR: return "ANCHOR";
        case OP_NOTE:   return "NOTE";
        case OP_EDGE:   return "EDGE";
        case OP_FLAG:   return "FLAG";
        case OP_CITE:   return "CITE";
        case OP_JMP:    return "JMP";
        case OP_JZ:     return "JZ";
        case OP_CALL:   return "CALL";
        case OP_RET:    return "RET";
        default:        return "???";
    }
}

// Operand widths in bytes, indexed by opcode. Hosts use this to skip unknown
// instructions safely instead of desynchronising the stream.
inline int operandBytes(uint8_t op) {
    switch (op) {
        case OP_PUSHF:  return 4;
        case OP_PUSHI:  return 4;
        case OP_PUSHS:  return 2;
        case OP_LOADV: case OP_LOADZ: case OP_LOADD: return 2;
        case OP_RGBA:   return 4;
        case OP_LINEW:  return 4;
        case OP_FONT:   return 6;
        case OP_TEXT:   return 3;
        case OP_PANEL:  return 4;
        case OP_ANCHOR: return 2;
        case OP_NOTE:   return 4;
        case OP_EDGE:   return 11;
        case OP_FLAG:   return 1;
        case OP_CITE:   return 2;
        case OP_JMP: case OP_JZ: return 2;
        case OP_CALL:   return 2;
        default:        return 0;
    }
}

enum Severity : uint8_t { SEV_OK = 0, SEV_BORDERLINE = 1, SEV_DEVIANT = 2, SEV_NODATA = 3 };
enum Anchor   : uint8_t { AN_LEFT = 0, AN_CENTRE = 1, AN_RIGHT = 2 };

// ---------------------------------------------------------------------------
// CRC-32/ISO-HDLC, so a host can tell a truncated file from a corrupt one.
// ---------------------------------------------------------------------------
inline uint32_t crc32(const uint8_t* p, size_t n) {
    static uint32_t table[256];
    static bool built = false;
    if (!built) {
        for (uint32_t i = 0; i < 256; ++i) {
            uint32_t c = i;
            for (int k = 0; k < 8; ++k) c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
        built = true;
    }
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; ++i) c = table[(c ^ p[i]) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

// ---------------------------------------------------------------------------
// Symbol table
// ---------------------------------------------------------------------------
struct Symbol {
    std::string name;
    std::string label;   // human-readable; hosts that show text prefer this
    double value = std::nan("");
    double z = 0.0;
    double dist = 0.0;
    double refLo = 0.0, refHi = 0.0;   // the reference band, so a host can
    bool hasRef = false;               // always name the line a value crossed
    uint8_t severity = SEV_NODATA;
    uint8_t domain = 0;
    bool valid = false;
};

// ---------------------------------------------------------------------------
// Emitter
// ---------------------------------------------------------------------------
class Emitter {
public:
    Emitter(uint32_t canvasW = 1600, uint32_t canvasH = 1000)
        : canvasW_(canvasW), canvasH_(canvasH) {}

    // -- pools ---------------------------------------------------------------
    uint16_t str(const std::string& s) {
        auto it = strIndex_.find(s);
        if (it != strIndex_.end()) return it->second;
        uint16_t id = (uint16_t)strings_.size();
        strings_.push_back(s);
        strIndex_[s] = id;
        return id;
    }

    uint16_t sym(const Symbol& s) {
        auto it = symIndex_.find(s.name);
        if (it != symIndex_.end()) {
            symbols_[it->second] = s;
            return it->second;
        }
        uint16_t id = (uint16_t)symbols_.size();
        symbols_.push_back(s);
        symIndex_[s.name] = id;
        return id;
    }

    uint16_t symId(const std::string& name) const {
        auto it = symIndex_.find(name);
        return it == symIndex_.end() ? (uint16_t)0xFFFF : it->second;
    }

    const std::vector<Symbol>& symbols() const { return symbols_; }
    const std::vector<std::string>& strings() const { return strings_; }

    void setMeta(const std::string& json) { meta_ = json; }
    void setCanvas(uint32_t w, uint32_t h) { canvasW_ = w; canvasH_ = h; }
    void setEntry(uint32_t pc) { entry_ = pc; }
    uint32_t here() const { return (uint32_t)code_.size(); }

    // -- raw emit ------------------------------------------------------------
    void op(uint8_t o) { code_.push_back(o); }
    void u8(uint8_t v) { code_.push_back(v); }
    void i8(int8_t v)  { code_.push_back((uint8_t)v); }
    void u16(uint16_t v) { code_.push_back(v & 0xFF); code_.push_back((v >> 8) & 0xFF); }
    void i16(int16_t v)  { u16((uint16_t)v); }
    void i32(int32_t v) {
        uint32_t u = (uint32_t)v;
        for (int k = 0; k < 4; ++k) code_.push_back((u >> (8 * k)) & 0xFF);
    }
    void f32(double d) {
        float f = (float)d;
        uint32_t u;
        std::memcpy(&u, &f, 4);
        for (int k = 0; k < 4; ++k) code_.push_back((u >> (8 * k)) & 0xFF);
    }

    // -- convenience ---------------------------------------------------------
    void pushf(double v) { op(OP_PUSHF); f32(v); }
    void pushi(int32_t v) { op(OP_PUSHI); i32(v); }
    void loadv(const std::string& n) { op(OP_LOADV); u16(symId(n)); }
    void loadz(const std::string& n) { op(OP_LOADZ); u16(symId(n)); }
    void loadd(const std::string& n) { op(OP_LOADD); u16(symId(n)); }

    void rgba(int r, int g, int b, int a = 255) {
        op(OP_RGBA); u8((uint8_t)r); u8((uint8_t)g); u8((uint8_t)b); u8((uint8_t)a);
    }
    void linew(double w) { op(OP_LINEW); f32(w); }
    void font(const std::string& name, double size) {
        op(OP_FONT); u16(str(name)); f32(size);
    }
    void rect(double x, double y, double w, double h) {
        pushf(x); pushf(y); pushf(w); pushf(h); op(OP_RECT);
    }
    void circle(double x, double y, double r) {
        pushf(x); pushf(y); pushf(r); op(OP_CIRCLE);
    }
    void line(double x0, double y0, double x1, double y1) {
        op(OP_PATH);
        pushf(x0); pushf(y0); op(OP_MOVETO);
        pushf(x1); pushf(y1); op(OP_LINETO);
        op(OP_STROKE);
    }
    void text(double x, double y, const std::string& s, uint8_t anchor = AN_LEFT) {
        pushf(x); pushf(y);
        op(OP_TEXT); u16(str(s)); u8(anchor);
    }
    void panel(const std::string& id, const std::string& title) {
        op(OP_PANEL); u16(str(id)); u16(str(title));
    }
    void endPanel() { op(OP_ENDPAN); }
    void anchor(const std::string& id) { op(OP_ANCHOR); u16(str(id)); }
    void note(const std::string& plain, const std::string& full) {
        op(OP_NOTE); u16(str(plain)); u16(str(full));
    }
    void edge(const std::string& a, const std::string& b, const std::string& hyp,
              double w, int sign) {
        op(OP_EDGE); u16(str(a)); u16(str(b)); u16(str(hyp)); f32(w); i8((int8_t)sign);
    }
    void flag(uint8_t sev) { op(OP_FLAG); u8(sev); }
    void cite(const std::string& s) { op(OP_CITE); u16(str(s)); }

    // Patchable forward call: emit CALL to a label fixed up later.
    size_t callPatch() { op(OP_CALL); size_t at = code_.size(); u16(0); return at; }
    void patchU16(size_t at, uint16_t v) {
        code_[at] = v & 0xFF;
        code_[at + 1] = (v >> 8) & 0xFF;
    }

    // -- serialise -----------------------------------------------------------
    std::vector<uint8_t> build() const {
        std::vector<uint8_t> strBlob;
        for (const auto& s : strings_) {
            uint16_t n = (uint16_t)s.size();
            strBlob.push_back(n & 0xFF);
            strBlob.push_back((n >> 8) & 0xFF);
            strBlob.insert(strBlob.end(), s.begin(), s.end());
        }

        std::vector<uint8_t> symBlob;
        for (const auto& s : symbols_) {
            uint16_t nameIdx = 0xFFFF, labelIdx = 0xFFFF;
            auto it = strIndex_.find(s.name);
            if (it != strIndex_.end()) nameIdx = it->second;
            auto lt = strIndex_.find(s.label);
            if (lt != strIndex_.end()) labelIdx = lt->second;
            uint16_t flags = (uint16_t)(s.severity & 0x3);
            if (s.valid) flags |= 0x4;
            flags |= (uint16_t)((s.domain & 0x7) << 3);
            if (s.hasRef) flags |= 0x40;
            putU16(symBlob, nameIdx);
            putU16(symBlob, labelIdx);
            putU16(symBlob, flags);
            putU16(symBlob, 0);
            putF32(symBlob, s.valid ? s.value : 0.0);
            putF32(symBlob, s.z);
            putF32(symBlob, s.dist);
            putF32(symBlob, s.refLo);
            putF32(symBlob, s.refHi);
        }

        const uint32_t hdr = 64;
        uint32_t strOff = hdr;
        uint32_t symOff = strOff + (uint32_t)strBlob.size();
        uint32_t codeOff = symOff + (uint32_t)symBlob.size();
        uint32_t metaOff = codeOff + (uint32_t)code_.size();

        std::vector<uint8_t> out;
        out.reserve(metaOff + meta_.size());
        out.insert(out.end(), {'N', 'V', 'M', '1'});
        putU16(out, 1);                                   // version
        putU16(out, meta_.empty() ? 0 : 1);               // flags
        putU32(out, strOff);
        putU32(out, (uint32_t)strings_.size());
        putU32(out, (uint32_t)strBlob.size());
        putU32(out, symOff);
        putU32(out, (uint32_t)symbols_.size());
        putU32(out, codeOff);
        putU32(out, (uint32_t)code_.size());
        putU32(out, metaOff);
        putU32(out, (uint32_t)meta_.size());
        putU32(out, crc32(code_.data(), code_.size()));
        putU32(out, entry_);
        putU32(out, canvasW_);
        putU32(out, canvasH_);
        putU32(out, 0);                                   // reserved
        out.insert(out.end(), strBlob.begin(), strBlob.end());
        out.insert(out.end(), symBlob.begin(), symBlob.end());
        out.insert(out.end(), code_.begin(), code_.end());
        out.insert(out.end(), meta_.begin(), meta_.end());
        return out;
    }

private:
    static void putU16(std::vector<uint8_t>& v, uint16_t x) {
        v.push_back(x & 0xFF); v.push_back((x >> 8) & 0xFF);
    }
    static void putU32(std::vector<uint8_t>& v, uint32_t x) {
        for (int k = 0; k < 4; ++k) v.push_back((x >> (8 * k)) & 0xFF);
    }
    static void putF32(std::vector<uint8_t>& v, double d) {
        float f = (float)d;
        uint32_t u;
        std::memcpy(&u, &f, 4);
        putU32(v, u);
    }

    std::vector<std::string> strings_;
    std::map<std::string, uint16_t> strIndex_;
    std::vector<Symbol> symbols_;
    std::map<std::string, uint16_t> symIndex_;
    std::vector<uint8_t> code_;
    std::string meta_;
    uint32_t entry_ = 0;
    uint32_t canvasW_, canvasH_;
};

}  // namespace nvm
