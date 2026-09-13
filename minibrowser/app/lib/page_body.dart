// Paints a PageModel: the C engine decided what the blocks and inline runs
// are; Flutter does the real text layout, wrapping and painting.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'render_tree.dart';

typedef NavigateFn = void Function(Uri url);
typedef SubmitFn = void Function(FormModel form, Map<String, String> fields);

class PageBody extends StatefulWidget {
  const PageBody({
    super.key,
    required this.page,
    required this.onNavigate,
    required this.onSubmit,
    this.loadImages = true,
    this.controller,
  });

  final PageModel page;
  final NavigateFn onNavigate;
  final SubmitFn onSubmit;
  final bool loadImages;
  final ScrollController? controller;

  @override
  State<PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<PageBody> {
  // block index -> recognizers created for that block's links
  final Map<int, List<TapGestureRecognizer>> _recognizers = {};
  // form index -> field name -> value
  final Map<int, Map<String, String>> _fields = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(covariant PageBody old) {
    super.didUpdateWidget(old);
    if (!identical(old.page, widget.page)) {
      _disposeRecognizers();
      _fields.clear();
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _disposeRecognizers([int? block]) {
    if (block != null) {
      for (final r in _recognizers.remove(block) ?? const <TapGestureRecognizer>[]) {
        r.dispose();
      }
      return;
    }
    for (final list in _recognizers.values) {
      for (final r in list) {
        r.dispose();
      }
    }
    _recognizers.clear();
  }

  void _setField(RunModel r, String value) {
    if (r.form < 0 || r.name == null || r.name!.isEmpty) return;
    _fields.putIfAbsent(r.form, () => {})[r.name!] = value;
  }

  void _submit(int formIndex, {RunModel? button}) {
    if (formIndex < 0 || formIndex >= widget.page.forms.length) return;
    final fields = <String, String>{..._fields[formIndex] ?? const {}};
    // a clicked submit button contributes its name=value pair
    if (button != null && button.name != null && button.name!.isNotEmpty) {
      fields[button.name!] = button.value ?? '';
    }
    widget.onSubmit(widget.page.forms[formIndex], fields);
  }

  TextEditingController _controllerFor(RunModel r, String key) {
    return _controllers.putIfAbsent(key, () {
      final c = TextEditingController(text: r.value ?? '');
      _setField(r, r.value ?? '');
      c.addListener(() => _setField(r, c.text));
      return c;
    });
  }

  @override
  Widget build(BuildContext context) {
    // seed hidden fields
    for (final b in widget.page.blocks) {
      for (final r in b.runs) {
        if (r.kind == RunKind.control && r.ctl == 'hidden') _setField(r, r.value ?? '');
      }
    }
    final blocks = widget.page.blocks;
    return SelectionArea(
      child: ListView.builder(
        controller: widget.controller,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: blocks.length,
        itemBuilder: (context, i) => _buildBlock(context, blocks[i], i),
      ),
    );
  }

  Widget _buildBlock(BuildContext context, BlockModel b, int index) {
    _disposeRecognizers(index);
    if (b.isInvisible) return const SizedBox.shrink();
    if (b.hr) {
      return Padding(
        padding: EdgeInsets.only(left: b.indent.toDouble(), top: 8, bottom: 8),
        child: const Divider(height: 1),
      );
    }
    final spans = <InlineSpan>[];
    for (var j = 0; j < b.runs.length; j++) {
      final r = b.runs[j];
      switch (r.kind) {
        case RunKind.text:
          spans.add(_textSpan(r, b, index));
        case RunKind.br:
          spans.add(const TextSpan(text: '\n'));
        case RunKind.image:
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _image(r),
          ));
        case RunKind.control:
          if (r.ctl == 'hidden') break;
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: _control(r, index, j),
            ),
          ));
      }
    }
    final textAlign = switch (b.align) {
      BlockAlign.left => TextAlign.start,
      BlockAlign.center => TextAlign.center,
      BlockAlign.right => TextAlign.end,
    };
    Widget text = Text.rich(
      TextSpan(children: spans),
      textAlign: b.marker != null ? TextAlign.start : textAlign,
      softWrap: !b.pre,
      style: b.pre ? const TextStyle(fontFamily: 'monospace', fontSize: 13) : null,
    );
    if (b.pre) {
      text = SingleChildScrollView(scrollDirection: Axis.horizontal, child: text);
    }
    if (b.marker != null) {
      text = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(b.marker!, textAlign: TextAlign.right, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 6),
          Expanded(child: text),
        ],
      );
    }
    if (b.quote) {
      text = Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Theme.of(context).dividerColor, width: 3)),
        ),
        padding: const EdgeInsets.only(left: 10),
        child: text,
      );
    }
    if (b.bg != null) {
      text = ColoredBox(color: b.bg!, child: text);
    }
    // Margins collapse like CSS: use the larger of bottom(prev) / top(this).
    final prevMb = index > 0 ? widget.page.blocks[index - 1].marginBottom : 0;
    final top = b.marginTop > prevMb ? b.marginTop - prevMb : 0;
    return Padding(
      padding: EdgeInsets.only(
        left: (b.indent - (b.marker != null ? 24 : 0)).clamp(0, 400).toDouble(),
        top: top.toDouble(),
        bottom: b.marginBottom.toDouble(),
      ),
      // list items keep their bullet on the left whatever the alignment
      child: b.marker != null
          ? text
          : Align(
              alignment: switch (b.align) {
                BlockAlign.left => Alignment.centerLeft,
                BlockAlign.center => Alignment.center,
                BlockAlign.right => Alignment.centerRight,
              },
              child: text,
            ),
    );
  }

  TextSpan _textSpan(RunModel r, BlockModel b, int blockIndex) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final isLink = r.href != null;
    var style = base.copyWith(
      fontSize: r.size.toDouble(),
      fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
      fontFamily: r.mono ? 'monospace' : null,
      color: r.color ?? (isLink ? const Color(0xFF1A0DAB) : base.color),
      backgroundColor: r.bg,
      height: 1.35,
      decoration: TextDecoration.combine([
        if (r.underline) TextDecoration.underline,
        if (r.strike) TextDecoration.lineThrough,
      ]),
    );
    if (b.pre) style = style.copyWith(fontFamily: 'monospace');
    TapGestureRecognizer? rec;
    if (isLink) {
      final target = Uri.tryParse(r.href!);
      if (target != null) {
        rec = TapGestureRecognizer()..onTap = () => widget.onNavigate(target);
        _recognizers.putIfAbsent(blockIndex, () => []).add(rec);
      }
    }
    return TextSpan(text: r.text, style: style, recognizer: rec);
  }

  Widget _image(RunModel r) {
    final w = r.width > 0 ? r.width.toDouble().clamp(1, 1200).toDouble() : null;
    final h = r.height > 0 ? r.height.toDouble().clamp(1, 1200).toDouble() : null;
    final maxW = (w ?? 320).clamp(24.0, 1200.0);
    final maxH = (h ?? 240).clamp(24.0, 1200.0);
    Widget placeholder = Container(
      constraints: BoxConstraints(minWidth: 24, minHeight: 24, maxWidth: maxW, maxHeight: maxH),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        color: const Color(0xFFF3F3F3),
      ),
      child: Text(
        r.alt.isEmpty ? '[image]' : r.alt,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
    if (!widget.loadImages || r.img == null) return placeholder;
    return Image.network(
      r.img!,
      width: w,
      height: h,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  Widget _control(RunModel r, int blockIndex, int runIndex) {
    final key = 'f${r.form}:${r.name ?? ''}:$blockIndex:$runIndex';
    if (r.isButton) {
      return FilledButton.tonal(
        onPressed: r.ctl == 'submit' ? () => _submit(r.form, button: r) : null,
        child: Text(r.label ?? r.value ?? 'Submit'),
      );
    }
    if (r.isTextField) {
      final controller = _controllerFor(r, key);
      final multiline = r.ctl == 'textarea';
      return SizedBox(
        width: multiline ? 360 : 260,
        child: TextField(
          controller: controller,
          obscureText: r.ctl == 'password',
          maxLines: multiline ? 4 : 1,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _submit(r.form),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: r.placeholder,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      );
    }
    if (r.ctl == 'checkbox' || r.ctl == 'radio') {
      final checked = _fields[r.form]?[r.name ?? ''] != null;
      return StatefulBuilder(builder: (context, setLocal) {
        return Checkbox(
          value: checked,
          onChanged: (v) {
            if (v == true) {
              _setField(r, r.value ?? 'on');
            } else {
              _fields[r.form]?.remove(r.name);
            }
            setLocal(() {});
          },
        );
      });
    }
    if (r.ctl == 'select') {
      final options = (r.placeholder ?? '').split('\n').where((o) => o.isNotEmpty).toList();
      if (options.isEmpty) return const SizedBox.shrink();
      var current = r.label != null && options.contains(r.label) ? r.label! : options.first;
      _setField(r, current);
      return StatefulBuilder(builder: (context, setLocal) {
        return DropdownButton<String>(
          value: current,
          isDense: true,
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) {
            if (v == null) return;
            current = v;
            _setField(r, v);
            setLocal(() {});
          },
        );
      });
    }
    return Text('[${r.ctl}]', style: const TextStyle(color: Colors.black45));
  }
}
