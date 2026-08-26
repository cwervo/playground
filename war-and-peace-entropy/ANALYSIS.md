# War and Peace: the entropy floor, and a lossy salience ladder below it

**Source text.** Project Gutenberg EBook #2600, *War and Peace*, Louise & Aylmer
Maude translation (fetched this session, PG boilerplate stripped, body only).
Measured directly:

| quantity | value |
|---|---|
| file bytes (novel body, header/footer stripped) | 3,207,505 |
| file bytes (full PG file incl. license boilerplate) | 3,226,652 |
| characters (== bytes; source is pure ASCII) | 3,207,505 |
| words (regex `[A-Za-z']+`) | 566,703 |
| words (whitespace-split, `wc -w`) | 563,309 |
| distinct byte values used | 78 |

This matches the task's "~3.3MB / ~587K words" to within normal
word-counting-convention variance (hyphens, numbers, contractions all get
tokenized differently by different counters — a ±4% spread on word count for
the same fixed byte stream is normal and not worth chasing further).

Everything below — compressor outputs, entropy tables, byte counts — was
computed on this actual file this session, not asserted from memory. Where I
cite external benchmarks (Shannon 1951, the Hutter Prize), I ran a live search
to pull current figures rather than rely on stale recall, and I redid the
arithmetic myself rather than trust a summary's conversion.

---

## 1. The lossless entropy floor

### 1.1 What "entropy floor" even means

There is no such thing as *the* entropy of a text in isolation. Shannon
entropy is a property of a *model* of the source, and Kolmogorov complexity
K(x) is defined relative to a *fixed universal decoder* U — K(x) is the length
of the shortest program that makes U output x. Change U (give it more
built-in knowledge) and K(x) drops, sometimes to nothing. So "the smallest
lossless size" is really "the smallest size, given how much we agree the
decoder is allowed to already know before the message arrives." Fixing that
is not a formality; it's the whole question. I'll fix it at the point that
makes the question interesting: **the decoder knows English (general
statistics of the language, not this specific book) and nothing else.** That
excludes the degenerate case in §1.5, which I discuss separately because it's
real and worth naming, not because it's cheating in some vague sense — it's
disqualified for a precise reason.

### 1.2 Real compressors, run on the actual file

| compressor | output bytes | bits/char | ratio vs. raw |
|---|---:|---:|---:|
| gzip -9 | 1,187,241 | 2.961 | 37.0% |
| xz -9e (LZMA2) | 917,072 | 2.287 | 28.6% |
| bzip2 -9 | **877,512** | **2.189** | 27.4% |

bzip2 (BWT + MTF + Huffman) beats LZMA here, which is a little counter to the
usual "LZMA wins on text" intuition — LZMA's advantage is long-range literal
match-copying, which pays off on structured/templated data more than on
continuous single-author prose, whereas BWT block-sorting is very good at
clustering a novel's recurring character names, epithets, and syntactic
habits even within its 900KB block size. **877,512 bytes is the honest,
measured, off-the-shelf floor** — no cheating, reproducible with tools on any
machine.

### 1.3 Showing the reasoning: empirical order-N entropy on the real text

Order-0 (character-frequency-only) entropy, no context at all:

```
H(char) = 4.4727 bits/char   →  1,793,276 bytes if achievable
```

That number alone already tells you gzip (2.96 bits/char) is leaving
something on the table relative to even a *context-free* model — because
gzip's Huffman stage operates over LZ77 tokens, not raw literal frequencies,
and pays overhead elsewhere.

Conditional entropy H(next char | previous k chars), computed directly from
the file by counting (k+1)-grams and subtracting block entropies:

| context length k | H(char \| k preceding chars), bits | 
|---:|---:|
| 0 | 4.473 |
| 1 | 3.529 |
| 2 | 2.793 |
| 3 | 2.169 |
| 4 | 1.770 |
| 5 | 1.500 |
| 6 | 1.261 |
| 7 | 1.033 |

