# minibrowser

A mini web browser. The page engine is **one portable C file** in the
spirit of [redbean](https://redbean.dev) (single translation unit, no
dependencies, builds with `cc`, `clang`, MinGW or `cosmocc` into an
Actually Portable Executable). **Flutter** provides the chrome (URL bar,
back/forward/reload, history, forms) and paints the display list the C
engine hands it over `dart:ffi`. A GNU `make` file assembles all of it on
Linux, macOS and Windows.

```
minibrowser/
├── Makefile                 gmake assembly instructions (see below)
├── engine/minibrowser.c     the engine: fetch, parse, style, layout, render
├── app/                     Flutter shell (lib/, test/, linux/, macos/, windows/)
├── fixtures/                offline copies of google / facebook / apple / wikipedia
├── test/check-engine.sh     engine checks against the fixtures
├── test/check-live.sh       engine checks against the live sites
└── build/download-cosmocc.sh  fetches the cosmocc toolchain for `make ape`
```

## What the engine does

`engine/minibrowser.c` (~2,500 lines, C11, no external dependencies):

| stage  | what it is                                                                                                   |
|--------|--------------------------------------------------------------------------------------------------------------|
| fetch  | HTTP/1.1 client: chunked encoding, redirects, IPv4/IPv6, Winsock; HTTPS with `-DMB_TLS_OPENSSL`               |
| parse  | forgiving HTML5-style tokenizer + tree builder: implicit end tags (`p`, `li`, `td`…), void and raw-text elements, 250 named + numeric character references |
| style  | built-in user-agent stylesheet plus the inline `style=""` properties that matter (display, color, font-*, text-*) |
| layout | flattens the DOM into block boxes holding inline runs: text, links, images, `<br>`, form controls; list markers, indents, margins, `<pre>` |
| render | JSON display list for Flutter, or wrapped plain text (`lynx -dump` style) for the terminal and for tests    |

There is no JavaScript and no external CSS. Sites render the way they do in
a text browser, with real fonts, clickable links, working forms and images.

Exported symbols (used by the Flutter shell through `dart:ffi`):

```c
char *mb_render_json(const char *html, size_t len, const char *base_url);
char *mb_render_text(const char *html, size_t len, const char *base_url, int width, int links);
char *mb_title(const char *html, size_t len);
char *mb_resolve_url(const char *base, const char *ref);
char *mb_fetch(const char *url, size_t *len, int *status, char **final_url, char **ctype, char **err);
void  mb_free(void *p);
const char *mb_version(void);
```

## Assembly instructions

You need GNU make (`make` on Linux/macOS, `gmake` on the BSDs), a C
compiler, and — for the app — the [Flutter SDK](https://docs.flutter.dev/get-started/install)
with desktop support for your OS enabled.

```sh
cd minibrowser

# 1. the engine: CLI + shared library into o/<os>-<arch>/
make

# 2. try it on the terminal
o/linux-x64/minibrowser -l https://en.wikipedia.org/wiki/Main_Page   # https needs TLS=openssl (auto-detected)
o/linux-x64/minibrowser -w 100 -b https://www.apple.com/ fixtures/apple.html
o/linux-x64/minibrowser -j fixtures/google.html | jq .title

# 3. the checks
make check          # engine vs. the four fixtures, no network needed
make test           # + Flutter widget tests, writes o/screenshots/*.png
make test-live      # engine vs. the real google/facebook/apple/wikipedia pages

# 4. the app
make app            # flutter build <linux|macos|windows>, engine bundled next to it
make run            # flutter run with the engine from o/
```

Overrides: `make CC=clang`, `make TLS=none` (drop the OpenSSL link), `make FLUTTER=/path/to/flutter`.

### One binary for every OS (`make ape`)

```sh
make ape            # downloads cosmocc into .cosmocc/ and builds o/minibrowser.com
./o/minibrowser.com -l https://www.google.com/
```

`o/minibrowser.com` is an Actually Portable Executable: the same file runs
on Linux, macOS, Windows, FreeBSD, OpenBSD and NetBSD, on x86-64 and arm64,
exactly like `redbean.com`. (The APE build of the CLI has no TLS; fetch
https pages with the Flutter app or with `curl | minibrowser.com -`.)

### Platform notes

* **Linux**: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libssl-dev`.
* **macOS**: Xcode command line tools; OpenSSL from Homebrew is auto-detected.
* **Windows**: run from an MSYS2/MinGW shell (`pacman -S mingw-w64-ucrt-x86_64-gcc make`)
  or build the engine with `clang-cl`; the Makefile links `ws2_32` for you.
  Flutter's Windows build needs Visual Studio with the "Desktop development with C++" workload.

## How the Flutter shell finds the engine

`app/lib/engine.dart` looks, in order, at `$MINIBROWSER_ENGINE`, the
`lib/` folder next to the executable (where `make app` copies it), the
macOS `Frameworks/` folder, `o/<os>-<arch>/` upwards from the working
directory, and finally the system library path.

## Tests

`make test` runs two layers:

1. `test/check-engine.sh` renders each fixture with the CLI and greps for
   what each page is known for (Google's two buttons and the `q` field,
   Facebook's login form and `method=post`, Apple's global nav and legal
   footer, Wikipedia's Main Page sections and search box), checks links
   resolve to absolute URLs and that the JSON parses.
2. `app/test/render_test.dart` loads the real shared library over FFI,
   paints each page with the real `PageBody` widget, asserts the same
   things at widget level (text fields with the right placeholders, the
   password field, buttons, headings), drives the browser chrome with a
   stubbed network (URL bar, back/forward, link tap, Google form
   submission carrying hidden fields, network error page), and saves
   `o/screenshots/{google,facebook,apple,wikipedia}.png`.

`make test-live` fetches the real home pages through the engine's own
HTTP(S) client and checks each renders a title, text and links.

### About the fixtures

`fixtures/*.html` are **offline stand-ins**: hand-written pages that mirror
the structure and text of each real home page (Google's search form with
its hidden fields, Facebook's `royal_login_form`, Apple's `globalnav` and
`globalfooter`, MediaWiki's Vector 2022 skin with the Main Page portals).
They were written in a sandbox whose egress policy blocks those hosts, so
they are not verbatim captures. `make fixtures` re-downloads the real
markup when you have network access; the engine checks are written to
hold against the real pages too.

## Design notes

* The C side does everything that does not need a font: parsing, styling,
  box structure, URL resolution, form discovery. Flutter does the text
  layout, because it has the fonts and the platform text stack. This keeps
  the engine deterministic and testable from a shell.
* Table cells are laid out inline, separated by a gap, so simple rows stay
  rows while layout tables degrade to a linear page (like `lynx`).
* Hidden form fields travel with the display list (as invisible controls)
  so submitting Google's form sends `hl`, `source`, `iflsig` etc. like a
  real browser.
* The engine was fuzzed with AddressSanitizer + UBSan over 800 truncated,
  mutated and deeply nested variants of the fixtures without a finding.
