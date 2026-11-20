import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Semantic tokens for whole documents: placeholders, SpEL, pointcuts, SQL
/// and the parameters of closures ([SpringWorkspace.semanticTokens]), in the
/// protocol's relative encoding.
final class SemanticTokens extends ServerFeature {
  /// Tokens in [session].
  SemanticTokens(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => {
    'semanticTokensProvider': {
      'legend': {
        'tokenTypes': semanticTokenTypes,
        'tokenModifiers': semanticTokenModifiers,
      },
      'full': true,
    },
  };

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/semanticTokens/full': (params) => {
      'data': encode(
        session.workspace.semanticTokens(SpringSession.documentPath(params)),
      ),
    },
  };

  /// [tokens] (sorted, absolute positions) in the protocol's encoding: five
  /// numbers per token, its line and column relative to the previous one's.
  static List<int> encode(Iterable<SemanticToken> tokens) {
    final data = <int>[];
    var line = 0;
    var column = 0;
    for (final token in tokens) {
      final deltaLine = token.line - line;
      final deltaColumn = deltaLine == 0 ? token.column - column : token.column;
      data.addAll([
        deltaLine,
        deltaColumn,
        token.length,
        token.type.index,
        token.modifiers,
      ]);
      line = token.line;
      column = token.column;
    }
    return data;
  }
}
