// minibrowser — a mini web browser whose page engine is a single portable C
// file (engine/minibrowser.c) loaded over dart:ffi. Flutter draws the chrome
// and paints the display list the engine produces.

import 'dart:io';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'fetcher.dart';
import 'page_body.dart';
import 'render_tree.dart';

void main(List<String> args) {
  // `minibrowser https://example.com/` or MINIBROWSER_URL=... opens that page.
  final initial = args.isNotEmpty ? args.first : Platform.environment['MINIBROWSER_URL'];
  runApp(MiniBrowserApp(initialUrl: initial));
}

class MiniBrowserApp extends StatelessWidget {
  const MiniBrowserApp({super.key, this.fetch, this.initialUrl, this.loadImages = true});

  final FetchFn? fetch;
  final String? initialUrl;
  final bool loadImages;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'minibrowser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3366CC),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: BrowserScreen(fetch: fetch, initialUrl: initialUrl, loadImages: loadImages),
    );
  }
}

/// The built-in start page, rendered through the engine like any other page.
const String kStartPageHtml = '''
<!doctype html><html><head><title>minibrowser</title></head><body>
<center><h1>minibrowser</h1>
<p>A tiny browser. The page engine is one portable C file; Flutter paints it.</p>
<p><a href="https://www.google.com/">Google</a> &middot;
<a href="https://www.facebook.com/">Facebook</a> &middot;
<a href="https://www.apple.com/">Apple</a> &middot;
<a href="https://en.wikipedia.org/wiki/Main_Page">Wikipedia</a></p>
<form action="https://www.google.com/search" method="get">
<input name="q" placeholder="Search the web"> <input type="submit" value="Search">
</form>
<p><small>No JavaScript, no CSS beyond the basics, no tracking.</small></p></center>
</body></html>
''';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.fetch, this.initialUrl, this.loadImages = true});

  final FetchFn? fetch;
  final String? initialUrl;
  final bool loadImages;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final FetchFn _fetch;
  Fetcher? _ownFetcher;
  final _urlController = TextEditingController();
  final _scroll = ScrollController();
  final List<Uri> _history = [];
  int _historyIndex = -1;
  PageModel? _page;
  String? _error;
  bool _loading = false;
  String _engineVersion = '';
  int _loadSeq = 0;
  bool _textMode = false;
  String? _rawHtml;

  static final Uri _startUri = Uri.parse('about:start');

  @override
  void initState() {
    super.initState();
    if (widget.fetch != null) {
      _fetch = widget.fetch!;
    } else {
      _ownFetcher = Fetcher();
      _fetch = _ownFetcher!.fetch;
    }
    try {
      _engineVersion = Engine.load().version;
    } catch (e) {
      _error = e.toString();
    }
    final initial = widget.initialUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigate(initial != null ? _parseUserUrl(initial) : _startUri);
    });
  }

  @override
  void dispose() {
    _ownFetcher?.close();
    _urlController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  Uri _parseUserUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return _startUri;
    if (text == 'about:start' || text == 'about:blank') return _startUri;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(text)) {
      if (text.contains(' ') || !text.contains('.')) {
        return Uri.https('www.google.com', '/search', {'q': text});
      }
      text = 'https://$text';
    }
    return Uri.parse(text);
  }

  /// Loads [url] and pushes it on the history stack.
  Future<void> navigate(Uri url) async {
    // drop forward history
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(url);
    _historyIndex = _history.length - 1;
    await _load(url);
  }

  Future<void> _load(Uri url, {String method = 'GET', Map<String, String>? form}) async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
      _urlController.text = url.toString();
    });
    try {
      final Engine engine = Engine.load();
      String html;
      Uri finalUrl = url;
      if (url == _startUri) {
        html = kStartPageHtml;
      } else {
        final res = await _fetch(url, method: method, form: form);
        finalUrl = res.url;
        html = res.isHtml
            ? res.body
            : '<pre>${_escape(res.body)}</pre>';
        if (res.status >= 400 && res.body.trim().isEmpty) {
          html = '<h1>HTTP ${res.status}</h1><p>The server returned an error for ${_escape(url.toString())}.</p>';
        }
      }
      if (seq != _loadSeq) return; // superseded by a newer navigation
      final json = engine.renderJson(html, finalUrl == _startUri ? '' : finalUrl.toString());
      final page = PageModel.fromJson(json);
      if (!mounted) return;
      setState(() {
        _page = page;
        _rawHtml = html;
        _loading = false;
        _history[_historyIndex] = finalUrl;
        _urlController.text = finalUrl == _startUri ? 'about:start' : finalUrl.toString();
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _page = null;
      });
    }
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  void _goBack() {
    if (!canGoBack) return;
    _historyIndex--;
    _load(_history[_historyIndex]);
  }

  void _goForward() {
    if (!canGoForward) return;
    _historyIndex++;
    _load(_history[_historyIndex]);
  }

  void _reload() {
    if (_historyIndex >= 0) _load(_history[_historyIndex]);
  }

  void _submitForm(FormModel form, Map<String, String> fields) {
    final action = Uri.tryParse(form.action);
    if (action == null) return;
    final method = form.method.toUpperCase() == 'POST' ? 'POST' : 'GET';
    final target = method == 'GET'
        ? action.replace(queryParameters: {...action.queryParameters, ...fields})
        : action;
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(target);
    _historyIndex = _history.length - 1;
    _load(target, method: method, form: method == 'POST' ? fields : null);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final title = page == null || page.title.isEmpty ? 'minibrowser' : page.title;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: canGoBack ? _goBack : null,
            ),
            IconButton(
              tooltip: 'Forward',
              icon: const Icon(Icons.arrow_forward),
              onPressed: canGoForward ? _goForward : null,
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => navigate(_startUri),
            ),
            Expanded(
              child: TextField(
                key: const Key('urlField'),
                controller: _urlController,
                textInputAction: TextInputAction.go,
                onSubmitted: (v) => navigate(_parseUserUrl(v)),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Enter a URL or search',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            IconButton(
              tooltip: _textMode ? 'Show rendered page' : 'Show as text',
              icon: Icon(_textMode ? Icons.article_outlined : Icons.text_snippet_outlined),
              onPressed: () => setState(() => _textMode = !_textMode),
            ),
            const SizedBox(width: 8),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _loading ? const LinearProgressIndicator(minHeight: 3) : const SizedBox(height: 3),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(page)),
          _statusBar(title),
        ],
      ),
    );
  }

  Widget _body(PageModel? page) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText('Could not load page.\n\n$_error',
              key: const Key('errorText'), textAlign: TextAlign.center),
        ),
      );
    }
    if (page == null) return const SizedBox.shrink();
    if (_textMode) {
      final text = Engine.load().renderText(_rawHtml ?? '', page.base, width: 100);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      );
    }
    return PageBody(
      page: page,
      controller: _scroll,
      loadImages: widget.loadImages,
      onNavigate: navigate,
      onSubmit: _submitForm,
    );
  }

  Widget _statusBar(String title) {
    final links = _page?.links.length ?? 0;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              key: const Key('statusTitle'),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$links links · engine ${_engineVersion.isEmpty ? 'missing' : _engineVersion}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
