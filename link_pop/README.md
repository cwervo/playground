# Link Pop 💥

A Flutter app where every link click goes *pop*. Each click:

1. plays a pop sound (`assets/pop.wav`),
2. is saved to a persistent history (`shared_preferences`), and
3. opens a springy "Pop!" modal showing the link, the time, and how many
   times you've popped it. Choose **Open link** to actually open the link, or **Close**.

The history button in the app bar shows a count badge and opens the list of
every saved pop, which you can clear.

Links come from a paragraph with inline links, a list of starter links, and
anything you add with the **Add a link** field. All of them go through the
same `_onLinkTap` handler in `lib/main.dart`.

## Offline first, upload later

Every click is saved on the device first, so the app works the same with or
without a network. If you give the app an upload URL, it sends saved pops to
it whenever there's a chance:

- at launch,
- a couple of seconds after new clicks (a burst goes as one batch),
- when the network comes back (`connectivity_plus`), and
- when the app returns to the foreground.

Failed uploads retry with exponential backoff (5 s up to 5 min). Any of the
chances above skips the wait. The history screen shows which pops are uploaded
and how many are still waiting.

```sh
flutter run --dart-define=POP_SYNC_URL=https://example.com/pops
```

The app POSTs `{"pops": [{"id", "label", "url", "at", "synced"}, ...]}` in
batches of up to 50, oldest first, and treats any 2xx as accepted. A retry can
resend pops the server already stored, so **de-duplicate on `id`**. On web,
the endpoint must allow CORS. With no URL set, nothing is uploaded and pops
stay on the device.

## Run

```sh
flutter pub get
flutter run            # any device: android, ios, web, linux, macos, windows
flutter test
```

## Files

- `lib/main.dart`: the app, home screen, and link handling
- `lib/pop_dialog.dart`: the modal, which scales in with an elastic "pop"
- `lib/pop_sound.dart`: plays the sound with `audioplayers` (low-latency mode)
- `lib/click_log.dart`: the saved click history, which is the source of truth
- `lib/pop_sync.dart`: the opportunistic uploader (batching, backoff, and
  sharing one upload run between concurrent requests)
- `lib/history_page.dart`: the list of saved pops
- `tool/make_pop.py`: regenerates `assets/pop.wav`, a synthesized
  bubble pop made of a falling sine sweep plus a noise click. It uses only the
  Python standard library.
