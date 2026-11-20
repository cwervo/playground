import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'providers.dart';

/// One turn of the conversation as sent to a provider.
class Turn {
  const Turn(this.role, this.text);

  /// `user` or `assistant`.
  final String role;
  final String text;
}

/// A model an account can use.
class ModelInfo {
  const ModelInfo(this.id, {this.label, this.maxOutput});
  final String id;
  final String? label;

  /// Output-token ceiling, when the provider reports one.
  final int? maxOutput;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (label != null) 'label': label,
    if (maxOutput != null) 'maxOutput': maxOutput,
  };

  static ModelInfo fromJson(Map<String, dynamic> j) => ModelInfo(
    j['id'] as String,
    label: j['label'] as String?,
    maxOutput: j['maxOutput'] as int?,
  );
}

/// A failure worth showing to the person, already phrased for them.
class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A piece of a streamed reply.
class Chunk {
  const Chunk.text(String this.text) : note = null;
  const Chunk.note(String this.note) : text = null;
  final String? text;

  /// Out-of-band remark, e.g. "stopped at the length limit".
  final String? note;
}

/// A running request that can be cancelled.
class ChatStream {
  ChatStream(this.chunks, this._cancel);
  final Stream<Chunk> chunks;
  final void Function() _cancel;
  void cancel() => _cancel();
}

/// Claude models that accept the server-side refusal-fallback parameter.
const _anthropicFallbackModels = [
  'claude-fable-5-2',
  'claude-fable-5-1',
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-sonnet-5-5',
];

ChatStream streamChat({
  required ModelProvider provider,
  required String apiKey,
  required String model,
  required List<Turn> turns,
  String system = '',
  int? maxOutput,
}) {
  if (provider.kind == ApiKind.demo) return _demo(turns);
  final client = http.Client();
  final Stream<Chunk> chunks = switch (provider.kind) {
    ApiKind.anthropic => _anthropic(
      client,
      provider,
      apiKey,
      model,
      turns,
      system,
      maxOutput,
    ),
    ApiKind.gemini => _gemini(client, provider, apiKey, model, turns, system),
    _ => _openAi(client, provider, apiKey, model, turns, system),
  };
  return ChatStream(_guard(chunks, provider, client), client.close);
}

