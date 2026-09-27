import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved link click.
class LinkClick {
  LinkClick({required this.label, required this.url, required this.at});

  final String label;
  final String url;
  final DateTime at;

  Map<String, Object> toJson() =>
      {'label': label, 'url': url, 'at': at.toIso8601String()};

  factory LinkClick.fromJson(Map<String, dynamic> json) => LinkClick(
        label: json['label'] as String,
        url: json['url'] as String,
        at: DateTime.parse(json['at'] as String),
      );
}

/// Every link click, newest first, persisted with shared_preferences.
class ClickLog extends ChangeNotifier {
  static const _key = 'link_pop.clicks';

  final List<LinkClick> _clicks = [];

  List<LinkClick> get clicks => List.unmodifiable(_clicks);
  int get total => _clicks.length;

  int countFor(String url) => _clicks.where((c) => c.url == url).length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    _clicks
      ..clear()
      ..addAll(raw.map((s) => LinkClick.fromJson(jsonDecode(s))));
    notifyListeners();
  }

  Future<LinkClick> record(String label, String url) async {
    final click = LinkClick(label: label, url: url, at: DateTime.now());
    _clicks.insert(0, click);
    notifyListeners();
    await _save();
    return click;
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
