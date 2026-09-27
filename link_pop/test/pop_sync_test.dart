import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_pop/click_log.dart';
import 'package:link_pop/pop_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records batches; fails while [online] is false.
class FakeUploader implements PopUploader {
  bool online = true;
  final List<List<String>> batches = [];

  @override
  Future<void> upload(List<LinkClick> clicks) async {
    if (!online) throw Exception('offline');
    batches.add([for (final c in clicks) c.label]);
  }
}

void main() {
  late ClickLog log;
  late FakeUploader uploader;
  late PopSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    log = ClickLog();
    await log.load();
    uploader = FakeUploader();
    sync = PopSync(
      log: log,
      uploader: uploader,
      batchSize: 2,
      debounce: const Duration(milliseconds: 10),
      retryBase: const Duration(milliseconds: 20),
      maxRetry: const Duration(milliseconds: 50),
    );
  });

  tearDown(() => sync.dispose());

  test('clicks save offline and upload oldest-first in batches later',
      () async {
    uploader.online = false;
    for (final l in ['a', 'b', 'c']) {
      await log.record(l, 'https://$l.example');
    }
    await sync.flush();
    expect(log.pending, hasLength(3));
    expect(log.total, 3);

    uploader.online = true;
    await sync.flush();
    expect(uploader.batches, [
      ['a', 'b'],
      ['c'],
    ]);
    expect(log.pending, isEmpty);
    expect(sync.retryDelay, isNull);
  });

  test('synced state persists across reloads', () async {
    await log.record('a', 'https://a.example');
    await sync.flush();

    final reloaded = ClickLog();
    await reloaded.load();
    expect(reloaded.clicks.single.synced, isTrue);
    expect(reloaded.clicks.single.id, log.clicks.single.id);
  });

  test('failures back off exponentially, capped at maxRetry', () async {
    uploader.online = false;
    await log.record('a', 'https://a.example');
    await sync.flush();
    expect(sync.retryDelay, const Duration(milliseconds: 20));
    await sync.flush();
    expect(sync.retryDelay, const Duration(milliseconds: 40));
    await sync.flush();
    expect(sync.retryDelay, const Duration(milliseconds: 50));
  });

  test('retries on its own once the network is back', () async {
    uploader.online = false;
    await log.record('a', 'https://a.example');
    await sync.flush();
    uploader.online = true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(log.pending, isEmpty);
  });

  test('a new click nudges an upload without an explicit flush', () async {
    await log.record('a', 'https://a.example');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(uploader.batches, [
      ['a'],
    ]);
  });

  test('concurrent flushes share one run (no duplicate uploads)', () async {
    await log.record('a', 'https://a.example');
    await Future.wait([sync.flush(), sync.flush(), sync.flush()]);
    expect(uploader.batches, hasLength(1));
  });

  test('old and corrupt saved data load without crashing', () async {
    SharedPreferences.setMockInitialValues({
      'link_pop.clicks': [
        jsonEncode({
          'label': 'old',
          'url': 'https://old.example',
          'at': '2026-01-01T00:00:00.000',
        }),
        'not json',
      ],
    });
    final old = ClickLog();
    await old.load();
    expect(old.total, 1);
    expect(old.clicks.single.synced, isFalse);
    expect(old.clicks.single.id, startsWith('legacy-'));
  });
}
