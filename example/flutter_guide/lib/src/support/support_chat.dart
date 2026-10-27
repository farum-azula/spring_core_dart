import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/api/support_socket.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The support chat: the messages so far and sending. Opens the socket on
/// [join] (the Support screen), closes it on logout.
@Component()
@NotifyListeners(exclude: ['join'])
@Log(topic: 'neon.support')
class SupportChat extends ChangeNotifier {
  SupportChat(this._socket);

  final SupportSocket _socket;
  StreamSubscription<ChatMessage>? _subscription;
  final _messages = <ChatMessage>[];
  String? _user;

  /// The conversation, the oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Listens to the chat (once).
  void join() {
    _subscription ??= _socket.messages().listen((message) {
      _messages.add(message);
      notifyListeners();
    }, onError: (Object error) => log.warning('support chat: $error'));
  }

  /// Sends [text] and shows it.
  Future<void> send(String text) async {
    final message = ChatMessage(
      from: _user ?? '',
      text: text,
      at: DateTime.now().toUtc(),
    );
    _messages.add(message);
    await _socket.send(message);
  }

  @EventListener()
  void onLogin(LoggedIn event) => _user = event.user;

  /// A new user gets a new conversation: the socket closes (its next
  /// handshake carries the new session).
  @EventListener()
  Future<void> onLogout(LoggedOut event) async {
    _user = null;
    await _subscription?.cancel();
    _subscription = null;
    _messages.clear();
    await _socket.close();
  }
}
