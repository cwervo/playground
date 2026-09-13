// Dart models for the JSON display list produced by the C engine.

import 'dart:convert';
import 'dart:ui' show Color;

class PageModel {
  PageModel({
    required this.title,
    required this.base,
    required this.forms,
    required this.blocks,
    this.engine = '',
  });

  final String title;
  final String base;
  final List<FormModel> forms;
  final List<BlockModel> blocks;
  final String engine;

  factory PageModel.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PageModel(
      title: (map['title'] as String?) ?? '',
      base: (map['base'] as String?) ?? '',
      engine: (map['engine'] as String?) ?? '',
      forms: [
        for (final f in (map['forms'] as List? ?? const []))
          FormModel.fromMap(f as Map<String, dynamic>)
      ],
      blocks: [
        for (final b in (map['blocks'] as List? ?? const []))
          BlockModel.fromMap(b as Map<String, dynamic>)
      ],
    );
  }

  /// All text on the page, block per line (handy in tests).
  String get plainText =>
      blocks.map((b) => b.plainText).where((s) => s.isNotEmpty).join('\n');

  Iterable<RunModel> get links =>
      blocks.expand((b) => b.runs).where((r) => r.href != null);
}

class FormModel {
  FormModel({required this.action, required this.method});
  final String action;
  final String method;

  factory FormModel.fromMap(Map<String, dynamic> m) => FormModel(
        action: (m['action'] as String?) ?? '',
        method: (m['method'] as String?) ?? 'get',
      );
}

enum BlockAlign { left, center, right }

class BlockModel {
  BlockModel({
    required this.tag,
    required this.indent,
    required this.marginTop,
    required this.marginBottom,
    required this.align,
    required this.pre,
    required this.hr,
    required this.quote,
    required this.bg,
    required this.marker,
    required this.runs,
  });

  final String tag;
  final int indent;
  final int marginTop;
  final int marginBottom;
  final BlockAlign align;
  final bool pre;
  final bool hr;
  final bool quote;
  final Color? bg;
  final String? marker;
  final List<RunModel> runs;

  factory BlockModel.fromMap(Map<String, dynamic> m) => BlockModel(
        tag: (m['tag'] as String?) ?? 'div',
        indent: (m['indent'] as num?)?.toInt() ?? 0,
        marginTop: (m['mt'] as num?)?.toInt() ?? 0,
        marginBottom: (m['mb'] as num?)?.toInt() ?? 0,
        align: BlockAlign.values[((m['align'] as num?)?.toInt() ?? 0).clamp(0, 2)],
        pre: m['pre'] == true,
        hr: m['hr'] == true,
        quote: m['quote'] == true,
        bg: parseColor(m['bg'] as String?),
        marker: m['marker'] as String?,
        runs: [
          for (final r in (m['runs'] as List? ?? const []))
            RunModel.fromMap(r as Map<String, dynamic>)
        ],
      );

  bool get isHeading => tag.length == 2 && tag[0] == 'h' && '123456'.contains(tag[1]);

  /// True when nothing in this block draws pixels (only hidden fields).
  bool get isInvisible =>
      !hr && marker == null && runs.every((r) => r.kind == RunKind.control && r.ctl == 'hidden');

  String get plainText {
    final sb = StringBuffer();
    if (marker != null) sb.write('$marker ');
    for (final r in runs) {
      switch (r.kind) {
        case RunKind.text:
          sb.write(r.text);
        case RunKind.br:
          sb.write('\n');
        case RunKind.image:
          sb.write('[image: ${r.alt}]');
        case RunKind.control:
          if (r.ctl != 'hidden') sb.write('[${r.ctl}: ${r.label ?? r.placeholder ?? r.name ?? ''}]');
      }
    }
    return sb.toString().trim();
  }
}

enum RunKind { text, br, image, control }

class RunModel {
  RunModel({
    required this.kind,
    this.text = '',
    this.href,
    this.img,
    this.alt = '',
    this.width = 0,
    this.height = 0,
    this.ctl,
    this.name,
    this.value,
    this.label,
    this.placeholder,
    this.form = -1,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.size = 16,
    this.color,
    this.bg,
  });

  final RunKind kind;
  final String text;
  final String? href;
  final String? img;
  final String alt;
  final int width;
  final int height;
  final String? ctl;
  final String? name;
  final String? value;
  final String? label;
  final String? placeholder;
  final int form;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool mono;
  final int size;
  final Color? color;
  final Color? bg;

  factory RunModel.fromMap(Map<String, dynamic> m) {
    RunKind kind;
    if (m['br'] == true) {
      kind = RunKind.br;
    } else if (m.containsKey('img')) {
      kind = RunKind.image;
    } else if (m.containsKey('ctl')) {
      kind = RunKind.control;
    } else {
      kind = RunKind.text;
    }
    return RunModel(
      kind: kind,
      text: (m['t'] as String?) ?? '',
      href: m['href'] as String?,
      img: m['img'] as String?,
      alt: (m['alt'] as String?) ?? '',
      width: (m['w'] as num?)?.toInt() ?? 0,
      height: (m['h'] as num?)?.toInt() ?? 0,
      ctl: m['ctl'] as String?,
      name: m['name'] as String?,
      value: m['value'] as String?,
      label: m['label'] as String?,
      placeholder: m['placeholder'] as String?,
      form: (m['form'] as num?)?.toInt() ?? -1,
      bold: m['b'] == 1,
      italic: m['i'] == 1,
      underline: m['u'] == 1,
      strike: m['s'] == 1,
      mono: m['mono'] == 1,
      size: (m['size'] as num?)?.toInt() ?? 16,
      color: parseColor(m['color'] as String?),
      bg: parseColor(m['bg'] as String?),
    );
  }

  bool get isButton => ctl == 'submit' || ctl == 'button' || ctl == 'reset';
  bool get isTextField =>
      ctl == 'text' ||
      ctl == 'password' ||
      ctl == 'search' ||
      ctl == 'email' ||
      ctl == 'url' ||
      ctl == 'tel' ||
      ctl == 'number' ||
      ctl == 'date' ||
      ctl == 'textarea';
}

Color? parseColor(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}
