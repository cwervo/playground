import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'click_log.dart';

/// Sends a batch of clicks somewhere. Throws if the batch wasn't accepted.
abstract class PopUploader {
  Future<void> upload(List<LinkClick> clicks);
}

/// POSTs `{"pops": [...]}` as JSON. Any 2xx means every click was accepted.
/// Retries resend the same ids, so the server should de-duplicate on `id`.
class HttpPopUploader implements PopUploader {
  HttpPopUploader(this.endpoint, {http.Client? client})
      : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<void> upload(List<LinkClick> clicks) async {
    final res = await _client
        .post(
          endpoint,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'pops': clicks.map((c) => c.toJson()).toList()}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw http.ClientException(
          'Upload failed: HTTP ${res.statusCode}', endpoint);
    }
  }
}

/// Offline-first sync: [ClickLog] is always written first, and this uploads
/// whatever is pending whenever there's a chance to.
///
/// Callers [nudge] it when a chance appears (a new click, the network coming
/// back, the app resuming). Failures back off exponentially up to [maxRetry];
/// a nudge skips the wait, since it usually means conditions just changed.
class PopSync {
  PopSync({
    required this.log,
    required this.uploader,
    this.batchSize = 50,
    this.debounce = const Duration(seconds: 2),
    this.retryBase = const Duration(seconds: 5),
    this.maxRetry = const Duration(minutes: 5),
  }) {
    log.addListener(_onLogChanged);
  }

  final ClickLog log;
  final PopUploader uploader;
  final int batchSize;
  final Duration debounce;
  final Duration retryBase;
  final Duration maxRetry;

  Timer? _timer;
  Future<void>? _flushing;
  Duration? _retryDelay;
  bool _disposed = false;

  /// The wait before the next retry, or null if the last flush succeeded.
  Duration? get retryDelay => _retryDelay;

  /// Upload soon (after [debounce], so a burst of clicks goes as one batch).
  void nudge() {
    if (_disposed || log.pending.isEmpty) return;
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  /// Upload everything pending now. Concurrent calls share one run.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    _timer?.cancel();
    try {
      while (!_disposed) {
        final batch = log.pending.take(batchSize).toList();
        if (batch.isEmpty) break;
        await uploader.upload(batch);
        await log.markSynced({for (final c in batch) c.id});
      }
      _retryDelay = null;
    } catch (e) {
      final delay = _retryDelay == null ? retryBase : _retryDelay! * 2;
      _retryDelay = delay > maxRetry ? maxRetry : delay;
      debugPrint('Pop upload failed, retrying in $_retryDelay: $e');
      if (!_disposed) _timer = Timer(_retryDelay!, flush);
    }
  }

  void _onLogChanged() {
    // New clicks are a chance to upload; skip while a flush is running, since
    // its loop will pick them up (and its own markSynced also lands here).
    if (_flushing == null) nudge();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    log.removeListener(_onLogChanged);
  }
}
