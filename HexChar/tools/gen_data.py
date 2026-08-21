#!/usr/bin/env python3
"""Generate HexChar/data.js from Python's Unicode character database.

Names, general categories and combining classes come straight from
unicodedata, so the keyboard never carries hand-typed (and eventually wrong)
metadata. Run this after editing the category spec below:

    python3 tools/gen_data.py
"""

import json
import os
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, os.pardir, "data.js"))


def r(first, last):
    """Inclusive code point range, as a string."""
    return "".join(chr(c) for c in range(first, last + 1))


def cp(*points):
    """Explicit code points, as a string. Used where typing the literal
    character would be ambiguous (combining marks) or unreadable."""
    return "".join(chr(c) for c in points)


# Friendly names for Unicode general categories, shown in the detail card.
GENERAL_CATEGORIES = {
    "Lu": "Uppercase letter", "Ll": "Lowercase letter", "Lt": "Titlecase letter",
    "Lm": "Modifier letter", "Lo": "Other letter",
    "Mn": "Nonspacing mark", "Mc": "Spacing mark", "Me": "Enclosing mark",
    "Nd": "Decimal number", "Nl": "Letter number", "No": "Other number",
    "Pc": "Connector punctuation", "Pd": "Dash punctuation", "Ps": "Open punctuation",
    "Pe": "Close punctuation", "Pi": "Initial quote", "Pf": "Final quote",
    "Po": "Other punctuation",
    "Sm": "Math symbol", "Sc": "Currency symbol", "Sk": "Modifier symbol",
    "So": "Other symbol",
    "Zs": "Space separator", "Zl": "Line separator", "Zp": "Paragraph separator",
    "Cf": "Format",
}

# Code points whose default presentation is a colour emoji (Emoji_Presentation=Yes
# in UTS #51), restricted to the ranges this keyboard uses. Their keys are drawn
# with a text variation selector so the honeycomb stays monochrome; the character
# that gets inserted is still the bare code point.
EMOJI_PRESENTATION = [
    (0x231A, 0x231B), (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3),
    (0x25FD, 0x25FE), (0x2614, 0x2615), (0x2648, 0x2653), (0x267F, 0x267F),
    (0x2693, 0x2693), (0x26A1, 0x26A1), (0x26AA, 0x26AB), (0x26BD, 0x26BE),
    (0x26C4, 0x26C5), (0x26CE, 0x26CE), (0x26D4, 0x26D4), (0x26EA, 0x26EA),
    (0x26F2, 0x26F3), (0x26F5, 0x26F5), (0x26FA, 0x26FA), (0x26FD, 0x26FD),
    (0x2705, 0x2705), (0x270A, 0x270B), (0x2728, 0x2728), (0x274C, 0x274C),
    (0x274E, 0x274E), (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797),
    (0x27B0, 0x27B0), (0x27BF, 0x27BF), (0x2B1B, 0x2B1C), (0x2B50, 0x2B50),
    (0x2B55, 0x2B55),
]


def is_emoji_presentation(ch):
    point = ord(ch)
    return any(lo <= point <= hi for lo, hi in EMOJI_PRESENTATION)


# Characters that draw nothing get a visible stand-in on their key.
DISPLAY = {
    0x00A0: "NB␣", 0x2002: "EN␣", 0x2003: "EM␣", 0x2007: "FIG␣",
    0x2009: "TH␣", 0x200A: "HR␣", 0x202F: "NNB␣", 0x205F: "MM␣",
    0x200B: "ZW␣", 0x200C: "ZWNJ", 0x200D: "ZWJ", 0x2060: "WJ",
}

