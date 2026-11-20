import 'dart:async';
import 'dart:io';

import 'package:dart_spring_language_server/src/features/code_actions.dart';
import 'package:dart_spring_language_server/src/features/completions.dart';
import 'package:dart_spring_language_server/src/features/definitions.dart';
import 'package:dart_spring_language_server/src/features/diagnostics.dart';
import 'package:dart_spring_language_server/src/features/document_sync.dart';
import 'package:dart_spring_language_server/src/features/hovers.dart';
import 'package:dart_spring_language_server/src/features/inlay_hints.dart';
import 'package:dart_spring_language_server/src/features/key_references.dart';
import 'package:dart_spring_language_server/src/features/key_renames.dart';
import 'package:dart_spring_language_server/src/features/semantic_tokens.dart';
import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/features/settings.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/protocol/message_channel.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// The `dart_spring` language server: answers an editor's questions about
/// a Spring project over the Language Server Protocol.
///
/// The editor runs it next to the Dart analysis server, which still
/// handles Dart itself; this server adds what needs Spring knowledge. Each
/// capability is a [ServerFeature] of its own (lib/src/features/), listed
/// once in [features]: a new capability is a new feature and one entry
/// there. [SpringWorkspace] holds what the server knows of the project.
///
/// ```dart
/// // bin/dart_spring_lsp.dart: the editor starts the process and talks to
/// // it over stdin and stdout. Tests pass in-memory streams instead.
/// final code = await SpringLanguageServer(stdin, stdout).serve();
/// exit(code);
/// ```
final class SpringLanguageServer {
  /// A server that reads the editor's messages from [input] (a byte stream
  /// such as stdin) and writes its answers and notifications to [output]
  /// (such as stdout). Nothing happens until [serve].
  SpringLanguageServer(Stream<List<int>> input, IOSink output)
    : _server = LanguageServer(
        'dart_spring_lsp',
        MessageChannel(input, output),
        features,
      );

  final LanguageServer _server;

  /// Handles messages until the input ends or the editor sends `exit`, and
  /// completes with the exit code the protocol asks for: 0 when a
  /// `shutdown` request came first, 1 otherwise.
  Future<int> serve() => _server.serve();

  /// The features of a session over the folders the editor opened.
  static List<ServerFeature> features(
    Map<String, Object?> initializeParams,
    Editor editor,
  ) {
    final session = SpringSession(
      SpringWorkspace(SpringSession.workspaceRoots(initializeParams)),
      editor,
      initializeParams,
    );
    return [
      DocumentSync(session),
      Definitions(session),
      Hovers(session),
      Completions(session),
      SemanticTokens(session),
      Diagnostics(session),
      CodeActions(session),
      KeyReferences(session),
      KeyRenames(session),
      InlayHints(session),
      Settings(session),
    ];
  }
}
