import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_starter_flutter/src/debug/network/resource_timing.dart';

/// The browser's `performance`, when it has Resource Timing; `null` in a
/// runtime without it (a worker of an edge function, an old browser).
///
/// Made once, when the recorder wraps its first transport. While a
/// recorded request waits for its entry ([ResourceTimingSource.observe]),
/// a `PerformanceObserver` keeps the last [_kept] resource entries as they
/// come: the browser's own list stops at 250 entries (a debug build loads
/// more scripts than that before the app starts), an observer is told of
/// every one. It is disconnected, and what it kept dropped, once none
/// waits. Without an observer, the browser's list is read.
ResourceTimingSource? resourceTimingSource() {
  try {
    if (!globalContext.has('performance') ||
        !globalContext.has('PerformanceResourceTiming')) {
      return null;
    }
    final performance = globalContext.getProperty<_Performance>(
      'performance'.toJS,
    );
    if (!performance.has('getEntriesByName') || !performance.has('now')) {
      return null;
    }
    return _BrowserResourceTiming(performance);
  } on Object {
    return null;
  }
}

const _kept = 256;

final class _BrowserResourceTiming implements ResourceTimingSource {
  _BrowserResourceTiming(this._performance);

  final _Performance _performance;
  final _observed = ListQueue<_Entry>();
  _Observer? _observer;
  int _users = 0;

  @override
  void Function() observe() {
    if (_users++ == 0) {
      _connect();
    }
    var stopped = false;
    return () {
      if (stopped) {
        return;
      }
      stopped = true;
      if (--_users == 0) {
        _disconnect();
      }
    };
  }

  void _connect() {
    try {
      if (!globalContext.has('PerformanceObserver')) {
        return;
      }
      _observer = _Observer(
        ((_EntryList list, JSAny? _) {
          for (final entry in list.getEntries().toDart) {
            if (_observed.length >= _kept) {
              _observed.removeFirst();
            }
            _observed.addLast(entry);
          }
        }).toJS,
      )..observe(_ObserveOptions(type: 'resource'.toJS));
    } on Object {
      // No observer: the browser's own list is read.
    }
  }

  void _disconnect() {
    try {
      _observer?.disconnect();
    } on Object {
      // Gone with the page.
    }
    _observer = null;
    _observed.clear();
  }

  @override
  double now() => _performance.now();

  @override
  Iterable<ResourceTimingEntry> entriesNamed(String name) {
    final found = <double, _Entry>{
      for (final entry in _listed(name)) entry.startTime: entry,
      for (final entry in _observed)
        if (entry.name == name) entry.startTime: entry,
    };
    final entries = found.values.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return [for (final entry in entries) _of(entry)];
  }

  List<_Entry> _listed(String name) {
    try {
      return _performance.getEntriesByName(name.toJS, 'resource'.toJS).toDart;
    } on Object {
      return const [];
    }
  }

  static ResourceTimingEntry _of(_Entry entry) => ResourceTimingEntry(
    startTime: entry.startTime,
    redirectStart: entry.redirectStart,
    redirectEnd: entry.redirectEnd,
    fetchStart: entry.fetchStart,
    domainLookupStart: entry.domainLookupStart,
    domainLookupEnd: entry.domainLookupEnd,
    connectStart: entry.connectStart,
    connectEnd: entry.connectEnd,
    secureConnectionStart: entry.secureConnectionStart,
    requestStart: entry.requestStart,
    responseStart: entry.responseStart,
    responseEnd: entry.responseEnd,
    nextHopProtocol: entry.nextHopProtocol ?? '',
  );
}

extension type _Performance._(JSObject _) implements JSObject {
  external double now();
  external JSArray<_Entry> getEntriesByName(JSString name, JSString type);
}

@JS('PerformanceObserver')
extension type _Observer._(JSObject _) implements JSObject {
  external factory _Observer(JSFunction callback);
  external void observe(_ObserveOptions options);
  external void disconnect();
}

extension type _ObserveOptions._(JSObject _) implements JSObject {
  external factory _ObserveOptions({JSString type});
}

extension type _EntryList._(JSObject _) implements JSObject {
  external JSArray<_Entry> getEntries();
}

extension type _Entry._(JSObject _) implements JSObject {
  external String get name;
  external double get startTime;
  external double get redirectStart;
  external double get redirectEnd;
  external double get fetchStart;
  external double get domainLookupStart;
  external double get domainLookupEnd;
  external double get connectStart;
  external double get connectEnd;
  external double get secureConnectionStart;
  external double get requestStart;
  external double get responseStart;
  external double get responseEnd;
  external String? get nextHopProtocol;
}