This is the classic Shannon-style curve: entropy keeps falling as context
grows, because English is a low-order Markov process only approximately —
most of its real predictability lives in longer-range syntax, semantics, and
this book's specific repeated names and phrases. **But this table is a trap
past about k=6**, and I want to be explicit about why rather than just quote
a falling number: at k=7 already 23% of all 7-grams in the file occur exactly
once, and at k=12 it's 75%. A context that occurs once "predicts" the next
character with 0 bits of apparent entropy *by construction* — that's not
genuine predictive power, it's the model memorizing the file against itself
with no held-out data and no escape mechanism for contexts it hasn't seen. A
real adaptive compressor (PPM, context-mixing) has to pay for that escape
probability, so it never gets this low in practice from naive counting alone.
This table is diagnostic, not directly achievable — which is exactly why I
didn't stop at "just count higher-order n-grams and report 0.3 bits/char,"
which would be a real error, not a rounding one.

### 1.4 Where the honest floor actually sits: three independent lines of evidence converge

1. **Shannon (1951), "Prediction and Entropy of Printed English"** — human
   subjects playing a next-letter guessing game against real English text,
   which captures full semantic/world-knowledge prediction a mechanical
   n-gram counter can't: **0.6–1.3 bits/letter**. (He also reports ~2.3
   bits/letter for statistical, i.e. non-human, models using up to 8 letters
   of context — consistent with my own measured 2.17–1.03 bits/char over
   contexts of 3–7 characters above.)
   [Shannon 1951 PDF](https://www.princeton.edu/~wbialek/rome/refs/shannon_51.pdf)

2. **Hutter Prize / enwik9** — the live, adversarially-contested benchmark for
   "best known lossless compression of a large English text corpus." The
   September 2024 record (Kaido Orav & Byron Knoll, `fx2-cmix`) compresses the
   1,000,000,000-byte enwik9 corpus to **110,793,128 bytes**, i.e.
   `110,793,128 × 8 / 1,000,000,000 = 0.886 bits/char`. (A web-search summary
   I pulled miscalculated this as "8.87 bits/char" — off by exactly 10× — so
   I redid the division myself from the raw byte counts rather than trust
   it.) [Hutter Prize](https://en.wikipedia.org/wiki/Hutter_Prize), [fx2-cmix](https://github.com/kaitz/fx2-cmix)

3. **My own extrapolated order-7/8 conditional entropy**, discounted for the
   overfitting bias flagged above, lands in the same neighborhood: roughly
   1.0–1.3 bits/char once you mentally add back a plausible escape-code
   penalty.

Applying the enwik9 rate (0.886 bits/char) directly to War and Peace's
3,207,505 characters gives **355,370 bytes**. Applying Shannon's 0.6–1.3
bits/letter range gives **240,563–521,220 bytes**. These aren't the same
corpus — enwik9 is Wikipedia markup, with templated citation/infobox
redundancy that's arguably *easier* to exploit than free-running narrative
prose, while War and Peace has its own compensating redundancy (a single
author's habits, recurring character names and epithets, Tolstoy's genuinely
repetitive rhetorical style in the historical-philosophy chapters, French
passages that recur near-verbatim). Given that, and given that all three
independent lines of evidence — a 1951 human-experiment number, a 2024
state-of-the-art context-mixing compressor number, and this file's own
measured statistics — land in the same neighborhood without having been
tuned to agree, I'll give a real answer rather than hide behind a range:

> **Best known lossless floor for this text: ≈0.9–1.3 bits/char ≈ 360,000–520,000 bytes** (call it **~430KB**, roughly an 7.5:1 ratio against the 3.2MB raw file), achievable in principle by a state-of-the-art context-mixing/neural compressor, not by anything I ran locally. The best number I actually produced myself, with tools anyone can run, is **877,512 bytes (bzip2 -9)**.

### 1.5 The floor beneath the floor: the "cheat" that isn't compression at all

This exact text is a specific, famous, freely-republished public-domain
document: Project Gutenberg EBook #2600. If sender and receiver *both already
agree in advance* that "#2600" refers to this exact edition, the "lossless"
transmission cost of the entire 3.2MB collapses to the cost of naming which
book it is — the ASCII string `PG2600` is **6 bytes**; a bare integer index
into Gutenberg's catalog of ~75,000 books needs `⌈log2(75000)⌉ = 17 bits`,
under **3 bytes**.

This is not compression in the Shannon/Kolmogorov sense used above — it's
addressing. The information wasn't squeezed out of the message; it was
already sitting in a library both parties had a key to, and the "message" is
now just the key. I flag it here, sharply separated from §1.4, because it's
the exact mechanism that makes the rest of this document possible: once a
receiver is allowed to already possess a copy of (or a good model of) the
object referred to, "reconstruction" stops being bounded by the entropy of
English prose and starts being bounded by the entropy of *which object, among
everything the receiver might already have*. That's precisely the move
Part 2 makes on purpose, honestly, at every rung.

---

## 2. A lossy salience ladder, written for real

Design choices, stated up front so the "what's destroyed" columns below are
honest about what was already decided rather than discovered:

- **Whose salience:** a literarily-informed general reader who has heard of
  the book but not necessarily read it — not a Tolstoy scholar (who'd want
  the free-indirect-discourse technique and the historiography debate
  preserved), not a plot-quiz taker (who'd want character-relationship
  detail), not a cataloguer (who'd just want title+author+ISBN).
- **Reconstruction task:** "could this artifact let someone correctly say
  what the book is fundamentally about," not "could someone reconstruct the
  prose, the plot beats, or pass a comprehension quiz from it."
- **Script:** Chinese (Han script), because a UTF-8 Hàn character is a fixed
  3 bytes and typically carries a full morpheme/word of content — denser
  *semantic* payload per byte than Latin script, which needs ~4–6 bytes per
  English word. All character/place names below use the standard forms from
  published Chinese translations of *War and Peace* (战争与和平).

All byte counts below are measured (`len(text.encode('utf-8'))`), not
estimated, on the exact strings printed.

### Rung 1 — target ~1KB, actual **1,035 bytes** (367 characters)

```
托尔斯泰长篇小说《战争与和平》,以1805至1812年俄法战争为背景,交织数百人物命运。别祖霍夫伯爵私生子皮埃尔骤得巨产,加入共济会寻求人生意义,婚姻失败,决斗几死,后于莫斯科沦陷时被法军俘虏,于战俘营中历经生死,终悟朴素劳作与家庭之幸福胜过一切玄想。博尔孔斯基公爵之子安德烈渴望荣耀,奥斯特利茨战场负伤仰望长空,顿悟功名虚妄;后倾心娜塔莎,婚约却因她被纨绔子弟阿纳托利诱惑而破,终于博罗季诺重伤,战后死去。罗斯托夫家女儿娜塔莎天真烂漫,历经悔恨与战乱磨砺,战后与皮埃尔结为夫妇。拿破仑大举侵俄,库图佐夫坚忍避战、诱敌深入,俄军于博罗季诺血战后弃守莫斯科,城陷而焚,法军终因严寒饥馑溃败撤退,俄罗斯获胜。书中另申史论:历史非英雄所造,乃众意汇成之潮流,非统帅所能主宰。尾声写战后数年家庭生活之平凡幸福,并沉思自由意志与历史必然之关系。
```

*(Gloss: Tolstoy's novel, set against the 1805–1812 Russo-French wars.
Pierre Bezukhov's illegitimate inheritance, Freemasonry, failed marriage,
duel, capture during the fall of Moscow, and eventual realization that plain
work and family matter more than any abstraction; Prince Andrei Bolkonsky's
disillusionment at Austerlitz, broken engagement to Natasha, death of wounds
after Borodino; Natasha Rostova's growth through disgrace and wartime
hardship to eventual marriage to Pierre; Napoleon's invasion, Kutuzov's
patient strategy, Borodino, the burning of Moscow, French retreat and defeat;
Tolstoy's historiographical thesis that history is made by the convergence of
countless individual wills, not by great men; the epilogue's meditation on
ordinary domestic happiness and free will vs. historical necessity.)*

**Preserves:** every major character's arc and fate, the historical
skeleton (invasion → Borodino → Moscow burns → French collapse), and — the
one thing a plot summary usually drops — Tolstoy's actual thesis (anti-great-man
historiography), because that thesis is arguably *the* thing the book is
"about" at the altitude this reader operates at.
**Destroys:** all 587K words of actual prose, every scene, all secondary
characters (Sonya, Marya Bolkonskaya, the elder Bolkonsky, Dolokhov,
Denisov, Platon Karataev — Karataev's absence alone is a real loss, since
he's the vehicle for Pierre's realization, not just a bystander to it), the
entire structure of alternating fiction/essay, and every stylistic feature.

### Rung 2 — target ~150B, actual **162 bytes** (58 characters)

```
拿破仑侵俄,库图佐夫坚忍制胜;皮埃尔历劫悟平凡之福,安德烈战死沙场,娜塔莎终嫁之;托翁谓历史非英雄所造,乃众志所汇。
```

*(Gloss: Napoleon invades Russia; Kutuzov's patient endurance wins.
Pierre, through ordeal, learns the blessing of the ordinary; Andrei dies in
battle; Natasha eventually marries him. Tolstoy: history is not made by
heroes, but by the convergence of countless wills.)*

**Preserves:** the causal skeleton (war → outcome), the two male leads'
opposite arcs (Andrei dies seeking glory, Pierre lives having renounced it),
Natasha's resolution, and the historiographical thesis — still intact,
because I judged it non-negotiable for *this* audience/task at every rung
down to here.
**Destroys:** everything about *how* — no Austerlitz, no Moscow, no
Freemasonry, no named antagonists, no sense of scale or duration. A reader
gets the shape of the story, not the story.

### Rung 3 — target ~30B, actual **31 bytes** (11 characters)

```
法侵俄终败,俄魂不灭。
```

*(Gloss: France invades Russia, is ultimately defeated; the Russian spirit
endures.)*

**Preserves:** only the historical macro-plot (invasion, defeat, national
survival) — no named characters at all now.
**Destroys:** Pierre, Andrei, Natasha, and the historiographical thesis, all
of it — there isn't room. Note the byte-budget forced dropping "拿破仑"
(Napoleon, 3 characters) for "法" (France, 1 character), which
*accidentally* re-enacts Tolstoy's own anti-great-man argument by erasing the
individual in favor of the nation-state as actor. That's a coincidence of
compression pressure, not a deliberate homage, and I want to be honest that
it's cute rather than meaningful — a different 11-character budget spent on
naming Pierre instead of the war would have been an equally defensible
choice for a different task ("who is this book's protagonist" instead of
"what happens").

### Rung 4 — target ~10B, actual **9 bytes** (3 characters)

```
战和命
```

*(Gloss: War · Peace · Fate — literally "war," "peace/harmony," and
"destiny/mandate/life," juxtaposed with no connective.)*

**Preserves:** a thematic triad — the title's two terms plus the concept
(命, fate/necessity) that Tolstoy's historical-determinism argument turns on.
This is no longer plot at all; it's a claim about what domain of ideas the
book belongs to.
**Destroys:** every character, every event, the fact that it's a novel
rather than, say, a philosophical treatise or a proverb. A reader with zero
other context could not distinguish this from a tag for a different book
entirely about war, peace, and fate in the abstract.

### Rung 5 — 1 glyph, actual **3 bytes**

```
和
```

*(hé — "peace" / "harmony"; also the second half of the book's own Chinese
title, 战争与和平.)*

**Preserves:** almost nothing propositional — at most, a valence: this
object resolves toward peace/harmony rather than war, which is true of the
actual ending (the epilogue's domestic happiness) and is one legitimate
one-symbol summary of "what side the book comes down on."
**Destroys:** literally everything else, including the fact that the book's
own title asserts a *duality*, not a resolution — "War and Peace," not just
"Peace." I seriously considered ☯ (U+262F, also 3 bytes) instead, which
preserves the duality/dynamic-balance structure of the title rather than
picking a winner, and is arguably the more faithful single glyph for *this
book specifically*, since Tolstoy's thesis is that war and peace are phases
of one continuous historical process, not opposites. I committed to 和
instead because it's an actual word in the actual title in an actual
language, rather than a symbol whose "duality" reading depends on importing
Taoist cosmology that has nothing to do with Tolstoy — which is itself the
point made formal in §3.5 below: even the choice between these two 3-byte
glyphs is a value judgment about whose interpretive frame gets to count as
the shared decoder.

### Measured summary

| rung | target | actual bytes | chars | invertible? |
|---|---:|---:|---:|:---:|
| lossless floor (§1.4, best-known) | — | ~360,000–520,000 | — | yes |
| lossless floor (§1.4, measured, bzip2) | — | 877,512 | — | yes |
| 1 | ~1KB | 1,035 | 367 | no |
| 2 | ~150B | 162 | 58 | no |
| 3 | ~30B | 31 | 11 | no |
| 4 | ~10B | 9 | 3 | no |
| 5 | 1 glyph | 3 | 1 | no |

---

## 3. Where compression ends and summarization begins

### 3.1 The line is categorical, not a point on the byte axis

Compression (§1) is an invertible map, relative to a disclosed decoder:
artifact + decoder → the exact original bitstring. Every rung in §2 is
non-invertible by construction — there is no decoder, however large, that
recovers Tolstoy's actual sentences from `战和命`, because that map was never
injective. This means the boundary between "compression" and "summarization"
isn't crossed partway down the ladder in §2 — **it's already fully crossed at
Rung 1, at 1,035 bytes**, which is 3,100× smaller than the raw text but
still, categorically, the same kind of operation as Rung 5: a lossy,
purpose-relative projection, not a more-aggressive compressor. The entire
ladder in §2 is summarization. Only §1 was ever compression. The task's own
framing ("below that floor, construct a lossy ladder") already contains this
answer; I want to state it precisely rather than let "lossy" quietly stand in
for "still basically compression, just cranked up," which it isn't.

### 3.2 Rate–distortion makes the missing piece explicit

Shannon's rate–distortion theory (1959) is the honest formal home for "how
small can it be while still being useful": for a fixed distortion measure
*D* and tolerance ε, there's a well-defined minimum rate R(D=ε). The theory
works. The problem is entirely upstream of it: **nobody has specified D.**
"Salience" is an informal name for "whatever D turns out to be," and D is not
a property of the text — it's a joint property of (a) an audience and (b) a
reconstruction task, and different choices of either give you a *different
R(D) curve entirely*, not just a different point on the same curve.

Concretely, at my own 9-byte budget (Rung 4), I chose D such that "preserves
the thesis that history is impersonal" counts as low-distortion and "names no
character" counts as acceptable. A children's-edition abridger targeting "can
a 10-year-old say what happens" would choose a D under which `战和命` is
*high* distortion (no characters, no events) and something naming Pierre and
Natasha is low distortion — for the *same* 9-byte budget. A library cataloguer
targeting "can this be told apart from other books" would want yet another D,
probably weighted toward title/author uniqueness over thematic content
entirely. None of these is wrong. There is no D-independent answer to
"smallest while maintaining salience" because the phrase doesn't name a
quantity until D is fixed, and fixing D is 90% of the actual work — the
compression part, once D is fixed, is comparatively mechanical.

### 3.3 The two halves of this document are the same move, at different scales

Section 1.5 showed that a fixed shared decoder (a library both parties can
already query) makes "lossless" reconstruction of 3.2MB cost 6 bytes, because
all the information moved into the (undisclosed, pre-shared) decoder. Every
rung in Section 2 does exactly the same thing, just with a vastly larger and
far less formal decoder: a human mind that already contains a language
(Chinese), a cultural stock of associations (what 和 connotes, what a
war/peace framing implies), and — at Rung 1 — enough general literacy to
unpack "共济会" (Freemasonry) or "奥斯特利茨" (Austerlitz) into their full
historical resonance. The single glyph 和 "reconstructs" almost nothing on
its own; it reconstructs a great deal in a mind that already halfway knows
the book, or at least knows the cultural weight of the pairing "war and
peace." That's not a flaw in the exercise — it's the actual mechanism by
which any of this works at all, and it's the same mechanism, run at a much
larger and much less accountable scale, that state-of-the-art neural
compressors in Section 1.4 exploit: a large pretrained language model
compresses English text well precisely because most of the "decoder" (a
model of the world, of syntax, of common phrasing) was paid for once, in
advance, out-of-band, and never counted against the message. Push that same
logic to its limit — a decoder that has this specific novel memorized, which
is not a hypothetical for any large modern LLM — and even the "lossless"
floor of Section 1 collapses toward the pointer floor of Section 1.5. The honest
conclusion is that "entropy floor" and "salience-preserving minimum" are not
two different kinds of question answered by two different parts of this
document; they're the same question — *how much can the message omit given
what the receiver is assumed to already carry* — asked once about a generic
model of English, and once about a specific human being with a specific
purpose, and the second version has no unique answer because unlike "a model
of English," "a specific human being with a specific purpose" isn't a thing
you get to leave unspecified and still expect a number back.
