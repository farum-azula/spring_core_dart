import 'dart:async';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/resource_timing.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// An [HttpTransport] that sends through [delegate] unchanged and writes a
/// copy of each exchange into [journal]: the method, the address, the
/// status, the times, the sizes and the headers, masked; the bodies with
/// `spring.flutter.debug.network.bodies` only, cut at the limit.
///
/// The request the caller built is the one [delegate] gets, and the
/// response or the error [delegate] gives is the one the caller gets. A
/// streamed body ([stream]) is passed on chunk by chunk as the caller
/// reads it, never gathered: each chunk is counted, and with bodies on its
/// first bytes up to the limit are copied. The exchange is over when the
/// caller has read the body to its end, stopped reading or seen it fail.
///
/// The times: the total of every exchange; the arrival of the status and
/// headers (the time to the first byte) of a streamed one, as [stream]
/// returns then. [send] returns the response whole, so its headers' time
/// is not measured: sending it through [stream] instead would change what
/// the caller gets (`send`'s timeouts cover the body too, `stream`'s the
/// headers only; the errors differ). On the web, [resourceTiming] reads
/// the browser's phases of either (DNS, connection, TLS, waiting,
/// download) once the response is done, when the browser gives them.
///
/// The debug network recorder puts it around the `HttpTransport` beans;
/// with the journal [DebugNetworkJournal.paused], it only passes through.
final class RecordingHttpTransport implements HttpTransport {
  /// [delegate], recorded into [journal]; the browser's phases read by
  /// [resourceTiming] (by default the browser's own, none outside one).
  RecordingHttpTransport(
    this.delegate,
    this.journal, {
    ResourceTimingReader? resourceTiming,
  }) : resourceTiming = resourceTiming ?? ResourceTimingReader.platform();

  /// The transport that sends.
  final HttpTransport delegate;

  /// Where the exchanges go.
  final DebugNetworkJournal journal;

  /// Reads the browser's phases of a request; `null` outside a browser.
  final ResourceTimingReader? resourceTiming;

  // When the browser's entry is looked for again after the response, while
  // it is not there: the browser tells its observers a task or more later.
  static const _timingRetries = [
    Duration(milliseconds: 100),
    Duration(seconds: 1),
  ];

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    if (!journal.isRecording) {
      return delegate.send(request);
    }
    final exchange = _start(request, streamed: false);
    final mark = resourceTiming?.mark();
    final clock = Stopwatch()..start();
    final HttpResponse response;
    try {
      response = await delegate.send(request);
    } on Object catch (error) {
      _fail(exchange, error, clock.elapsed);
      if (mark != null) {
        resourceTiming!.done();
      }
      rethrow;
    }
    final contentType = response.headers.contentType;
    exchange
      ..statusCode = response.statusCode
      ..responseHeaders = journal.masking.headers(
        response.headers,
        sensitive: request.sensitiveHeaders,
      )
      ..responseSize = response.bodyBytes.length
      ..responseBody = journal.body(
        response.bodyBytes,
        response.bodyBytes.length,
        contentType,
      )
      ..totalTime = clock.elapsed
      ..state = HttpExchangeState.done;
    journal.changed();
    if (mark != null) {
      _readTiming(exchange, request.url, mark);
    }
    return response;
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    if (!journal.isRecording) {
      return delegate.stream(request);
    }
    final exchange = _start(request, streamed: true);
    final mark = resourceTiming?.mark();
    final clock = Stopwatch()..start();
    final StreamedHttpResponse response;
    try {
      response = await delegate.stream(request);
    } on Object catch (error) {
      _fail(exchange, error, clock.elapsed);
      if (mark != null) {
        resourceTiming!.done();
      }
      rethrow;
    }
    exchange
      ..statusCode = response.statusCode
      ..responseHeaders = journal.masking.headers(
        response.headers,
        sensitive: request.sensitiveHeaders,
      )
      ..headersTime = clock.elapsed
      ..state = HttpExchangeState.receiving;
    journal.changed();
    return StreamedHttpResponse(
      response.statusCode,
      headers: response.headers,
      request: response.request,
      body: _observed(
        response.body,
        exchange,
        clock,
        response.headers.contentType,
        onDone: mark == null
            ? null
            : () => _readTiming(exchange, request.url, mark),
        onEnded: mark == null ? null : resourceTiming!.done,
      ),
    );
  }

  @override
  void close() => delegate.close();

  HttpExchange _start(HttpRequest request, {required bool streamed}) {
    final size = request.body?.length ?? 0;
    return journal.add(
      HttpExchange(
        id: journal.nextId(),
        url: journal.masking.url(request.url),
        started: DateTime.now(),
        method: request.method.value,
        requestHeaders: journal.masking.headers(
          request.headers,
          sensitive: request.sensitiveHeaders,
        ),
        requestSize: size,
        requestBody: journal.body(
          request.body,
          size,
          request.headers.contentType,
        ),
        streamed: streamed,
      ),
    );
  }

  // The browser's phases of the request to [url] started at [mark]: now,
  // or a little later when its entry is not there yet. The address is the
  // request's own, looked up and never kept.
  void _readTiming(
    HttpExchange exchange,
    Uri url,
    double mark, [
    int tried = 0,
  ]) {
    final reader = resourceTiming!;
    final timing = reader.read(url, mark);
    if (timing != null) {
      exchange.resourceTiming = timing;
      journal.changed();
      reader.done();
    } else if (tried < _timingRetries.length) {
      Timer(
        _timingRetries[tried],
        () => _readTiming(exchange, url, mark, tried + 1),
      );
    } else {
      reader.done();
    }
  }

  void _fail(HttpExchange exchange, Object error, Duration elapsed) {
    exchange
      ..state = HttpExchangeState.failed
      ..error = journal.masking.text(
        error is HttpTransportException ? error.message : '$error',
      )
      ..timeout = error is HttpTransportException && error.isTimeout
      ..totalTime = elapsed;
    journal.changed();
  }

  // The body passed on as the caller reads it: the source is listened to
  // when the caller listens, paused and resumed and cancelled with it, so
  // nothing waits here that the caller has not asked for.
  Stream<List<int>> _observed(
    Stream<List<int>> body,
    HttpExchange exchange,
    Stopwatch clock,
    String? contentType, {
    void Function()? onDone,
    void Function()? onEnded,
  }) {
    final keep = journal.bodies ? BytesBuilder(copy: false) : null;
    final limit = journal.bodyLimit;
    StreamSubscription<List<int>>? source;
    late final StreamController<List<int>> controller;

    void finish(HttpExchangeState state, {String? error}) {
      if (exchange.isDone) {
        return;
      }
      exchange
        ..state = state
        ..error = error
        ..totalTime = clock.elapsed
        ..responseBody = keep == null
            ? null
            : journal.body(
                keep.takeBytes(),
                exchange.responseSize,
                contentType,
              );
      journal.changed();
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        source = body.listen(
          (chunk) {
            if (keep != null && keep.length < limit) {
              final room = limit - keep.length;
              keep.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
            }
            exchange.responseSize += chunk.length;
            journal.changed();
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!exchange.isDone) {
              onEnded?.call();
            }
            finish(
              HttpExchangeState.failed,
              error: journal.masking.text(
                error is HttpTransportException ? error.message : '$error',
              ),
            );
            controller.addError(error, stack);
          },
          onDone: () {
            finish(HttpExchangeState.done);
            onDone?.call();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        if (!exchange.isDone) {
          onEnded?.call();
        }
        finish(HttpExchangeState.cancelled);
        return source?.cancel();
      },
    );
    return controller.stream;
  }
}
