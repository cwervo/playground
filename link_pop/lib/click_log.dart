import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved link click.
class LinkClick {
  LinkClick({
    required this.id,
    required this.label,
    required this.url,
    required this.at,
    this.synced = false,
  });

  /// Stable across retries so the server can de-duplicate uploads.
  final String id;
  final String label;
  final String url;
  final DateTime at;

  /// True once the server has accepted this click.
  final bool synced;

  LinkClick copyWith({bool? synced}) => LinkClick(
      id: id, label: label, url: url, at: at, synced: synced ?? this.synced);

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'at': at.toIso8601String(),
        'synced': synced,
      };

  factory LinkClick.fromJson(Map<String, dynamic> json) {
    final at = DateTime.parse(json['at'] as String);
    return LinkClick(
      // Clicks saved before sync existed have no id; derive a stable one.
      id: json['id'] as String? ?? 'legacy-${at.microsecondsSinceEpoch}',
      label: json['label'] as String,
      url: json['url'] as String,
      at: at,
      synced: json['synced'] as bool? ?? false,
    );
  }
}

/// Every link click, newest first, persisted with shared_preferences.
///
/// This is the source of truth: clicks are saved here first and uploaded
/// later (see PopSync), so nothing waits on the network.
class ClickLog extends ChangeNotifier {
  static const _key = 'link_pop.clicks';
  static final _random = Random();

  final List<LinkClick> _clicks = [];

  List<LinkClick> get clicks => List.unmodifiable(_clicks);
  int get total => _clicks.length;

  /// Clicks the server hasn't accepted yet, oldest first.
  List<LinkClick> get pending =>
      _clicks.reversed.where((c) => !c.synced).toList();

  int countFor(String url) => _clicks.where((c) => c.url == url).length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    _clicks.clear();
    for (final s in raw) {
      // One corrupt entry shouldn't take the whole app down at startup.
      try {
        _clicks.add(LinkClick.fromJson(jsonDecode(s)));
      } catch (e) {
        debugPrint('Skipping unreadable saved click: $e');
      }
    }
    notifyListeners();
  }

  Future<LinkClick> record(String label, String url) async {
    final now = DateTime.now();
    final click = LinkClick(
      // Not `1 << 32`: on web that shift wraps to 0 and nextInt throws.
      id: '${now.microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff).toRadixString(16)}',
      label: label,
      url: url,
      at: now,
    );
    _clicks.insert(0, click);
    notifyListeners();
    await _save();
    return click;
  }

  /// Marks [ids] as uploaded. Ids that were cleared meanwhile are ignored.
  Future<void> markSynced(Set<String> ids) async {
    var changed = false;
    for (var i = 0; i < _clicks.length; i++) {
      if (!_clicks[i].synced && ids.contains(_clicks[i].id)) {
        _clicks[i] = _clicks[i].copyWith(synced: true);
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _clicks.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, _clicks.map((c) => jsonEncode(c.toJson())).toList());
  }
}
