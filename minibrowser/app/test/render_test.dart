// Render tests: each of the four fixture home pages goes through the real C
// engine (over dart:ffi) and is painted by the real PageBody widget. The
// tests assert the page-defining text and controls are on screen, drive the
// browser chrome end-to-end with a stubbed network, and save a PNG of every
// page under o/screenshots/ so a human can eyeball the result.
//
// Run with:  make test        (or: MINIBROWSER_ENGINE=... flutter test)

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minibrowser/engine.dart';
import 'package:minibrowser/fetcher.dart';
import 'package:minibrowser/main.dart';
import 'package:minibrowser/page_body.dart';
import 'package:minibrowser/render_tree.dart';

final Directory _root = _findRoot();

Directory _findRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (File('${dir.path}/fixtures/google.html').existsSync()) return dir;
    dir = dir.parent;
  }
  throw StateError('fixtures/ not found above ${Directory.current.path}');
}

const _sites = <String, String>{
  'google': 'https://www.google.com/',
  'facebook': 'https://www.facebook.com/',
  'apple': 'https://www.apple.com/',
  'wikipedia': 'https://en.wikipedia.org/wiki/Main_Page',
};

String fixture(String name) => File('${_root.path}/fixtures/$name.html').readAsStringSync();

/// A network stub that serves the fixture pages for the four sites.
Future<FetchResult> fakeFetch(Uri url, {String method = 'GET', Map<String, String>? form}) async {
  for (final e in _sites.entries) {
    final site = Uri.parse(e.value);
    if (url.host == site.host) {
      return FetchResult(url: url, status: 200, contentType: 'text/html', body: fixture(e.key));
    }
  }
  return FetchResult(
    url: url,
    status: 404,
    contentType: 'text/html',
    body: '<h1>Not found</h1><p>${url.toString()}</p>',
  );
}

/// Loads a real font so screenshots are legible instead of Ahem boxes.
Future<String?> loadScreenshotFont() async {
  const candidates = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/dejavu/DejaVuSans.ttf',
    '/Library/Fonts/Arial.ttf',
    'C:/Windows/Fonts/arial.ttf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      final loader = FontLoader('ScreenshotFont')..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return 'ScreenshotFont';
    }
  }
  return null;
}

