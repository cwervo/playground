// dart:ffi binding to the portable C engine (engine/minibrowser.c).
//
// The engine is a single C file compiled by the top-level Makefile into
// o/<host>-<arch>/libminibrowser.{so,dylib,dll}. It parses HTML, applies a
// built-in stylesheet and returns a JSON display list; this file only
// marshals strings across the boundary.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _RenderJsonC = Pointer<Utf8> Function(
    Pointer<Utf8> html, Size len, Pointer<Utf8> base);
typedef _RenderJsonDart = Pointer<Utf8> Function(
    Pointer<Utf8> html, int len, Pointer<Utf8> base);
typedef _RenderTextC = Pointer<Utf8> Function(
    Pointer<Utf8> html, Size len, Pointer<Utf8> base, Int32 width, Int32 links);
typedef _RenderTextDart = Pointer<Utf8> Function(
    Pointer<Utf8> html, int len, Pointer<Utf8> base, int width, int links);
typedef _ResolveC = Pointer<Utf8> Function(Pointer<Utf8> base, Pointer<Utf8> ref);
typedef _ResolveDart = Pointer<Utf8> Function(Pointer<Utf8> base, Pointer<Utf8> ref);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

class EngineNotFound implements Exception {
  EngineNotFound(this.searched);
  final List<String> searched;
  @override
  String toString() =>
      'minibrowser engine library not found. Build it with `make` at the '
      'repository root or point MINIBROWSER_ENGINE at it. Looked in:\n  '
      '${searched.join('\n  ')}';
}

class Engine {
  Engine._(DynamicLibrary lib)
      : _renderJson =
            lib.lookupFunction<_RenderJsonC, _RenderJsonDart>('mb_render_json'),
        _renderText =
            lib.lookupFunction<_RenderTextC, _RenderTextDart>('mb_render_text'),
        _resolve = lib.lookupFunction<_ResolveC, _ResolveDart>('mb_resolve_url'),
        _free = lib.lookupFunction<_FreeC, _FreeDart>('mb_free'),
        _version = lib.lookupFunction<_VersionC, _VersionDart>('mb_version');

  final _RenderJsonDart _renderJson;
  final _RenderTextDart _renderText;
  final _ResolveDart _resolve;
  final _FreeDart _free;
  final _VersionDart _version;

  static Engine? _instance;

  /// Loads the engine once and caches it.
  static Engine load() => _instance ??= Engine._(_open());

  /// Library file name for this platform.
  static String get libraryFileName {
    if (Platform.isWindows) return 'minibrowser.dll';
    if (Platform.isMacOS || Platform.isIOS) return 'libminibrowser.dylib';
    return 'libminibrowser.so';
  }

  /// `linux-x64`, `macos-arm64`, ... matching the Makefile's output folder.
  static String get hostArch {
    final abi = Abi.current().toString(); // e.g. linux_x64
    final parts = abi.split('_');
    final os = parts.first;
    final arch = parts.length > 1 ? parts[1] : 'x64';
    return '$os-$arch';
  }

  /// Every location we look for the engine, in order.
  static List<String> candidates() {
    final name = libraryFileName;
    final out = <String>[];
    final env = Platform.environment['MINIBROWSER_ENGINE'];
    if (env != null && env.isNotEmpty) out.add(env);
    final exeDir = p.dirname(Platform.resolvedExecutable);
    // bundled next to the app (make app copies it here)
    out.add(p.join(exeDir, 'lib', name));
    out.add(p.join(exeDir, name));
    out.add(p.join(exeDir, '..', 'Frameworks', name)); // macOS .app
    // development: walk up from the working directory to find o/<host>/
    var dir = Directory.current.path;
    for (var i = 0; i < 4; i++) {
      out.add(p.join(dir, 'o', hostArch, name));
      dir = p.dirname(dir);
    }
    out.add(name); // system loader path
    return out;
  }

  static DynamicLibrary _open() {
    final tried = <String>[];
    for (final path in candidates()) {
      tried.add(path);
      if (path != libraryFileName && !File(path).existsSync()) continue;
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // try the next one
      }
    }
    throw EngineNotFound(tried);
  }

  String get version => _version().toDartString();

  /// Parses and lays out [html]; returns the JSON display list.
  String renderJson(String html, String baseUrl) {
    final bytes = utf8.encode(html);
    final buf = malloc<Uint8>(bytes.length + 1);
    buf.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    final base = baseUrl.toNativeUtf8();
    try {
      final out = _renderJson(buf.cast(), bytes.length, base);
      try {
        return out.toDartString();
      } finally {
        _free(out.cast());
      }
    } finally {
      malloc.free(buf);
      malloc.free(base);
    }
  }

  /// Renders [html] as wrapped plain text (used by the "view as text" mode).
  String renderText(String html, String baseUrl, {int width = 80, bool links = true}) {
    final bytes = utf8.encode(html);
    final buf = malloc<Uint8>(bytes.length + 1);
    buf.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    final base = baseUrl.toNativeUtf8();
    try {
      final out = _renderText(buf.cast(), bytes.length, base, width, links ? 1 : 0);
      try {
        return out.toDartString();
      } finally {
        _free(out.cast());
      }
    } finally {
      malloc.free(buf);
      malloc.free(base);
    }
  }

  /// Resolves [ref] against [base] with the engine's URL resolver.
  String resolve(String base, String ref) {
    final b = base.toNativeUtf8();
    final r = ref.toNativeUtf8();
    try {
      final out = _resolve(b, r);
      try {
        return out.toDartString();
      } finally {
        _free(out.cast());
      }
    } finally {
      malloc.free(b);
      malloc.free(r);
    }
  }
}
