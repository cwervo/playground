# minibrowser (Flutter shell)

The Flutter side of the mini browser. The page engine is `../engine/minibrowser.c`,
loaded over `dart:ffi`; build it and run everything from the top-level Makefile:

    cd .. && make        # engine
    make test            # engine checks + these widget tests
    make app             # flutter build for this desktop OS, engine bundled
    make run             # flutter run

`lib/engine.dart` binds the C API, `lib/render_tree.dart` models the JSON
display list, `lib/page_body.dart` paints it (real text layout, links,
images, forms), `lib/fetcher.dart` fetches pages with dart:io, and
`lib/main.dart` is the browser chrome.
