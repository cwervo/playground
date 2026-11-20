import 'package:flutter/rendering.dart' show SemanticsBinding;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_page.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Expose the UI to screen readers from the first frame instead of waiting
  // for the browser's "enable accessibility" prompt.
  SemanticsBinding.instance.ensureSemantics();
  final store = AppStore(await SharedPreferences.getInstance());
  runApp(SwitchboardApp(store: store));
}

/// Colours beyond what [ColorScheme] names.
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.muted,
    required this.line,
    required this.panel,
    required this.good,
    required this.bad,
  });

  final Color muted;
  final Color line;
  final Color panel;
  final Color good;
  final Color bad;

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) =>
      t < 0.5 || other is! Palette ? this : other;
}

const mono = 'IBM Plex Mono';

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // Ink-blue on white, after the #1010FF code panels elsewhere in this repo.
  final bg = dark ? const Color(0xFF0A0A1F) : const Color(0xFFFFFFFF);
  final panel = dark ? const Color(0xFF15153A) : const Color(0xFFF1F2FC);
  final ink = dark ? const Color(0xFFE8E9FF) : const Color(0xFF0B0B3B);
  final muted = dark ? const Color(0xFF9DA0C8) : const Color(0xFF585B85);
  final line = dark ? const Color(0xFF2B2B5E) : const Color(0xFFD5D7EE);
  final accent = dark ? const Color(0xFFA3AAFF) : const Color(0xFF1010FF);
  final onAccent = dark ? const Color(0xFF0A0A1F) : const Color(0xFFFFFFFF);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1010FF),
        brightness: brightness,
      ).copyWith(
        primary: accent,
        onPrimary: onAccent,
        surface: bg,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: bg,
        surfaceContainerLow: panel,
        surfaceContainer: panel,
        surfaceContainerHigh: panel,
        surfaceContainerHighest: panel,
        outline: line,
        outlineVariant: line,
        error: dark ? const Color(0xFFFF9A8F) : const Color(0xFFB3261E),
      );

  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: 'IBM Plex Sans',
    splashFactory: NoSplash.splashFactory,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  const label = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    extensions: [
      Palette(
        muted: muted,
        line: line,
        panel: panel,
        good: dark ? const Color(0xFF7FD6A8) : const Color(0xFF0B7A45),
        bad: scheme.error,
      ),
    ],
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        textStyle: label,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: line),
        foregroundColor: ink,
        textStyle: label,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        textStyle: label,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: bg,
      hoverColor: Colors.transparent,
      hintStyle: TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
    ),
  );
}

class SwitchboardApp extends StatelessWidget {
  const SwitchboardApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Switchboard',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ChatPage(store: store),
    );
  }
}
