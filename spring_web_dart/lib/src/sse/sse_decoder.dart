import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/src/sse/server_sent_event.dart';

/// A stream transformer that turns the bytes of a `text/event-stream`
/// body into [ServerSentEvent]s with text data.
///
/// The body arrives in chunks that may split a line or a character
/// anywhere. This decoder reassembles them and parses the format as the
/// HTML specification describes it:
///
/// - `data:` lines are joined with newlines;
/// - `id:`, `event:` and `retry:` (whole milliseconds) set the other
///   fields, and an invalid `retry:` is ignored;
/// - a line starting with `:` is a comment;
/// - a blank line ends the event.
///
/// Lines may end with `\n`, `\r\n` or `\r`, and bytes that are not valid
/// UTF-8 become replacement characters. An unfinished event at the end of
/// the body is dropped.
///
/// Unlike a browser, it emits every block, also those without `data:`
/// (a lone `retry:`, a heartbeat comment): their [ServerSentEvent.data] is
/// `null`. Fields do not carry over: each event has only the `id:` it
/// sent.
///
/// `connectServerSentEvents` uses it, so applications rarely do; it is for
/// code that reads an event stream from a raw response.
///
/// ```dart
/// // `response` comes from `HttpTransport.stream`.
/// await for (final event in response.body.transform(const SseDecoder())) {
///   if (event.data case final data?) log.info(data);
/// }
/// ```
///
/// Spring (Java): `ServerSentEventHttpMessageReader`, which `WebClient`
/// uses to read `text/event-stream`.
final class SseDecoder
    extends StreamTransformerBase<List<int>, ServerSentEvent<String?>> {
  /// A decoder. It keeps no state between bodies, so one constant
  /// instance serves every stream.
  const SseDecoder();

  @override
  Stream<ServerSentEvent<String?>> bind(Stream<List<int>> stream) =>
      Stream<ServerSentEvent<String?>>.eventTransformed(
        stream
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter()),
        _SseSink.new,
      ).cast<ServerSentEvent<String?>>();

  /// Parses a whole `text/event-stream` [body] that is already in memory,
  /// such as a recorded response in a test. The rules are the same as for
  /// a stream: blocks without `data:` are included, and an unfinished
  /// event at the end is dropped.
  static List<ServerSentEvent<String?>> parse(String body) {
    final events = <ServerSentEvent<String?>>[];
    final sink = _SseSink(_ListSink(events));
    const LineSplitter().convert(body).forEach(sink.add);
    // A body ending with an empty line has dispatched everything already.
    return events;
  }
}

final class _ListSink implements EventSink<ServerSentEvent<String?>> {
  _ListSink(this.events);

  final List<ServerSentEvent<String?>> events;

  @override
  void add(ServerSentEvent<String?> event) => events.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);

  @override
  void close() {}
}

final class _SseSink implements EventSink<String> {
  _SseSink(this._out);

  final EventSink<ServerSentEvent<String?>> _out;
  bool _first = true;
  StringBuffer? _data;
  String? _id;
  String? _event;
  Duration? _retry;
  StringBuffer? _comment;
  bool _any = false;

  @override
  void add(String input) {
    var line = input;
    if (_first) {
      _first = false;
      if (line.startsWith('﻿')) {
        line = line.substring(1);
      }
    }
    if (line.isEmpty) {
      _dispatch();
      return;
    }
    _any = true;
    final colon = line.indexOf(':');
    if (colon == 0) {
      final text = line.substring(1);
      final comment = _comment ??= StringBuffer();
      if (comment.isNotEmpty) {
        comment.write('\n');
      }
      comment.write(text.startsWith(' ') ? text.substring(1) : text);
      return;
    }
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    switch (field) {
      case 'data':
        (_data ??= StringBuffer())
          ..write(value)
          ..write('\n');
      case 'id':
        if (!value.contains('\u0000')) {
          _id = value;
        }
      case 'event':
        _event = value;
      case 'retry':
        if (RegExp(r'^\d+$').hasMatch(value)) {
          _retry = Duration(milliseconds: int.parse(value));
        }
    }
  }

  void _dispatch() {
    if (!_any) {
      return;
    }
    final data = _data?.toString();
    _out.add(
      ServerSentEvent<String?>(
        data?.substring(0, data.length - 1),
        id: _id,
        event: _event == null || _event!.isEmpty ? null : _event,
        retry: _retry,
        comment: _comment?.toString(),
      ),
    );
    _data = null;
    _id = null;
    _event = null;
    _retry = null;
    _comment = null;
    _any = false;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() => _out.close();
}
