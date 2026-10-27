// The support chat (chapter 5): a WebSocket endpoint on the web server's
// port. The handshake is an ordinary request through the security filter
// chain, so only logged-in users connect (the session cookie), and the
// methods get the user of the handshake.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/shop/clock.dart';
import 'package:neon_books_server/src/support/chat_message.dart';
import 'package:neon_books_server/src/support/support_bot.dart';
import 'package:neon_books_server/src/support/support_sessions.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

/// Changes chat messages before anyone sees them.
abstract interface class ChatFilter {
  String filter(String text);
}

/// Customers write to the shop; every admin in the chat sees it, and the
/// bot (when on) answers at once. An admin answers a customer with
/// `@name text`.
@WebSocketEndpoint(
  SupportSessions.path,
  // Browsers (the Flutter web build) from another port; the apps send no
  // Origin and are accepted anyway.
  allowedOriginPatterns: ['http://localhost:[*]', 'http://127.0.0.1:[*]'],
)
@Log()
class SupportEndpoint {
  SupportEndpoint(this._support, this._clock, this._filters, [this._bot]);

  final SupportSessions _support;
  final Clock _clock;

  /// Every ChatFilter bean, in @Order. None exists yet (a place for
  /// moderation): the list is empty, not an error.
  final List<ChatFilter> _filters;

  /// Optional (nullable): absent with `neon.support.bot.enabled=false`.
  final SupportBot? _bot;

  @OnOpen()
  void open(ServerWebSocketSession session, Principal? user) {
    final name = user?.name ?? 'guest';
    log.info('$name joined the support chat', fields: {'session': session.id});
    if (_bot case final bot?) {
      session.sendJson(_reply(bot.greet(name, locale: _localeOf(session))));
    }
  }

  /// What this returns is sent back to the sender, as JSON.
  @OnMessage()
  ChatMessage? message(
    ServerWebSocketSession session,
    Principal? user,
    ChatMessage message,
  ) {
    final name = user?.name ?? 'guest';
    final text = _filters.fold(message.text, (text, f) => f.filter(text));
    final stamped = ChatMessage(from: name, text: text, at: _clock.now());
    if (SupportSessions.isAdmin(user)) {
      final reply = RegExp(r'^@(\S+)\s+(.*)$').firstMatch(text);
      if (reply != null) {
        _support.sendTo(
          reply[1]!,
          ChatMessage(from: name, text: reply[2]!, at: stamped.at),
        );
        return null;
      }
    }
    _support.sendToAdmins(stamped, except: session);
    return switch (_bot) {
      final bot? => _reply(bot.answer(text, name, locale: _localeOf(session))),
      null => null,
    };
  }

  @OnClose()
  void close(ServerWebSocketSession session, CloseStatus status) => log.debug(
    '${session.principal?.name} left the support chat (${status.code})',
  );

  /// A message that is not a chat message (not JSON, no `text`): the
  /// connection stays open.
  @OnError()
  void error(ServerWebSocketSession session, Object error) {
    log.warning('support chat: $error');
    session.sendJson(_reply('Sorry, that message could not be read.'));
  }

  ChatMessage _reply(String text) =>
      ChatMessage(from: SupportBot.name, text: text, at: _clock.now());

  static String? _localeOf(ServerWebSocketSession session) =>
      session.handshakeHeaders['Accept-Language']?.split(RegExp('[,;-]')).first;
}
