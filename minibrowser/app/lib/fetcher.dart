// Page fetching for the Flutter shell.
//
// The C engine has its own HTTP client (used by the CLI), but the shared
// library is built without TLS so the app fetches with dart:io, which has
// the platform's certificate store, gzip and redirects for free.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FetchResult {
  FetchResult({
    required this.url,
    required this.status,
    required this.contentType,
    required this.body,
  });

  final Uri url; // final URL after redirects
  final int status;
  final String contentType;
  final String body;

  bool get isHtml =>
      contentType.contains('html') || contentType.contains('xml') || contentType.isEmpty;
}

/// Signature shared by the real fetcher and test doubles.
typedef FetchFn = Future<FetchResult> Function(
  Uri url, {
  String method,
  Map<String, String>? form,
});

class Fetcher {
  Fetcher({HttpClient? client})
      : _client = client ??
            (HttpClient()
              ..userAgent = 'Mozilla/5.0 (compatible; minibrowser/0.1; +flutter)'
              ..autoUncompress = true
              ..connectionTimeout = const Duration(seconds: 20)
              ..maxConnectionsPerHost = 6);

  final HttpClient _client;

  Future<FetchResult> fetch(
    Uri url, {
    String method = 'GET',
    Map<String, String>? form,
  }) async {
    if (url.scheme == 'file') {
      final text = await File(url.toFilePath()).readAsString();
      return FetchResult(url: url, status: 200, contentType: 'text/html', body: text);
    }
    if (url.scheme == 'about') {
      return FetchResult(url: url, status: 200, contentType: 'text/html', body: '');
    }
    var target = url;
    if (method == 'GET' && form != null) {
      target = url.replace(queryParameters: {...url.queryParameters, ...form});
      form = null;
    }
    final req = await _client.openUrl(method, target);
    req.followRedirects = true;
    req.maxRedirects = 10;
    req.headers.set(HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'en');
    if (form != null) {
      final encoded = form.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write(encoded);
    }
    final res = await req.close();
    final bytes = await _collect(res);
    final ctype = res.headers.contentType;
    final charset = (ctype?.charset ?? _sniffCharset(bytes)).toLowerCase();
    final body = _decode(bytes, charset);
    final finalUrl = res.redirects.isNotEmpty ? res.redirects.last.location : target;
    return FetchResult(
      url: finalUrl.hasScheme ? finalUrl : target.resolveUri(finalUrl),
      status: res.statusCode,
      contentType: ctype?.mimeType ?? '',
      body: body,
    );
  }

  static Future<Uint8List> _collect(HttpClientResponse res) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Looks for <meta charset=...> in the first few KB.
  static String _sniffCharset(Uint8List bytes) {
    final head = latin1.decode(bytes.sublist(0, bytes.length < 4096 ? bytes.length : 4096));
    final m = RegExp(r'charset\s*=\s*["]?([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(head);
    return m?.group(1) ?? 'utf-8';
  }

  static String _decode(Uint8List bytes, String charset) {
    switch (charset) {
      case 'iso-8859-1':
      case 'latin1':
      case 'windows-1252':
      case 'cp1252':
        return latin1.decode(bytes);
      case 'us-ascii':
      case 'ascii':
        return ascii.decode(bytes, allowInvalid: true);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  void close() => _client.close(force: true);
}
