import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Find references of a property key: from a key of a config file, a
/// `${key}` or a key the code reads, every place of the package that
/// names it ([SpringWorkspace.keyOccurrences]); the definitions only when
/// the editor asks for the declaration too.
final class KeyReferences extends ServerFeature {
  /// References in [session].
  KeyReferences(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {'referencesProvider': true};

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/references': (params) {
      final workspace = session.workspace..refresh();
      final path = SpringSession.documentPath(params);
      final position = params['position']! as Map;
      final named = workspace.keyAt(
        path,
        position['line']! as int,
        position['character']! as int,
      );
      if (named == null) {
        return null;
      }
      final declarations =
          (params['context'] as Map?)?['includeDeclaration'] != false;
      return [
        for (final occurrence in workspace.keyOccurrences(path, named.key))
          if (declarations || !occurrence.definition)
            {
              'uri': uriOf(occurrence.range.path),
              'range': rangeJson(occurrence.range),
            },
      ];
    },
  };
}
