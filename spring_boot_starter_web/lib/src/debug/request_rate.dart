import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.qps');

/// The upper bounds of the latency buckets, in microseconds: from 100 µs,
/// each half as much again as the one before, to about a minute; a last
/// bucket takes what is slower. A percentile read from them is at most
/// half its value off, which is enough to see 2 ms from 20 ms from 200.
final List<int> requestLatencyBounds = List.unmodifiable([
  for (var bound = 100.0; bound < 60e6; bound *= 1.5) bound.round(),
]);

/// Counts the requests of its isolate: the first filter of the debug
/// feature `qps` (`spring.web.debug.qps.enabled`), around everything else,
/// so the time it measures is the whole answer as the server sees it
/// (not the time the request waited for the isolate).
///
/// It only counts; [RequestRates] turns the counts of every isolate into
/// requests per second.
final class RequestRateFilter implements WebFilter, Ordered, IsolateReporter {
  /// The report's name ([IsolateReporter.id]).
  static const reportId = 'qps';

  var _requests = 0;
  var _errors = 0;
  var _active = 0;
  final _buckets = List<int>.filled(requestLatencyBounds.length + 1, 0);

  @override
  int get order => Ordered.highestPrecedence;

  @override
  String get id => reportId;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final watch = Stopwatch()..start();
    _active++;
    // The status of an error thrown past the filters is written after
    // them: an error that says its status is counted by it, any other is
    // a 500.
    int? thrown;
    try {
      await chain.doFilter(request, response);
    } on Object catch (error) {
      thrown = error is ErrorResponse ? error.statusCode : 500;
      rethrow;
    } finally {
      _active--;
      _requests++;
      if ((thrown ?? response.statusCode) >= 500) {
        _errors++;
      }
      _buckets[_bucket(watch.elapsedMicroseconds)]++;
    }
  }

  static int _bucket(int micros) {
    var low = 0;
    var high = requestLatencyBounds.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (requestLatencyBounds[middle] < micros) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// What this isolate has counted since it started.
  RequestCounts get counts => RequestCounts(
    requests: _requests,
    errors: _errors,
    active: _active,
    buckets: List.of(_buckets),
  );

  @override
  Object? report() => counts.toJson();
}

/// The requests one isolate has counted since it started.
final class RequestCounts {
  /// The counts.
  const RequestCounts({
    this.requests = 0,
    this.errors = 0,
    this.active = 0,
    this.buckets = const [],
  });

  /// The counts [json] ([toJson]) describes; none for anything else.
  factory RequestCounts.fromJson(Object? json) => json is! Map
      ? const RequestCounts()
      : RequestCounts(
          requests: (json['requests'] as num?)?.toInt() ?? 0,
          errors: (json['errors'] as num?)?.toInt() ?? 0,
          active: (json['active'] as num?)?.toInt() ?? 0,
          buckets: [
            for (final count in json['buckets'] as List? ?? const [])
              (count as num).toInt(),
          ],
        );

  /// The requests answered.
  final int requests;

  /// Those answered with a 5xx status, or not at all.
  final int errors;

  /// The requests in flight now.
  final int active;

  /// How many requests each latency bucket ([requestLatencyBounds]) has.
  final List<int> buckets;

  /// These counts as JSON, which crosses isolates.
  Map<String, Object?> toJson() => {
    'requests': requests,
    'errors': errors,
    'active': active,
    'buckets': buckets,
  };
}

/// What happened in one window of time: the requests per second and how
/// long they took, for one isolate or for all together.
final class RequestRate {
  /// The rate of a window of [seconds].
  const RequestRate({
    required this.seconds,
    required this.requests,
    required this.errors,
    required this.active,
    required this.buckets,
  });

  /// What was counted between [before] and [now], [seconds] apart. An
  /// isolate that started again counts from zero: its window is what it
  /// has now.
  factory RequestRate.between(
    RequestCounts? before,
    RequestCounts now,
    double seconds,
  ) {
    final from = before == null || before.requests > now.requests
        ? const RequestCounts()
        : before;
    return RequestRate(
      seconds: seconds,
      requests: now.requests - from.requests,
      errors: now.errors - from.errors,
      active: now.active,
      buckets: [
        for (final (i, count) in now.buckets.indexed)
          count - (i < from.buckets.length ? from.buckets[i] : 0),
      ],
    );
  }

  /// The rates of several isolates as one.
  factory RequestRate.sum(Iterable<RequestRate> rates, double seconds) {
    var requests = 0;
    var errors = 0;
    var active = 0;
    final buckets = List<int>.filled(requestLatencyBounds.length + 1, 0);
    for (final rate in rates) {
      requests += rate.requests;
      errors += rate.errors;
      active += rate.active;
      for (final (i, count) in rate.buckets.indexed) {
        if (i < buckets.length) {
          buckets[i] += count;
        }
      }
    }
    return RequestRate(
      seconds: seconds,
      requests: requests,
      errors: errors,
      active: active,
      buckets: buckets,
    );
  }

  /// The length of the window.
  final double seconds;

  /// The requests answered in it.
  final int requests;

  /// Those answered with a 5xx status, or not at all.
  final int errors;

  /// The requests in flight at its end.
  final int active;

  /// The requests of the window by latency bucket.
  final List<int> buckets;

  /// Requests per second.
  double get qps => seconds <= 0 ? 0 : requests / seconds;

