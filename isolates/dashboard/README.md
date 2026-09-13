# isolates dashboard

Flutter web/desktop front end for the `isolates` runtime in the parent
directory. It talks only to the runtime's JSON control plane (`/api/...`).

```sh
flutter pub get
flutter run -d chrome                       # dev: points at http://127.0.0.1:8787
flutter build web --no-web-resources-cdn --dart-define=ISOLATES_API=
../bin/isolates serve --dashboard build/web   # prod: same-origin, served by the runtime
```

The API URL can also be changed at runtime from the toolbar button at the
bottom of the navigation rail.

Screens:

- **Overview** - scheduler counters (fibers, assembly context switches),
  request/error totals, per-worker requests-per-second sparklines.
- **Workers** - deploy from a bundled example or a blank script; per worker:
  script editor with assemble/deploy and bytecode listing, CPU/memory limits,
  bindings, an invoke console with per-request budget meters, live logs and a
  KV browser.
- **Reference** - the instruction set, pulled live from the runtime.
