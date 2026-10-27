import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/login_page.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/support/support_chat.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The Support screen: a chat with the bookstore over a WebSocket. Only
/// for logged-in users (the server refuses the handshake otherwise).
///
/// Like a notes app: [ChatMessages] reads the messages and rebuilds on
/// each one, [ChatInput] only sends and keeps its text field's state.
class SupportPage extends SpringStatelessWidget<(Session,)> {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (session,) = beans;
    return Scaffold(
      appBar: AppBar(title: Text(context.message('support.title'))),
      body: session.isLoggedIn
          ? const Column(
              children: [
                Expanded(child: ChatMessages()),
                ChatInput(),
              ],
            )
          : Center(
              child: OutlinedButton.icon(
                onPressed: () => LoginPage.open(context),
                icon: const Icon(Icons.login),
                label: Text(context.message('support.login')),
              ),
            ),
    );
  }
}

/// The beans of [ChatMessages].
typedef ChatMessagesBeans = (
  SupportChat,
  Session,
);

/// The conversation; joins the chat when shown.
class ChatMessages extends SpringStatefulWidget<ChatMessagesBeans> {
  const ChatMessages({super.key});

  @override
  State<ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends SpringState<ChatMessages, ChatMessagesBeans> {
  @override
  void initState() {
    super.initState();
    beans.$1.join();
  }

  @override
  Widget build(BuildContext context) {
    final (
      chat,
      session,
    ) = beans;
    final messages = chat.messages;
    if (messages.isEmpty) {
      return Center(child: Text(context.message('support.empty')));
    }
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final message in messages)
          Align(
            alignment: message.from == session.user
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Card(
              color: message.from == session.user
                  ? colors.primaryContainer
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.from,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(message.text),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The text field and its button: only sends, so it is never rebuilt by a
/// new message (and keeps what is being typed).
class ChatInput extends SpringStatefulWidget<(SupportChat,)> {
  const ChatInput({super.key});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends SpringState<ChatInput, (SupportChat,)> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      return;
    }
    final (chat,) = beans;
    chat.send(text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat-text'),
              controller: _text,
              decoration: InputDecoration(
                hintText: context.message('support.hint'),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _send,
            tooltip: context.message('support.send'),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    ),
  );
}
