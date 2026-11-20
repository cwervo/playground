{{flutter_js}}
{{flutter_build_config}}

// Start the app without Flutter's own (deprecated, self-removing) service
// worker. Offline caching is handled by sw.js, registered in index.html.
_flutter.loader.load();
