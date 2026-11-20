import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'llm_client.dart';
import 'providers.dart';

/// One bubble in the transcript.
class Message {
  Message({
    required this.role,
    this.text = '',
    this.providerId,
    this.model,
    this.error,
    List<String>? notes,
  }) : notes = notes ?? [];

  /// `user`, `assistant`, or `note` (a local remark never sent to a model).
  final String role;
  String text;
  final String? providerId;
  final String? model;
  String? error;
  final List<String> notes;

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    if (providerId != null) 'providerId': providerId,
    if (model != null) 'model': model,
    if (error != null) 'error': error,
    if (notes.isNotEmpty) 'notes': notes,
  };

  static Message fromJson(Map<String, dynamic> j) => Message(
    role: j['role'] as String,
    text: j['text'] as String? ?? '',
    providerId: j['providerId'] as String?,
    model: j['model'] as String?,
    error: j['error'] as String?,
    notes: (j['notes'] as List?)?.cast<String>(),
  );
}

enum KeyCheck { unchecked, checking, ok, failed }

/// Everything the app remembers. Persisted in this browser only.
class AppStore extends ChangeNotifier {
  AppStore(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  final Map<String, String> _keys = {};
  final Map<String, String> _model = {};
  final Map<String, List<ModelInfo>> _models = {};
  final Map<String, KeyCheck> _check = {};
  final Map<String, String> _checkDetail = {};
  final List<Message> messages = [];
  String activeId = demoProvider.id;
  String system = '';

  ChatStream? _running;
  bool _stopped = false;
  bool get busy => _running != null;

  ModelProvider get active => providerById(activeId);

  String keyFor(String id) => _keys[id] ?? '';
  bool hasKey(String id) => id == demoProvider.id || keyFor(id).isNotEmpty;
  bool get hasAnyKey => providers.any((p) => keyFor(p.id).isNotEmpty);
  String modelFor(ModelProvider p) => _model[p.id] ?? p.defaultModel;
  List<ModelInfo> modelsFor(String id) => _models[id] ?? const [];
  KeyCheck checkFor(String id) => _check[id] ?? KeyCheck.unchecked;
  String checkDetail(String id) => _checkDetail[id] ?? '';

  // ------------------------------------------------------------ persistence

  void _load() {
    for (final p in providers) {
      final k = _prefs.getString('key.${p.id}');
      if (k != null && k.isNotEmpty) _keys[p.id] = k;
      final m = _prefs.getString('model.${p.id}');
      if (m != null && m.isNotEmpty) _model[p.id] = m;
      final list = _prefs.getString('models.${p.id}');
      if (list != null) {
        try {
          _models[p.id] = [
            for (final j in jsonDecode(list) as List)
              ModelInfo.fromJson(j as Map<String, dynamic>),
          ];
        } on Object {
          // A corrupt cache is only a cache; it is refetched on next check.
        }
      }
    }
    system = _prefs.getString('system') ?? '';
    final saved = _prefs.getString('active');
    if (saved != null && hasKey(saved)) {
      activeId = providerById(saved).id;
    } else {
      activeId = providers
          .firstWhere((p) => hasKey(p.id), orElse: () => demoProvider)
          .id;
    }
    final thread = _prefs.getString('thread');
    if (thread != null) {
      try {
        messages.addAll([
          for (final j in jsonDecode(thread) as List)
            Message.fromJson(j as Map<String, dynamic>),
        ]);
      } on Object {
        // Unreadable history is dropped rather than blocking startup.
      }
    }
  }

  void _saveThread() {
    _prefs.setString(
      'thread',
      jsonEncode([
        for (final m in messages)
          if (m.role != 'note') m.toJson(),
      ]),
    );
  }

  // ------------------------------------------------------------------- keys

  void setKey(String id, String value) {
    final key = value.trim();
    if (key == keyFor(id)) return;
    if (key.isEmpty) {
      _keys.remove(id);
      _prefs.remove('key.$id');
      _models.remove(id);
      _prefs.remove('models.$id');
      if (activeId == id) setActive(demoProvider.id);
    } else {
      final first = !hasAnyKey;
      _keys[id] = key;
      _prefs.setString('key.$id', key);
      // The first key added is almost certainly the one they want to use.
      if (first || activeId == demoProvider.id) setActive(id);
    }
    _check.remove(id);
    _checkDetail.remove(id);
    notifyListeners();
  }

  void setModel(String id, String model) {
    final m = model.trim();
    if (m.isEmpty) return;
    _model[id] = m;
    _prefs.setString('model.$id', m);
    notifyListeners();
  }

  void setActive(String id) {
    activeId = id;
    _prefs.setString('active', id);
    notifyListeners();
  }

  void setSystem(String value) {
    system = value.trim();
    _prefs.setString('system', system);
    notifyListeners();
  }

  /// Verifies a key by asking the provider which models it can use.
  Future<void> checkKey(String id) async {
    final p = providerById(id);
    final key = keyFor(id);
    if (key.isEmpty) return;
    _check[id] = KeyCheck.checking;
    notifyListeners();
    try {
      final list = await listModels(p, key);
      if (keyFor(id) != key) return; // Edited while we were waiting.
      _models[id] = list;
      _prefs.setString(
        'models.$id',
        jsonEncode([for (final m in list) m.toJson()]),
      );
      // Keep the chosen model if the account has it; otherwise pick the
      // closest thing the account does have.
      if (list.isNotEmpty && !list.any((m) => m.id == modelFor(p))) {
        ModelInfo? pick;
        for (final want in p.preferred) {
          pick = list.where((m) => m.id.contains(want)).firstOrNull;
          if (pick != null) break;
        }
        setModel(id, (pick ?? list.first).id);
      }
      _check[id] = KeyCheck.ok;
      _checkDetail[id] = list.length == 1
          ? 'Key works. 1 model available.'
          : 'Key works. ${list.length} models available.';
    } on LlmException catch (e) {
      _check[id] = KeyCheck.failed;
      _checkDetail[id] = e.message;
    } on Object catch (e) {
      _check[id] = KeyCheck.failed;
      _checkDetail[id] = 'Couldn\'t read the model list: $e';
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------- chat

  void addNote(String text) {
    messages.add(Message(role: 'note', text: text));
    notifyListeners();
  }

  void newChat() {
    stop();
    messages.clear();
    _saveThread();
    notifyListeners();
  }

  void stop() {
    if (_running == null) return;
    _stopped = true;
    _running!.cancel();
  }

  Future<void> send(String input) async {
    final text = input.trim();
    if (text.isEmpty || busy) return;
    final p = active;
    final model = modelFor(p);

    messages.add(Message(role: 'user', text: text));
    // What the model sees: every real turn so far, whoever answered it.
    final turns = [
      for (final m in messages)
        if (m.role != 'note' && m.text.trim().isNotEmpty) Turn(m.role, m.text),
    ];
    final reply = Message(role: 'assistant', providerId: p.id, model: model);
    messages.add(reply);

    final stream = streamChat(
      provider: p,
      apiKey: keyFor(p.id),
      model: model,
      turns: turns,
      system: system,
      maxOutput: modelsFor(
        p.id,
      ).where((m) => m.id == model).firstOrNull?.maxOutput,
    );
    _running = stream;
    _stopped = false;
    notifyListeners();

    try {
      await for (final chunk in stream.chunks) {
        if (chunk.text != null) reply.text += chunk.text!;
        if (chunk.note != null) reply.notes.add(chunk.note!);
        notifyListeners();
      }
    } on LlmException catch (e) {
      // Closing the connection on Stop surfaces as a transport error.
      if (!_stopped) reply.error = e.message;
    } on Object catch (e) {
      if (!_stopped) {
        reply.error = 'Something went wrong while reading the reply: $e';
      }
    } finally {
      if (_stopped) reply.notes.add('Stopped.');
      _running = null;
      _saveThread();
      notifyListeners();
    }
  }
}
