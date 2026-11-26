import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_starter_flutter/src/debug/isolates/size/page_resources.dart';

/// The browser's Resource Timing, when it has it; `null` in a runtime
/// without it.
///
/// Made when the size block first shows: it raises the browser's buffer
/// of resource entries ([_buffer]), so the downloads from then on are
/// kept; those dropped before (a debug build loads more scripts than the
/// default 250 before the app starts) stay lost, and [PageResources.full]
/// says so.
PageResources? pageResources() => _pageResources ??= _open();

PageResources? _pageResources;

const _defaultBuffer = 250;
const _buffer = 4000;

PageResources? _open() {
  try {
    if (!globalContext.has('performance') ||
        !globalContext.has('PerformanceResourceTiming')) {
      return null;
    }
    final performance = globalContext.getProperty<_Performance>(
      'performance'.toJS,
    );
    if (!performance.has('getEntriesByType')) {
      return null;
    }
    final dropped =
        performance.getEntriesByType('resource'.toJS).length >= _defaultBuffer;
    if (performance.has('setResourceTimingBufferSize')) {
      performance.setResourceTimingBufferSize(_buffer);
    }
    return _BrowserPageResources(performance, dropped);
  } on Object {
    return null;
  }
}

final class _BrowserPageResources implements PageResources {
  _BrowserPageResources(this._performance, this._dropped);

  final _Performance _performance;
  final bool _dropped;
  var _count = 0;

  @override
  bool get full => _dropped || _count >= _buffer;

  @override
  List<PageResource> read() {
    final origin = _originOf(Uri.base.toString());
    final entries = [
      ..._performance.getEntriesByType('navigation'.toJS).toDart,
      ..._performance.getEntriesByType('resource'.toJS).toDart,
    ];
    _count = entries.length;
    return [
      for (final entry in entries)
        PageResource(
          name: PageResource.masked(entry.name),
          initiator: entry.initiatorType ?? '',
          transferSize: (entry.transferSize ?? 0).toInt(),
          decodedBodySize: (entry.decodedBodySize ?? 0).toInt(),
          crossOrigin: _originOf(entry.name) != origin,
        ),
    ];
  }

  static String? _originOf(String name) {
    try {
      return Uri.parse(name).origin;
    } on Object {
      return null;
    }
  }
}

extension type _Performance._(JSObject _) implements JSObject {
  external JSArray<_Entry> getEntriesByType(JSString type);
  external void setResourceTimingBufferSize(int size);
}

extension type _Entry._(JSObject _) implements JSObject {
  external String get name;
  external String? get initiatorType;
  external double? get transferSize;
  external double? get decodedBodySize;
}