GROUPS = [
    {
        "id": "ipa",
        "label": "IPA",
        "categories": [
            {
                "id": "vowels",
                "label": "Vowels",
                "icon": "ə",
                # IPA vowel chart, close to open, then rhotic vowels.
                "chars": "iyɨʉɯu" "ɪʏʊ" "eøɘɵɤo" "ə" "ɛœɜɞʌɔ"
                         "æɐ" "aɶɑɒ" "ɚɝ",
            },
            {
                "id": "pulmonic",
                "label": "Consonants",
                "icon": "ʈ",
                # Pulmonic consonant chart, by manner.
                "chars": "pbtdʈɖcɟkɡqɢʔ"
                         "mɱnɳɲŋɴ"
                         "ʙrʀⱱɾɽ"
                         "ɸβfvθðszʃʒʂʐçʝxɣχʁħʕhɦ"
                         "ɬɮ"
                         "ʋɹɻjɰ"
                         "lɭʎʟ",
            },
            {
                "id": "nonpulmonic",
                "label": "Clicks & more",
                "icon": "ǃ",
                # Clicks, implosives, ejective mark, and the "other symbols" row.
                "chars": "ʘǀǃǂǁ"
                         "ɓɗʄɠʛ" + cp(0x02BC) +
                         "ʍwɥʜʢʡɕʑɺɧ"
                         "ʣʤʥʦʧʨ"
                         "ɫɿʅʆʓ",
            },
            {
                "id": "diacritics",
                "label": "Diacritics",
                "icon": "̃",
                "chars": cp(
                    0x0325, 0x030A, 0x032C, 0x02B0, 0x0339, 0x031C, 0x031F, 0x0320,
                    0x0308, 0x033D, 0x0329, 0x032F, 0x02DE, 0x0324, 0x0330, 0x033C,
                    0x02B7, 0x02B2, 0x02E0, 0x02E4, 0x0334, 0x031D, 0x031E, 0x0318,
                    0x0319, 0x032A, 0x033A, 0x033B, 0x0303, 0x207F, 0x02E1, 0x031A,
                    0x0361, 0x035C, 0x0327, 0x0328, 0x0348, 0x0353, 0x0356,
                ),
            },
            {
                "id": "suprasegmentals",
                "label": "Tone & stress",
                "icon": "ˈ",
                "chars": cp(
                    0x02C8, 0x02CC, 0x02D0, 0x02D1, 0x0306, 0x007C, 0x2016, 0x002E,
                    0x203F, 0x2197, 0x2198,
                    0x02E5, 0x02E6, 0x02E7, 0x02E8, 0x02E9, 0xA71B, 0xA71C,
                    0x030B, 0x0301, 0x0304, 0x0300, 0x030F, 0x030C, 0x0302,
                    0x1DC4, 0x1DC5, 0x1DC8, 0x1DC6, 0x1DC7,
                ),
            },
            {
                "id": "modifiers",
                "label": "Modifier letters",
                "icon": "ʰ",
                "chars": r(0x02B0, 0x02FF),
            },
            {
                "id": "block",
                "label": "IPA Extensions",
                "icon": "ɐ",
                # The whole U+0250..U+02AF block, which is the view that
                # started this whole thing.
                "chars": r(0x0250, 0x02AF),
            },
        ],
    },
    {
        "id": "symbols",
        "label": "Symbols",
        "categories": [
            {
                "id": "arrows",
                "label": "Arrows",
                "icon": "→",
                "chars": r(0x2190, 0x21FF) + "⟵⟶⟷⟸⟹⟺⟼⤴⤵⤶⤷"
                         "⬅⬆⬇⬈⬉⬊⬋⬌⬍",
            },
            {
                "id": "math",
                "label": "Math",
                "icon": "∑",
                "chars": "+−±∓×÷⋅∗∘√∛∜"
                         "=≠≈≅≡≢≤≥≪≫∝∴∵"
                         "∞∂∇∫∬∭∮∑∏∐"
                         "∀∃∄∅∈∉∋⊂⊃⊆⊇⊄⊅"
                         "∪∩∖⊕⊖⊗⊘⊙⊞⊟⊠"
                         "∧∨¬⊤⊥⊢⊨⊩"
                         "∠∡∢∥∦⟂△⊿⌀"
                         "⌈⌉⌊⌋⟨⟩⟦⟧⟪⟫"
                         "ℵℶ℘ℑℜℂℝℕℚℤ",
            },
            {
                "id": "punctuation",
                "label": "Punctuation",
                "icon": "¶",
                "chars": "‐‑‒–—―⸺⸻"
                         "‘’‚‛“”„‟‹›«»"
                         "¡¿‽⁇⁈⁉⸮⸘‼"
                         "§¶†‡•‣∙…⋮⋯"
                         "‰‱′″‴‵‶⁗"
                         "‖⁄⁂⁋⁑⁝⁞⁕⁘"
                         "·¸ªº¨¯´˝ˇ˘˙"
                         + cp(0x00A0, 0x2002, 0x2003, 0x2007, 0x2009, 0x200A,
                              0x202F, 0x205F, 0x200B, 0x200C, 0x200D, 0x2060),
            },
            {
                "id": "currency",
                "label": "Currency",
                "icon": "€",
                "chars": "$¢£¤¥" + r(0x20A0, 0x20BF),
            },
            {
                "id": "technical",
                "label": "Keys & UI",
                "icon": "⌘",
                "chars": "⌘⌥⇧⌃⇪↵⏎⌫⌦⇥⇆⇱⇲"
                         "⎋⎀⎄⎇⎌⎈⏏"
                         "⇞⇟↖↗↘↙"
                         "⏰⏱⏲⌚⌛⏳⌨"
                         "⏻⏼⏽⏾⭘⏯⏮⏭⏪⏩⏸⏹⏺⏫⏬"
                         "␣␠␀␊␍␉␛␡"
                         "⌂⌗⌑⌒⌓⌕⌖⌜⌝⌞⌟⌤⌦"
                         "⎗⎘⎙⎚⌸⌹⌺⌻⌼",
            },
            {
                "id": "geometric",
                "label": "Shapes",
                "icon": "◆",
                "chars": r(0x25A0, 0x25FF) + "⬛⬜⬟⬠⬡⬢⬣"
                         "⬤⬥⬦⬧⬨⬩⭐⭑⭒",
            },
            {
                "id": "stars",
                "label": "Stars",
                "icon": "★",
                "chars": "★☆⭐⭑⭒✪✩✫✬✭✮✯✰"
                         "✦✧✤✥✡✢✣"
                         "✱✲✳✴✵✶✷✸✹"
                         "✺✻✼✽✾✿❀❁❂❃"
                         "❄❅❆❇❈❉❊❋"
                         "⁂⁑٭∗*",
            },
            {
                "id": "signs",
                "label": "Signs",
                "icon": "♻",
                "chars": "♻♼♽♲♳♴♵♶♷♸♹♺"
                         "⚠☢☣☠♿⛔⚡⚛"
                         "⚕⚖⚜⚗⚘⚙⚚"
                         "☎☏✆✇✉✈"
                         "☐☑☒✓✔✗✘✖"
                         "⛒⛓⛽♨⚓⚔⚑⚐"
                         "☝☞☟☜✌",
            },
            {
                "id": "music",
                "label": "Music",
                "icon": "♫",
                "chars": "♩♪♫♬♭♮♯" + cp(
                    0x1D11E, 0x1D121, 0x1D122, 0x1D12A, 0x1D12B,
                    0x1D13B, 0x1D13C, 0x1D13D, 0x1D13E, 0x1D13F,
                    0x1D15C, 0x1D15D, 0x1D15E, 0x1D15F, 0x1D160,
                    0x1D110, 0x1D10B, 0x1D10C, 0x1D106, 0x1D107,
                ),
            },
            {
                "id": "greek",
                "label": "Greek",
                "icon": "λ",
                "chars": r(0x0391, 0x03A1) + r(0x03A3, 0x03A9)
                         + r(0x03B1, 0x03C9) + "ϑϕϖϱϵϝϛ",
            },
            {
                "id": "letterlike",
                "label": "Letterlike",
                "icon": "№",
                "chars": "№™©®℠℗℃℉Ω℧℮ℹ℅℆"
                         "°µ¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞"
                         "⁰¹²³" + r(0x2074, 0x207E)
                         + r(0x2080, 0x208E)
                         + r(0x2460, 0x2473) + r(0x24B6, 0x24BF),
            },
            {
                "id": "games",
                "label": "Games",
                "icon": "♠",
                "chars": "♠♡♢♣♤♥♦♧"
                         "♔♕♖♗♘♙♚♛♜♝♞♟"
                         "⚀⚁⚂⚃⚄⚅⚆⚇⚈⚉"
                         "⛀⛁⛂⛃☯☮☸",
            },
            {
                "id": "sky",
                "label": "Sky",
                "icon": "☀",
                "chars": "☀☁☂☃☄⛄⛅⛆⛇⛈☔❄"
                         "☼☽☾◐◑◒◓○●◔◕"
                         "☉☿♀♁♂♃♄♅♆♇⛢"
                         "♈♉♊♋♌♍♎♏♐♑♒♓",
            },
            {
                "id": "boxes",
                "label": "Boxes",
                "icon": "█",
                "chars": r(0x2500, 0x257F) + r(0x2580, 0x259F),
            },
            {
                "id": "dingbats",
                "label": "Dingbats",
                "icon": "✎",
                "chars": "✁✂✃✄✆✇✈✉✌✍"
                         "✎✏✐✑✒✓✔✕✖✗✘"
                         "✙✚✛✜✝✞✟✠"
                         "❏❐❑❒❖❘❙❚"
                         "❛❜❝❞❡❢❣❤❥❦❧"
                         "➔➘➙➚➛➜➝➞➟➠"
                         "➡➢➣➤➥➦➧➨➩➪"
                         "➫➬➭➮➯➱➲➳➴➵",
            },
        ],
    },
]


