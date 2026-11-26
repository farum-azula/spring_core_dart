import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/resource_timing_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter/src/debug/network/resource_timing_web.dart'
    as browser;

/// The browser's Resource Timing entry of one request
/// (`PerformanceResourceTiming`), its times in milliseconds from the
/// page's time origin. A time the browser hides is `0`: every phase of a
/// response from another origin without `Timing-Allow-Origin`.
final class ResourceTimingEntry {
  /// An entry of these times.
  const ResourceTimingEntry({
    required this.startTime,
    required this.responseEnd,
    this.redirectStart = 0,
    this.redirectEnd = 0,
    this.fetchStart = 0,
    this.domainLookupStart = 0,
    this.domainLookupEnd = 0,
    this.connectStart = 0,
    this.connectEnd = 0,
    this.secureConnectionStart = 0,
    this.requestStart = 0,
    this.responseStart = 0,
    this.nextHopProtocol = '',
  });

  /// When the request started.
  final double startTime;

  /// When the first redirect started.
  final double redirectStart;

  /// When the last redirect's response ended.
  final double redirectEnd;

  /// When the browser was ready to fetch.
  final double fetchStart;

  /// When the name lookup started.
  final double domainLookupStart;

  /// When the name lookup ended.
  final double domainLookupEnd;

  /// When the connection started opening.
  final double connectStart;

  /// When the connection was open, TLS included.
  final double connectEnd;

  /// When the TLS handshake started; `0` without TLS.
  final double secureConnectionStart;

  /// When the request was sent.
  final double requestStart;

  /// When the response's first byte arrived.
  final double responseStart;

  /// When the response's last byte arrived.
  final double responseEnd;

  /// The protocol (`h2`, `http/1.1`); empty when hidden.
  final String nextHopProtocol;
}

/// Where the Resource Timing entries come from: the browser's
/// `performance` ([platform]), or a test's.
abstract interface class ResourceTimingSource {
  /// The time now, on the entries' clock (`performance.now()`).
  double now();

  /// The entries of the resource [name] (an absolute address), oldest
  /// first.
  Iterable<ResourceTimingEntry> entriesNamed(String name);

  /// Keeps the entries as they come (the browser's `PerformanceObserver`)
  /// until the function it returns is called; while no one observes,
  /// nothing is kept or heard. Each call is stopped once.
  void Function() observe();
}

/// Reads a request's phases from the browser's Resource Timing: the
/// recorder [mark]s when a request starts and, once it is done, [read]s
/// the first entry of its address that started then or after.
///
/// Web only ([platform]): `dart:io` and a server's `fetch` give no such
/// times. What it gives is "if available": a response from another origin
/// shows its phases only with `Timing-Allow-Origin` (else
/// [ResourceTiming.restricted]); the browser keeps 250 entries unless the
/// app calls `performance.setResourceTimingBufferSize`, and adds none once
/// they are full; two requests to one address at the same moment may get
/// each other's.
final class ResourceTimingReader {
  /// A reader of [source]; a relative address resolved against [base]
  /// (the page's, `Uri.base`).
  ResourceTimingReader(this.source, {Uri? base}) : base = base ?? Uri.base;

  /// The browser's reader; `null` outside a browser, or in one without
  /// Resource Timing.
  static ResourceTimingReader? platform() => switch (_platformSource) {
    final source? => ResourceTimingReader(source),
    null => null,
  };

  static final ResourceTimingSource? _platformSource = browser
      .resourceTimingSource();

  /// Where the entries come from.
  final ResourceTimingSource source;

  /// What a relative address is resolved against.
  final Uri base;

  // How much earlier than the mark an entry may start: the browser rounds
  // its times.
  static const _tolerance = 1.0;

  /// The time a request starts, to [read] it by later. From then on the
  /// browser is observed until [done], so its entry is not missed.
  double mark() {
    if (_waiting++ == 0) {
      _stopObserving = source.observe();
    }
    return source.now();
  }

  /// A request [mark]ed no longer waits for its entry (read, given up,
  /// failed, cancelled): with none waiting, the browser is no longer
  /// observed.
  void done() {
    if (_waiting > 0 && --_waiting == 0) {
      _stopObserving?.call();
      _stopObserving = null;
    }
  }

  int _waiting = 0;
  void Function()? _stopObserving;

  /// The phases of the request to [url] that started at [since] or after;
  /// `null` when the browser has no such entry (yet).
  ResourceTiming? read(Uri url, double since) {
    final name = nameOf(url);
    ResourceTimingEntry? found;
    for (final entry in source.entriesNamed(name)) {
      if (entry.startTime + _tolerance < since || entry.responseEnd <= 0) {
        continue;
      }
      if (found == null || entry.startTime < found.startTime) {
        found = entry;
      }
    }
    return found == null ? null : timingOf(found);
  }

  /// [url] as the browser names its entry: absolute, with a path, without
  /// a fragment.
  String nameOf(Uri url) {
    var absolute = url.hasScheme ? url : base.resolveUri(url);
    if (absolute.path.isEmpty) {
      absolute = absolute.replace(path: '/');
    }
    return absolute.removeFragment().toString();
  }

  /// [entry]'s phases, each from the request's start: redirect, queued,
  /// DNS, TCP, TLS, waiting (the request sent until the first byte) and
  /// download; the ones of length `0` left out.
  static ResourceTiming timingOf(ResourceTimingEntry entry) {
    final start = entry.startTime;
    final total = _span(entry.responseEnd - start);
    if (entry.responseStart <= 0) {
      return ResourceTiming(total: total, restricted: true);
    }
    final phases = <NetworkPhase>[];
    void add(String name, double from, double to) {
      if (from > 0 && to > from) {
        phases.add(NetworkPhase(name, _span(from - start), _span(to - from)));
      }
    }

    add('Redirect', entry.redirectStart, entry.redirectEnd);
    add('Queued', entry.fetchStart, entry.domainLookupStart);
    add('DNS', entry.domainLookupStart, entry.domainLookupEnd);
    final tls = entry.secureConnectionStart;
    if (tls > 0) {
      add('TCP', entry.connectStart, tls);
      add('TLS', tls, entry.connectEnd);
    } else {
      add('TCP', entry.connectStart, entry.connectEnd);
    }
    add('Waiting', entry.requestStart, entry.responseStart);
    add('Download', entry.responseStart, entry.responseEnd);
    return ResourceTiming(
      total: total,
      firstByte: _span(entry.responseStart - start),
      protocol: entry.nextHopProtocol.isEmpty ? null : entry.nextHopProtocol,
      phases: phases,
    );
  }

  static Duration _span(double milliseconds) =>
      Duration(microseconds: (milliseconds * 1000).round());
}
