/// Finds a protocol's heartbeat and its reply among a WebSocket's text
/// frames, so the recorder measures the round trip: one of a chain, the
/// first that knows a frame wins. The built-in one reads Phoenix's
/// ([PhoenixHeartbeatMatcher]).
///
/// It is asked once per text frame while the recorder records (sent
/// frames for [ping], received ones for [pong]), so it looks at the start
/// of the frame only and returns quickly.
abstract interface class WebSocketPingMatcher {
  /// What the frames it finds are called (`heartbeat`).
  String get name;

  /// The key of the heartbeat [text] sent (its `ref`); `null` when it is
  /// not one.
  String? ping(String text);

  /// The key of the heartbeat the reply [text] received answers; `null`
  /// when it is not one.
  String? pong(String text);
}

/// Phoenix's heartbeat (the WebSocket starter's `@PhoenixChannel`,
/// Supabase Realtime): the `heartbeat` push on the `phoenix` topic, and the
/// `phx_reply` on that topic with the same `ref`, in the serializer's
/// version 2 (`[join_ref, ref, topic, event, payload]`) and version 1 (an
/// object).
final class PhoenixHeartbeatMatcher implements WebSocketPingMatcher {
  /// The matcher.
  const PhoenixHeartbeatMatcher();

  // How far into a frame it looks: the topic and the event come first.
  static const _prefix = 512;

  static final _array = RegExp(
    r'^\s*\[\s*(?:null|"[^"]*")\s*,\s*(?:null|"([^"]*)")\s*,\s*"phoenix"\s*,'
    r'\s*"([a-z_]+)"',
  );
  static final _event = RegExp(r'"event"\s*:\s*"([a-z_]+)"');
  static final _ref = RegExp(r'"ref"\s*:\s*"([^"]*)"');
  static final _topic = RegExp(r'"topic"\s*:\s*"phoenix"');

  @override
  String get name => 'heartbeat';

  @override
  String? ping(String text) => _match(text, _isPing);

  @override
  String? pong(String text) => _match(text, _isPong);

  static bool _isPing(String event) =>
      event == 'heartbeat' || event == 'phx_heartbeat';

  static bool _isPong(String event) => event == 'phx_reply';

  static String? _match(String text, bool Function(String event) wanted) {
    final head = text.length > _prefix ? text.substring(0, _prefix) : text;
    if (!head.contains('"phoenix"')) {
      return null;
    }
    if (_array.firstMatch(head) case final match?) {
      return wanted(match[2]!) ? match[1] : null;
    }
    if (!_topic.hasMatch(head)) {
      return null;
    }
    final event = _event.firstMatch(head)?[1];
    if (event == null || !wanted(event)) {
      return null;
    }
    return _ref.firstMatch(head)?[1];
  }
}