  /// The latency under which [share] of the requests were answered (`0.5`:
  /// the median, `0.99`: all but the slowest hundredth); `null` without
  /// requests. It is the upper bound of the bucket that request fell in.
  Duration? percentile(double share) {
    if (requests <= 0) {
      return null;
    }
    final rank = (requests * share).ceil().clamp(1, requests);
    var seen = 0;
    for (final (i, count) in buckets.indexed) {
      seen += count;
      if (seen >= rank) {
        return Duration(
          microseconds: i < requestLatencyBounds.length
              ? requestLatencyBounds[i]
              : requestLatencyBounds.last * 2,
        );
      }
    }
    return null;
  }

  /// This rate as JSON: what the actuator's `qps` endpoint answers.
  Map<String, Object?> toJson() => {
    'qps': double.parse(qps.toStringAsFixed(1)),
    'requests': requests,
    'errors': errors,
    'active': active,
    'p50Micros': ?percentile(0.5)?.inMicroseconds,
    'p95Micros': ?percentile(0.95)?.inMicroseconds,
    'p99Micros': ?percentile(0.99)?.inMicroseconds,
  };
}

/// The last window of every isolate and of all together.
final class RequestRateWindow {
  /// The window.
  const RequestRateWindow(this.total, this.isolates);

  /// All isolates together.
  final RequestRate total;

  /// Each isolate by name, the first isolate first.
  final Map<String, RequestRate> isolates;

  /// The window as JSON.
  Map<String, Object?> toJson() => {
    'seconds': double.parse(total.seconds.toStringAsFixed(1)),
    ...total.toJson(),
    'isolates': {
      for (final MapEntry(:key, :value) in isolates.entries)
        key: value.toJson(),
    },
  };
}

/// Requests per second of the application, isolate by isolate and in
/// total: the bean of the debug feature `qps`
/// (`spring.web.debug.qps.enabled: true`), in the application's first
/// isolate.
///
/// Every `spring.web.debug.qps.log-interval` it asks the isolates for
/// their counts ([RequestRateFilter]), keeps the window between two looks
/// in [last], and logs it at INFO on `spring.web.qps` when there were
/// requests:
///
/// ```text
/// 1250.4 requests/s (p50 1.1 ms, p99 9.2 ms), 14 in flight, 0 errors;
///   main 412.0, isolate-1 420.2, isolate-2 418.2
/// ```
///
/// The line is one line in the log. The actuator's `qps` endpoint answers
/// [last] as JSON, from whichever isolate takes the request (it asks this
/// bean through [PrimaryIsolate]). Set the level of `spring.web.qps` to
/// `warn` to keep it out of the logs.
///
/// Spring's counterpart is Micrometer's `http.server.requests` timer; this
/// is a debug feature, not a metrics system: it is in the build only when
/// asked for.
final class RequestRates with SmartLifecycle implements PrimaryIsolateHandler {
  /// The rates of [own] and of the isolates in [reports].
  RequestRates(
    this.own,
    this.reports, {
    this.interval = const Duration(seconds: 10),
  });

  /// This isolate's counter.
  final RequestRateFilter own;

  /// The other isolates' counts.
  final IsolateReports reports;

  /// The length of a window, and how often it is logged.
  final Duration interval;

  Timer? _timer;
  final _clock = Stopwatch();
  Duration _at = Duration.zero;
  Map<String, RequestCounts> _before = {};

  /// The last window; `null` before the first [interval] has passed.
  RequestRateWindow? last;

  /// The name it answers under for the other isolates
  /// ([PrimaryIsolate.ask]): the request `now` ends the window and answers
  /// it, anything else answers [last]; both as JSON, `null` for none.
  static const handlerId = 'web.qps';

  @override
  String get id => handlerId;

  @override
  Future<Object?> handle(Object? request) async =>
      request == 'now' ? (await look()).toJson() : last?.toJson();

  @override
  bool get isRunning => _clock.isRunning;

  // Without an interval (`0`) nothing is logged, and a window is as long
  // as the time between two [look]s.
  @override
  void start() {
    if (_clock.isRunning) {
      return;
    }
    _clock.start();
    _at = _clock.elapsed;
    _before = {IsolateInfo.current.name: own.counts};
    if (interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) => unawaited(look()));
    }
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  /// Ends the window: asks the isolates, works out [last] and logs it.
  Future<RequestRateWindow> look() async {
    await reports.refresh();
    final now = _clock.elapsed;
    final seconds = (now - _at).inMicroseconds / Duration.microsecondsPerSecond;
    final counts = {
      for (final MapEntry(key: isolate, value: report)
          in reports
              .of(RequestRateFilter.reportId, own: IsolateInfo.current.name)
              .entries)
        isolate: RequestCounts.fromJson(report),
    };
    final isolates = {
      for (final MapEntry(key: isolate, value: count) in counts.entries)
        isolate: RequestRate.between(_before[isolate], count, seconds),
    };
    _at = now;
    _before = counts;
    final window = last = RequestRateWindow(
      RequestRate.sum(isolates.values, seconds),
      isolates,
    );
    if (window.total.requests > 0 || window.total.active > 0) {
      _log.info(() => describe(window));
    }
    return window;
  }

  /// [window] as the line the log gets.
  static String describe(RequestRateWindow window) {
    String ms(Duration? time) => time == null
        ? '-'
        : '${(time.inMicroseconds / 1000).toStringAsFixed(1)} ms';
    final total = window.total;
    final each = [
      if (window.isolates.length > 1)
        for (final MapEntry(:key, :value) in window.isolates.entries)
          '$key ${value.qps.toStringAsFixed(1)}',
    ].join(', ');
    return '${total.qps.toStringAsFixed(1)} requests/s '
        '(p50 ${ms(total.percentile(0.5))}, '
        'p99 ${ms(total.percentile(0.99))}), '
        '${total.active} in flight, ${total.errors} errors'
        '${each.isEmpty ? '' : '; $each'}';
  }
}
