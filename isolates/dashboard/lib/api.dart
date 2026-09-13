/// HTTP client for the isolates control plane (`/api/...`).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Compile-time override: `flutter build web --dart-define=ISOLATES_API=`
/// (empty string) makes the dashboard talk to the origin it was served from,
/// which is what `isolates serve --dashboard build/web` expects.
const String kDefaultApiBase =
    String.fromEnvironment('ISOLATES_API', defaultValue: 'http://127.0.0.1:8787');

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? kDefaultApiBase;

  String baseUrl;
  final http.Client _client = http.Client();

  Uri _uri(String path) {
    final base = baseUrl.trim();
    if (base.isEmpty) return Uri.base.resolve(path);
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$trimmed$path');
  }

  Future<Map<String, dynamic>> _json(http.Response r) async {
    final text = utf8.decode(r.bodyBytes);
    dynamic decoded;
    try {
      decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } catch (_) {
      decoded = {'error': text};
    }
    if (r.statusCode >= 400) {
      final msg = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'request failed';
      throw ApiException(r.statusCode, msg);
    }
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  Future<PlatformStatus> status() async =>
      PlatformStatus.fromJson(await _json(await _client.get(_uri('/api/status'))));

  Future<List<WorkerSummary>> workers() async {
    final j = await _json(await _client.get(_uri('/api/workers')));
    return ((j['workers'] as List?) ?? const [])
        .map((e) => WorkerSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WorkerDetail> worker(String name) async =>
      WorkerDetail.fromJson(await _json(await _client.get(_uri('/api/workers/$name'))));

  Future<WorkerDetail> deploy(
    String name, {
    required String script,
    int? cpuLimit,
    int? memLimit,
    Map<String, String>? env,
  }) async {
    final body = <String, dynamic>{'script': script};
    if (cpuLimit != null) body['cpu_limit'] = cpuLimit;
    if (memLimit != null) body['mem_limit'] = memLimit;
    if (env != null) body['env'] = env;
    final r = await _client.put(_uri('/api/workers/$name'),
        headers: _jsonHeaders, body: jsonEncode(body));
    return WorkerDetail.fromJson(await _json(r));
  }

  Future<void> deleteWorker(String name) async =>
      _json(await _client.delete(_uri('/api/workers/$name')));

  Future<List<LogEntry>> logs(String name) async {
    final j = await _json(await _client.get(_uri('/api/workers/$name/logs')));
    return ((j['logs'] as List?) ?? const [])
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearLogs(String name) async =>
      _json(await _client.delete(_uri('/api/workers/$name/logs')));

  Future<List<KvEntry>> kv(String name) async {
    final j = await _json(await _client.get(_uri('/api/workers/$name/kv')));
    final list = ((j['entries'] as List?) ?? const [])
        .map((e) => KvEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  Future<void> kvPut(String name, String key, String value) async => _json(
      await _client.put(_uri('/api/workers/$name/kv/${Uri.encodeComponent(key)}'),
          body: value));

  Future<void> kvDelete(String name, String key) async => _json(await _client
      .delete(_uri('/api/workers/$name/kv/${Uri.encodeComponent(key)}')));

  Future<void> kvClear(String name) async =>
      _json(await _client.delete(_uri('/api/workers/$name/kv')));

  Future<InvokeResult> invoke(
    String name, {
    String method = 'GET',
    String path = '/',
    Map<String, String> headers = const {},
    String body = '',
  }) async {
    final r = await _client.post(_uri('/api/workers/$name/invoke'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'method': method,
          'path': path,
          'headers': headers,
          'body': body,
        }));
    return InvokeResult.fromJson(await _json(r));
  }

  Future<AssembleResult> assemble(String script) async {
    final r = await _client.post(_uri('/api/assemble'),
        headers: _jsonHeaders, body: jsonEncode({'script': script}));
    return AssembleResult.fromJson(await _json(r));
  }

  Future<List<ExampleScript>> examples() async {
    final j = await _json(await _client.get(_uri('/api/examples')));
    return ((j['examples'] as List?) ?? const [])
        .map((e) => ExampleScript.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<InstructionDoc>> reference() async {
    final j = await _json(await _client.get(_uri('/api/reference')));
    return ((j['instructions'] as List?) ?? const [])
        .map((e) => InstructionDoc.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Public URL of a worker route, for display and copy-paste.
  String workerUrl(String name, [String path = '/']) {
    final base = baseUrl.trim().isEmpty ? Uri.base.origin : baseUrl.trim();
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/w/$name$path';
  }
}
