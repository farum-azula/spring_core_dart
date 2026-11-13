import 'dart:js_interop';

@JS('crossOriginIsolated')
external bool? get _crossOriginIsolated;

/// Whether the web page is cross-origin isolated, so Flutter draws in a
/// worker and not on the page's thread; `null` off the web, where the
/// question does not arise.
bool? get pageIsolated => _crossOriginIsolated ?? false;
