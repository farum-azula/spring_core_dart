import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/src/sse/server_sent_event.dart';

/// Parses a `text/event-stream` body (byte chunks, split anywhere) into
/// events, following the HTML specification: `data:` lines are joined
/// with newlines, `id:`, `event:` and `retry:` set the other fields, `:`
/// starts a comment, a blank line ends the event. Line ends may be `\n`,
/// `\r\n` or `\r`; an unfinished event at the end is dropped.
///
/// Every block is emitted, also those without `data:` (a lone `retry:` or
/// a heartbeat comment): their [ServerSentEvent.data] is `null`.
///
/// ```dart
/// final events = response.body.transform(const SseDecoder());
/// ```
///
/// Spring (Java): `ServerSentEventHttpMessageReader`.
final class SseDecoder
    extends StreamTransformerBase<List<int>, ServerSentEvent<String?>> {
  /// A decoder.
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

  /// Parses a whole `text/event-stream` [body].
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