/// Lists the models this key can use, newest or most capable first where the
/// provider gives us enough to tell.
Future<List<ModelInfo>> listModels(ModelProvider provider, String apiKey) async {
  if (provider.kind == ApiKind.demo) {
    return const [ModelInfo('canned-reply')];
  }
  final client = http.Client();
  try {
    final (uri, headers) = switch (provider.kind) {
      ApiKind.anthropic => (
        Uri.parse('${provider.baseUrl}/models?limit=1000'),
        _anthropicHeaders(apiKey),
      ),
      ApiKind.gemini => (
        Uri.parse('${provider.baseUrl}/models?pageSize=1000'),
        {'x-goog-api-key': apiKey},
      ),
      _ => (
        Uri.parse('${provider.baseUrl}/models'),
        {'Authorization': 'Bearer $apiKey'},
      ),
    };
    final http.Response res;
    try {
      res = await client.get(uri, headers: headers);
    } on http.ClientException {
      throw LlmException(_unreachable(provider));
    }
    if (res.statusCode != 200) {
      throw LlmException(_describeError(provider, res.statusCode, res.body));
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    switch (provider.kind) {
      case ApiKind.anthropic:
        return [
          for (final m in (json['data'] as List? ?? const []))
            ModelInfo(
              m['id'] as String,
              label: m['display_name'] as String?,
              maxOutput: m['max_tokens'] as int?,
            ),
        ];
      case ApiKind.gemini:
        return [
          for (final m in (json['models'] as List? ?? const []))
            if ((m['supportedGenerationMethods'] as List? ?? const []).contains(
              'generateContent',
            ))
              ModelInfo(
                (m['name'] as String).replaceFirst('models/', ''),
                label: m['displayName'] as String?,
              ),
        ];
      default:
        final data = [...(json['data'] as List? ?? const [])];
        data.sort(
          (a, b) => ((b['created'] as num?) ?? 0).compareTo(
            (a['created'] as num?) ?? 0,
          ),
        );
        return [
          for (final m in data)
            if (_looksLikeChatModel(m['id'] as String))
              ModelInfo(m['id'] as String),
        ];
    }
  } finally {
    client.close();
  }
}

/// Hides the embedding, speech and image models that share `/models` with
/// chat models on OpenAI-style APIs.
bool _looksLikeChatModel(String id) {
  const notChat = [
    'embedding',
    'whisper',
    'tts',
    'dall-e',
    'image',
    'audio',
    'realtime',
    'moderation',
    'transcribe',
    'sora',
    'video',
    'babbage',
    'davinci',
  ];
  return !notChat.any(id.contains);
}

// ---------------------------------------------------------------- Anthropic

Map<String, String> _anthropicHeaders(String apiKey) => {
  'x-api-key': apiKey,
  'anthropic-version': '2023-06-01',
  // Anthropic only answers browser (CORS) requests that opt in explicitly.
  'anthropic-dangerous-direct-browser-access': 'true',
};

Stream<Chunk> _anthropic(
  http.Client client,
  ModelProvider provider,
  String apiKey,
  String model,
  List<Turn> turns,
  String system,
  int? maxOutput,
) async* {
  final body = <String, dynamic>{
    'model': model,
    'max_tokens': maxOutput == null || maxOutput > 64000 ? 64000 : maxOutput,
    'stream': true,
    if (system.isNotEmpty) 'system': system,
    'messages': [
      for (final t in turns) {'role': t.role, 'content': t.text},
    ],
  };
  final headers = {
    ..._anthropicHeaders(apiKey),
    'content-type': 'application/json',
  };

  // On the newest models a safety classifier can decline a request. Asking
  // for the default fallback lets the API re-run it on another Claude model
  // in the same call instead of returning nothing.
  final wantsFallback = _anthropicFallbackModels.contains(model);
  var res = await _post(
    client,
    Uri.parse('${provider.baseUrl}/messages'),
    wantsFallback
        ? {...headers, 'anthropic-beta': 'server-side-fallback-2026-07-01'}
        : headers,
    wantsFallback ? {...body, 'fallbacks': 'default'} : body,
  );
  if (wantsFallback && res.statusCode == 400) {
    final text = await res.stream.bytesToString();
    if (!text.contains('fallback')) {
      throw LlmException(_describeError(provider, 400, text));
    }
    // This account can't use fallbacks; send the plain request.
    res = await _post(
      client,
      Uri.parse('${provider.baseUrl}/messages'),
      headers,
      body,
    );
  }
  await _ensureOk(provider, res);

  await for (final event in _sse(res)) {
    switch (event['type']) {
      case 'content_block_delta':
        final delta = event['delta'] as Map<String, dynamic>? ?? const {};
        if (delta['type'] == 'text_delta') {
          yield Chunk.text(delta['text'] as String? ?? '');
        }
      case 'content_block_start':
        final block = event['content_block'] as Map<String, dynamic>?;
        if (block?['type'] == 'fallback') {
          final to = (block?['to'] as Map?)?['model'];
          yield Chunk.note(
            '$model declined this request${to == null ? '' : '; $to answered instead'}.',
          );
        }
      case 'message_delta':
        final reason = (event['delta'] as Map?)?['stop_reason'];
        if (reason == 'refusal') {
          yield const Chunk.note('The model declined this request.');
        } else if (reason == 'max_tokens') {
          yield const Chunk.note('Stopped at the length limit.');
        }
      case 'error':
        final err = event['error'] as Map?;
        throw LlmException(
          '${provider.maker} reported an error mid-reply: '
          '${err?['message'] ?? err?['type'] ?? 'unknown error'}',
        );
    }
  }
}

// ------------------------------------------------- OpenAI-compatible (3 of 5)

Stream<Chunk> _openAi(
  http.Client client,
  ModelProvider provider,
  String apiKey,
  String model,
  List<Turn> turns,
  String system,
) async* {
  final res = await _post(
    client,
    Uri.parse('${provider.baseUrl}/chat/completions'),
    {'Authorization': 'Bearer $apiKey', 'content-type': 'application/json'},
    {
      'model': model,
      'stream': true,
      'messages': [
        if (system.isNotEmpty) {'role': 'system', 'content': system},
        for (final t in turns) {'role': t.role, 'content': t.text},
      ],
    },
  );
  await _ensureOk(provider, res);

  await for (final event in _sse(res)) {
    if (event['error'] != null) {
      final err = event['error'];
      throw LlmException(
        '${provider.maker} reported an error mid-reply: '
        '${err is Map ? err['message'] : err}',
      );
    }
    final choices = event['choices'] as List?;
    if (choices == null || choices.isEmpty) continue;
    final choice = choices.first as Map<String, dynamic>;
    final delta = choice['delta'] as Map<String, dynamic>?;
    final text = delta?['content'];
    if (text is String && text.isNotEmpty) yield Chunk.text(text);
    final refusal = delta?['refusal'];
    if (refusal is String && refusal.isNotEmpty) yield Chunk.text(refusal);
    switch (choice['finish_reason']) {
      case 'length':
        yield const Chunk.note('Stopped at the length limit.');
      case 'content_filter':
        yield const Chunk.note(
          'The provider\'s content filter stopped this reply.',
        );
    }
  }
}

// ------------------------------------------------------------------- Gemini

Stream<Chunk> _gemini(
  http.Client client,
  ModelProvider provider,
  String apiKey,
  String model,
  List<Turn> turns,
  String system,
) async* {
  final res = await _post(
    client,
    Uri.parse('${provider.baseUrl}/models/$model:streamGenerateContent?alt=sse'),
    {'x-goog-api-key': apiKey, 'content-type': 'application/json'},
    {
      if (system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'contents': [
        for (final t in turns)
          {
            'role': t.role == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': t.text},
            ],
          },
      ],
    },
  );
  await _ensureOk(provider, res);

  await for (final event in _sse(res)) {
    if (event['error'] != null) {
      throw LlmException(
        'Google reported an error mid-reply: '
        '${(event['error'] as Map)['message']}',
      );
    }
    final blocked = (event['promptFeedback'] as Map?)?['blockReason'];
    if (blocked != null) {
      yield Chunk.note('Gemini blocked this prompt ($blocked).');
    }
    final candidates = event['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) continue;
    final candidate = candidates.first as Map<String, dynamic>;
    for (final part
        in ((candidate['content'] as Map?)?['parts'] as List? ?? const [])) {
      // Parts flagged `thought` are reasoning summaries, not the answer.
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String && text.isNotEmpty) yield Chunk.text(text);
    }
    switch (candidate['finishReason']) {
      case null || 'STOP':
        break;
      case 'MAX_TOKENS':
        yield const Chunk.note('Stopped at the length limit.');
      case final other:
        yield Chunk.note('Gemini stopped early ($other).');
    }
  }
}

// --------------------------------------------------------------------- Demo

ChatStream _demo(List<Turn> turns) {
  var cancelled = false;
  Stream<Chunk> run() async* {
    final asked = turns.isEmpty ? '' : turns.last.text.trim();
    final quoted = asked.length > 80 ? '${asked.substring(0, 80)}…' : asked;
    final reply =
        'This is the **demo line**: a canned reply generated on this device, '
        'so you can try the app before adding a key. No request left your '
        'browser.\n\n'
        'You wrote: _${quoted.replaceAll('_', r'\_')}_\n\n'
        'To talk to a real model:\n\n'
        '1. Open **Keys** and paste a key for any provider.\n'
        '2. Press **Check key** to load the models your account can use.\n'
        '3. Pick that provider from the switcher above the conversation.\n\n'
        'You can change provider between messages. The whole conversation '
        'so far is sent to whichever one you pick next.\n\n'
        '```\n/help   list the composer commands\n```';
    for (final match in RegExp(r'\S+\s*').allMatches(reply)) {
      if (cancelled) return;
      await Future<void>.delayed(const Duration(milliseconds: 22));
      yield Chunk.text(match.group(0)!);
    }
  }

  return ChatStream(run(), () => cancelled = true);
}

// ------------------------------------------------------------------ Helpers

Future<http.StreamedResponse> _post(
  http.Client client,
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> body,
) {
  final req = http.Request('POST', uri)
    ..headers.addAll(headers)
    ..body = jsonEncode(body);
  return client.send(req);
}

Future<void> _ensureOk(ModelProvider provider, http.StreamedResponse res) async {
  if (res.statusCode == 200) return;
  final body = await res.stream.bytesToString();
  throw LlmException(_describeError(provider, res.statusCode, body));
}

/// Decodes a server-sent-event response into its JSON `data:` payloads.
Stream<Map<String, dynamic>> _sse(http.StreamedResponse res) async* {
  final lines = res.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    if (!line.startsWith('data:')) continue;
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') continue;
    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic>) yield json;
    } on FormatException {
      // A keep-alive or partial line; nothing to show for it.
    }
  }
}

