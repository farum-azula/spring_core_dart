import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// A line of the support chat: `{"from": "ada", "text": "Hi", "at":
/// "2026-10-27T10:00:00.000Z"}`. Clients may send only `text`: the server
/// fills in who sent it and when.
@Introspected()
class ChatMessage {
  const ChatMessage({required this.text, this.from = '', this.at});

  final String from;
  final String text;
  final DateTime? at;
}