def build():
    seen_ids = set()
    groups = []
    total = 0
    skipped = []
    for gspec in GROUPS:
        cats = []
        for cspec in gspec["categories"]:
            cid = gspec["id"] + "." + cspec["id"]
            if cid in seen_ids:
                raise SystemExit("duplicate category id: " + cid)
            seen_ids.add(cid)
            chars = []
            local = set()
            for ch in cspec["chars"]:
                if ch == " " or ch in local:
                    continue
                gc = unicodedata.category(ch)
                name = unicodedata.name(ch, "")
                if gc in ("Cn", "Cs", "Co") or not name:
                    # Unassigned in this Python's UCD, or nameless: shipping it
                    # would just put a tofu box on a key.
                    skipped.append("%s U+%04X" % (cid, ord(ch)))
                    continue
                local.add(ch)
                entry = {"c": ch, "n": name.title()}
                if gc in GENERAL_CATEGORIES:
                    entry["g"] = GENERAL_CATEGORIES[gc]
                if unicodedata.combining(ch):
                    entry["m"] = 1  # combining mark: draw it on a dotted circle
                if is_emoji_presentation(ch):
                    entry["e"] = 1  # draw with U+FE0E, insert without it
                if ord(ch) in DISPLAY:
                    entry["d"] = DISPLAY[ord(ch)]  # invisible: draw a stand-in
                chars.append(entry)
            total += len(chars)
            cats.append({
                "id": cid,
                "label": cspec["label"],
                "icon": cspec["icon"],
                "chars": chars,
            })
        groups.append({"id": gspec["id"], "label": gspec["label"], "categories": cats})
    return groups, total, skipped


def main():
    groups, total, skipped = build()
    payload = {"unicodeVersion": unicodedata.unidata_version, "groups": groups}
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("// Generated by tools/gen_data.py -- do not edit by hand.\n")
        f.write("// Names and categories come from the Unicode Character Database"
                " (via Python's unicodedata).\n")
        f.write("window.HEXCHAR_DATA = " + body + ";\n")
    ncats = sum(len(g["categories"]) for g in groups)
    print("wrote %s: %d characters in %d categories" % (OUT, total, ncats))
    if skipped:
        print("skipped %d unnamed/unassigned code points: %s"
              % (len(skipped), ", ".join(skipped[:12]) + (" ..." if len(skipped) > 12 else "")))


if __name__ == "__main__":
    sys.exit(main())
