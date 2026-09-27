import 'package:flutter_test/flutter_test.dart';
import 'package:link_pop/click_log.dart';
import 'package:link_pop/main.dart';
import 'package:link_pop/pop_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePopSound implements PopSound {
  int plays = 0;
  @override
  Future<void> play() async => plays++;
}

void main() {
  late ClickLog log;
  late FakePopSound sound;
  late List<Uri> opened;

  Future<void> pumpApp(WidgetTester tester, {bool canOpen = true}) async {
    await tester.pumpWidget(LinkPopApp(
      log: log,
      sound: sound,
      openLink: (uri) async {
        opened.add(uri);
        return canOpen;
      },
    ));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    log = ClickLog();
    await log.load();
    sound = FakePopSound();
    opened = [];
  });

  testWidgets('clicking a link pops, saves, and shows the modal',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();

    expect(sound.plays, 1);
    expect(log.total, 1);
    expect(log.clicks.first.url, 'https://flutter.dev');
    expect(find.text('Pop!'), findsOneWidget);
    expect(find.textContaining('first pop'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Pop!'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('"Open link" opens the URL and repeat clicks are counted',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pop #2'), findsOneWidget);
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://flutter.dev')]);
    expect(sound.plays, 2);
    expect(find.text('2 💥'), findsOneWidget);
  });

  testWidgets('clicks persist and show up in history', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Bubble wrap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final reloaded = ClickLog();
    await reloaded.load();
    expect(reloaded.total, 1);
    expect(reloaded.clicks.first.label, 'Bubble wrap');

    await tester.tap(find.byTooltip('Saved pops'));
    await tester.pumpAndSettle();
    expect(find.text('Saved pops (1)'), findsOneWidget);
    expect(find.text('https://en.wikipedia.org/wiki/Bubble_wrap'),
        findsOneWidget);
  });

  testWidgets('a link that fails to open shows a message', (tester) async {
    await pumpApp(tester, canOpen: false);
    await tester.tap(find.text('Flutter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open https://flutter.dev"), findsOneWidget);
    expect(log.total, 1);
  });
}
