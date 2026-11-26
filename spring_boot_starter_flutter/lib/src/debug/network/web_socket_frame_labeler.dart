/// What a WebSocket frame is, for the Network tab: one of a chain the
/// recorder asks in order, the first label given wins. The built-in one
/// reads Phoenix channels' joins and leaves ([PhoenixFrameLabeler]); a
/// bean of this type is asked before it, for an application's own
/// protocol.
///
/// It is asked once per text frame while the recorder records, so it
/// looks at the start of the frame only and returns quickly.
abstract interface class WebSocketFrameLabeler {
  /// [text]'s label, with the channel it opens or closes; `null` when it
  /// does not know the frame.
  WebSocketFrameLabel? label(String text);
}

/// A frame's label, and what it does to a channel.
final class WebSocketFrameLabel {
  /// [text], joining or leaving [channel] when given.
  const WebSocketFrameLabel(this.text, {this.channel, this.joins, this.event});

  /// What is shown (`join room:lobby`).
  final String text;

  /// The channel it is about.
  final String? channel;

  /// `true` when it joins [channel], `false` when it leaves it, `null`
  /// otherwise.
  final bool? joins;

  /// The protocol's event name (`phx_join`).
  final String? event;
}

/// Labels the frames of Phoenix channels (the WebSocket starter's
/// `@PhoenixChannel`, Supabase Realtime): `join <topic>`, `leave <topic>`,
/// `close <topic>`, `error <topic>`, in the serializer's version 2 (an
/// array, `[join_ref, ref, topic, event, payload]`) and version 1 (an
/// object with `topic` and `event`). Other frames, the heartbeat and the
/// replies included, get no label.
final class PhoenixFrameLabeler implements WebSocketFrameLabeler {
  /// The labeler.
  const PhoenixFrameLabeler();

  // How far into a frame it looks: the topic and the event come first.
  static const _prefix = 512;

  static final _array = RegExp(
    r'^\s*\[\s*(?:null|"[^"]*")\s*,\s*(?:null|"[^"]*")\s*,\s*"([^"]*)"\s*,'
    r'\s*"(phx_join|phx_leave|phx_close|phx_error)"',
  );
  static final _topic = RegExp(r'"topic"\s*:\s*"([^"]*)"');
  static final _event = RegExp(
    r'"event"\s*:\s*"(phx_join|phx_leave|phx_close|phx_error)"',
  );

  @override
  WebSocketFrameLabel? label(String text) {
    final head = text.length > _prefix ? text.substring(0, _prefix) : text;
    if (!head.contains('phx_')) {
      return null;
    }
    String? topic;
    String? event;
    if (_array.firstMatch(head) case final match?) {
      topic = match[1];
      event = match[2];
    } else if (_event.firstMatch(head) case final match?) {
      event = match[1];
      topic = _topic.firstMatch(head)?[1];
    }
    if (topic == null || event == null) {
      return null;
    }
    return switch (event) {
      'phx_join' => WebSocketFrameLabel(
        'join $topic',
        channel: topic,
        joins: true,
        event: event,
      ),
      'phx_leave' => WebSocketFrameLabel(
        'leave $topic',
        channel: topic,
        joins: false,
        event: event,
      ),
      'phx_close' => WebSocketFrameLabel(
        'close $topic',
        channel: topic,
        joins: false,
        event: event,
      ),
      _ => WebSocketFrameLabel('error $topic', channel: topic, event: event),
    };
  }
}