Future<void> saveScreenshot(WidgetTester tester, Key key, String name) async {
  final boundary = tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${_root.path}/o/screenshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Taps the link whose span text is [text] by invoking its tap recognizer,
/// the way a pointer landing on that span would.
Future<void> tapLink(WidgetTester tester, String text) async {
  TapGestureRecognizer? found;
  for (final e in find.byType(RichText).evaluate()) {
    (e.widget as RichText).text.visitChildren((span) {
      if (span is TextSpan && span.text == text && span.recognizer is TapGestureRecognizer) {
        found = span.recognizer as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (found != null) break;
  }
  expect(found, isNotNull, reason: 'no link with text "$text"');
  found!.onTap!();
  await tester.pumpAndSettle();
}

Widget harness(Widget child, String? font) => MaterialApp(
      theme: ThemeData(fontFamily: font, useMaterial3: true),
      home: Scaffold(body: RepaintBoundary(key: const Key('shot'), child: child)),
    );

void main() {
  late Engine engine;
  String? font;

  setUpAll(() async {
    engine = Engine.load();
    font = await loadScreenshotFont();
  });

  group('engine', () {
    test('loads and reports a version', () {
      expect(engine.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('resolves relative urls', () {
      expect(engine.resolve('https://a.example/x/y.html', '../z'), 'https://a.example/z');
      expect(engine.resolve('https://a.example/x/y.html', '//b.example/q'), 'https://b.example/q');
      expect(engine.resolve('https://a.example/x/y.html', '#frag'), 'https://a.example/x/y.html#frag');
    });

    for (final e in _sites.entries) {
      test('${e.key} produces a display list with title, links and text', () {
        final page = PageModel.fromJson(engine.renderJson(fixture(e.key), e.value));
        expect(page.title, isNotEmpty);
        expect(page.blocks.length, greaterThan(5));
        expect(page.links.length, greaterThan(5));
        for (final l in page.links) {
          expect(l.href, startsWith('http'), reason: 'links must be absolute: ${l.href}');
        }
      });
    }
  });

  group('renders', () {
    Future<PageModel> pump(WidgetTester tester, String name) async {
      tester.view.physicalSize = const Size(1100, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final page = PageModel.fromJson(engine.renderJson(fixture(name), _sites[name]!));
      await tester.pumpWidget(harness(
        PageBody(page: page, loadImages: false, onNavigate: (_) {}, onSubmit: (_, _) {}),
        font,
      ));
      await tester.pumpAndSettle();
      return page;
    }

    testWidgets('Google: logo, search box and both buttons', (tester) async {
      final page = await pump(tester, 'google');
      expect(page.title, 'Google');
      expect(find.text('Google Search'), findsOneWidget);
      expect(find.text("I'm Feeling Lucky"), findsOneWidget);
      expect(find.text('Google'), findsWidgets); // image alt placeholder
      expect(find.byType(TextField), findsWidgets); // the q input
      expect(page.forms.single.action, 'https://www.google.com/search');
      expect(page.plainText, contains('Advanced search'));
      expect(page.plainText, contains('Gmail'));
      await saveScreenshot(tester, const Key('shot'), 'google');
    });

    testWidgets('Facebook: login form and footer', (tester) async {
      final page = await pump(tester, 'facebook');
      expect(page.title, 'Facebook – log in or sign up');
      expect(find.textContaining('Facebook helps you connect'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
      final fields = find.byType(TextField).evaluate().map((e) => e.widget as TextField).toList();
      expect(fields.where((t) => t.decoration?.hintText == 'Email address or phone number'), hasLength(1));
      expect(fields.where((t) => t.obscureText), hasLength(1), reason: 'password field');
      expect(page.plainText, contains('Forgotten password?'));
      expect(page.plainText, contains('Create new account'));
      expect(page.forms.first.method, 'post');
      await saveScreenshot(tester, const Key('shot'), 'facebook');
    });

    testWidgets('Apple: global nav, hero headlines and footer', (tester) async {
      final page = await pump(tester, 'apple');
      expect(page.title, 'Apple');
      for (final item in ['Store', 'Mac', 'iPad', 'iPhone', 'Watch', 'AirPods', 'Support']) {
        expect(find.text(item), findsWidgets, reason: 'nav item $item');
      }
      expect(find.textContaining('iPhone 17 Pro'), findsWidgets);
      expect(page.plainText, contains('MacBook Air'));
      expect(page.plainText, contains('Copyright © 2026 Apple Inc.'));
      final hrefs = page.links.map((l) => l.href).toSet();
      expect(hrefs, contains('https://www.apple.com/mac/'));
      expect(hrefs, contains('https://support.apple.com/?cid=gn-ols-home-hp-tab'));
      await saveScreenshot(tester, const Key('shot'), 'apple');
    });

    testWidgets('Wikipedia: main page sections, search and lists', (tester) async {
      final page = await pump(tester, 'wikipedia');
      expect(page.title, 'Wikipedia, the free encyclopedia');
      expect(find.text('Main Page'), findsWidgets);
      expect(find.textContaining("From today's featured article"), findsOneWidget);
      final text = page.plainText;
      for (final section in ['In the news', 'Did you know', 'On this day', "Today's featured picture"]) {
        expect(text, contains(section));
      }
      expect(text, contains('Welcome to Wikipedia'));
      expect(text, contains('• ... that tardigrades'));
      final search = find.byType(TextField).evaluate().map((e) => e.widget as TextField);
      expect(search.where((t) => t.decoration?.hintText == 'Search Wikipedia'), hasLength(1));
      expect(page.forms.first.action, 'https://en.wikipedia.org/w/index.php');
      await saveScreenshot(tester, const Key('shot'), 'wikipedia');
    });
  });

  group('browser chrome', () {
    testWidgets('navigates between the four sites with back/forward and link taps', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MiniBrowserApp(fetch: fakeFetch, loadImages: false));
      await tester.pumpAndSettle();
      // start page lists the four sites
      expect(find.text('minibrowser'), findsWidgets);

      Future<void> go(String url) async {
        await tester.enterText(find.byKey(const Key('urlField')), url);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
      }

      await go('https://www.google.com/');
      expect(find.text("I'm Feeling Lucky"), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('statusTitle'))).data, 'Google');

      await go('https://www.apple.com/');
      expect(find.textContaining('iPhone 17 Pro'), findsWidgets);

      // tap the "Wikipedia"-bound link? apple has none; use the URL bar for wikipedia
      await go('https://en.wikipedia.org/wiki/Main_Page');
      expect(tester.widget<Text>(find.byKey(const Key('statusTitle'))).data, 'Wikipedia, the free encyclopedia');

      // back goes to apple, back again to google, forward to apple
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('statusTitle'))).data, 'Apple');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('statusTitle'))).data, 'Google');
      await tester.tap(find.byTooltip('Forward'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('statusTitle'))).data, 'Apple');

      // tapping a link in the page navigates: home page -> Facebook
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      await tapLink(tester, 'Facebook');
      expect(tester.widget<Text>(find.byKey(const Key('statusTitle'))).data, 'Facebook – log in or sign up');
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    });

    testWidgets('submitting the Google search form builds a GET query', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requested = <Uri>[];
      Future<FetchResult> spy(Uri url, {String method = 'GET', Map<String, String>? form}) {
        requested.add(url);
        return fakeFetch(url, method: method, form: form);
      }

      await tester.pumpWidget(MiniBrowserApp(fetch: spy, loadImages: false, initialUrl: 'https://www.google.com/'));
      await tester.pumpAndSettle();
      final q = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == null && w.obscureText == false);
      expect(q, findsWidgets);
      await tester.enterText(q.first, 'flutter ffi');
      await tester.tap(find.widgetWithText(FilledButton, 'Google Search'));
      await tester.pumpAndSettle();
      final search = requested.lastWhere((u) => u.path == '/search');
      expect(search.host, 'www.google.com');
      expect(search.queryParameters['q'], 'flutter ffi');
      expect(search.queryParameters['hl'], 'en', reason: 'hidden fields travel with the form');
    });

    testWidgets('shows an error page when the network fails', (tester) async {
      Future<FetchResult> failing(Uri url, {String method = 'GET', Map<String, String>? form}) async {
        throw const SocketException('no route to host');
      }

      await tester.pumpWidget(MiniBrowserApp(fetch: failing, loadImages: false, initialUrl: 'https://nowhere.example/'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('errorText')), findsOneWidget);
      expect(find.textContaining('no route to host'), findsOneWidget);
    });
  });
}
