// json.hpp — a small, dependency-free JSON reader.
//
// Scope is deliberately narrow: enough to load the session and prior-graph files
// in neuro/data/ and nothing more. No writer, no streaming, no comments. Values
// are held in a tagged struct; numbers are always double; `null` is its own tag
// so that "measured and equal to zero" stays distinguishable from "not measured"
// (neuro/data has both, e.g. eeg.paf_eo is null because it was Indiscernible).
#pragma once

#include <cstdint>
#include <cstdlib>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace nj {

struct Value;
using Object = std::map<std::string, Value>;
using Array = std::vector<Value>;

struct Value {
    enum class Tag { Null, Bool, Number, String, Array, Object } tag = Tag::Null;

    bool boolean = false;
    double number = 0.0;
    std::string text;
    std::shared_ptr<Array> array;
    std::shared_ptr<Object> object;

    bool isNull() const { return tag == Tag::Null; }
    bool isNumber() const { return tag == Tag::Number; }
    bool isString() const { return tag == Tag::String; }
    bool isArray() const { return tag == Tag::Array; }
    bool isObject() const { return tag == Tag::Object; }

    // Member lookup on a non-object, or a missing key, yields a Null value rather
    // than throwing. Callers check with isNull(); the data files are hand-written
    // and optional keys are common.
    const Value& operator[](const std::string& key) const {
        static const Value kNull;
        if (tag != Tag::Object || !object) return kNull;
        auto it = object->find(key);
        return it == object->end() ? kNull : it->second;
    }

    const Value& operator[](size_t i) const {
        static const Value kNull;
        if (tag != Tag::Array || !array || i >= array->size()) return kNull;
        return (*array)[i];
    }

    size_t size() const {
        if (tag == Tag::Array && array) return array->size();
        if (tag == Tag::Object && object) return object->size();
        return 0;
    }

    double num(double fallback = 0.0) const { return isNumber() ? number : fallback; }
    std::string str(const std::string& fallback = "") const { return isString() ? text : fallback; }
};

class Parser {
public:
    explicit Parser(const std::string& src) : s_(src) {}

    Value parse() {
        skipSpace();
        Value v = parseValue();
        skipSpace();
        if (i_ != s_.size()) fail("trailing content after top-level value");
        return v;
    }

private:
    const std::string& s_;
    size_t i_ = 0;

    [[noreturn]] void fail(const std::string& why) const {
        throw std::runtime_error("json: " + why + " at byte " + std::to_string(i_));
    }

    char peek() const { return i_ < s_.size() ? s_[i_] : '\0'; }

    void skipSpace() {
        while (i_ < s_.size()) {
            char c = s_[i_];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { ++i_; continue; }
            break;
        }
    }

    void expect(char c) {
        if (peek() != c) fail(std::string("expected '") + c + "'");
        ++i_;
    }

    Value parseValue() {
        switch (peek()) {
            case '{': return parseObject();
            case '[': return parseArray();
            case '"': { Value v; v.tag = Value::Tag::String; v.text = parseString(); return v; }
            case 't': return parseLiteral("true", true);
            case 'f': return parseLiteral("false", false);
            case 'n': { expectWord("null"); return Value{}; }
            default:  return parseNumber();
        }
    }

    void expectWord(const char* w) {
        for (const char* p = w; *p; ++p) {
            if (peek() != *p) fail(std::string("expected literal ") + w);
            ++i_;
        }
    }

    Value parseLiteral(const char* w, bool b) {
        expectWord(w);
        Value v;
        v.tag = Value::Tag::Bool;
        v.boolean = b;
        return v;
    }

    Value parseNumber() {
        size_t start = i_;
        if (peek() == '-' || peek() == '+') ++i_;
        while (i_ < s_.size() && (isdigit((unsigned char)s_[i_]) || s_[i_] == '.' ||
                                  s_[i_] == 'e' || s_[i_] == 'E' || s_[i_] == '-' || s_[i_] == '+')) {
            ++i_;
        }
        if (start == i_) fail("expected a value");
        Value v;
        v.tag = Value::Tag::Number;
        v.number = strtod(s_.substr(start, i_ - start).c_str(), nullptr);
        return v;
    }

    std::string parseString() {
        expect('"');
        std::string out;
        while (true) {
            if (i_ >= s_.size()) fail("unterminated string");
            char c = s_[i_++];
            if (c == '"') break;
            if (c != '\\') { out += c; continue; }
            if (i_ >= s_.size()) fail("unterminated escape");
            char e = s_[i_++];
            switch (e) {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'b':  out += '\b'; break;
                case 'f':  out += '\f'; break;
                case 'n':  out += '\n'; break;
                case 'r':  out += '\r'; break;
                case 't':  out += '\t'; break;
                case 'u': {
                    // Only the BMP subset the data files actually use; encode as UTF-8.
                    if (i_ + 4 > s_.size()) fail("short \\u escape");
                    unsigned cp = (unsigned)strtoul(s_.substr(i_, 4).c_str(), nullptr, 16);
                    i_ += 4;
                    if (cp < 0x80) {
                        out += (char)cp;
                    } else if (cp < 0x800) {
                        out += (char)(0xC0 | (cp >> 6));
                        out += (char)(0x80 | (cp & 0x3F));
                    } else {
                        out += (char)(0xE0 | (cp >> 12));
                        out += (char)(0x80 | ((cp >> 6) & 0x3F));
                        out += (char)(0x80 | (cp & 0x3F));
                    }
                    break;
                }
                default: fail("unknown escape");
            }
        }
        return out;
    }

    Value parseArray() {
        expect('[');
        Value v;
        v.tag = Value::Tag::Array;
        v.array = std::make_shared<Array>();
        skipSpace();
        if (peek() == ']') { ++i_; return v; }
        while (true) {
            skipSpace();
            v.array->push_back(parseValue());
            skipSpace();
            if (peek() == ',') { ++i_; continue; }
            expect(']');
            break;
        }
        return v;
    }

    Value parseObject() {
        expect('{');
        Value v;
        v.tag = Value::Tag::Object;
        v.object = std::make_shared<Object>();
        skipSpace();
        if (peek() == '}') { ++i_; return v; }
        while (true) {
            skipSpace();
            std::string key = parseString();
            skipSpace();
            expect(':');
            skipSpace();
            (*v.object)[key] = parseValue();
            skipSpace();
            if (peek() == ',') { ++i_; continue; }
            expect('}');
            break;
        }
        return v;
    }
};

Value parse(const std::string& src) { return Parser(src).parse(); }

}  // namespace nj
