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
- `lib/click_log.dart`: the saved click history
- `lib/history_page.dart`: the list of saved pops
- `tool/make_pop.py`: regenerates `assets/pop.wav`, a synthesized
  bubble pop made of a falling sine sweep plus a noise click. It uses only the
  Python standard library.