/// Turns transport failures into something a person can act on.
Stream<Chunk> _guard(
  Stream<Chunk> source,
  ModelProvider provider,
  http.Client client,
) async* {
  try {
    yield* source;
  } on http.ClientException {
    throw LlmException(_unreachable(provider));
  } finally {
    client.close();
  }
}

String _unreachable(ModelProvider p) =>
    'Couldn\'t reach ${p.host}. Check your connection. If you opened this '
    'app inside an embedded preview, outbound requests are blocked there: '
    'use the Demo line, or open the hosted build.';

String _describeError(ModelProvider p, int status, String body) {
  String? detail;
  try {
    final json = jsonDecode(body);
    final err = json is List && json.isNotEmpty ? json.first : json;
    if (err is Map) {
      final e = err['error'];
      detail = e is Map
          ? e['message']?.toString()
          : (e ?? err['message'] ?? err['detail'])?.toString();
    }
  } on FormatException {
    // Not JSON; fall through to the raw body.
  }
  detail ??= body.trim();
  if (detail.length > 400) detail = '${detail.substring(0, 400)}…';
  final lead = switch (status) {
    401 || 403 =>
      '${p.maker} rejected this key ($status). Check it on the Keys screen.',
    404 =>
      '${p.maker} doesn\'t recognise this model or endpoint (404). '
          'Pick another model on the Keys screen.',
    429 =>
      '${p.maker} is rate-limiting this key or it is out of credit (429). '
          'Wait a moment, or check billing.',
    >= 500 => '${p.maker} is having trouble right now ($status). Try again.',
    _ => '${p.maker} refused the request ($status).',
  };
  return detail.isEmpty ? lead : '$lead\n$detail';
}
