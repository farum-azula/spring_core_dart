import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Go to definition: from an injection point to its beans, from a `${key}`
/// to the property, and the other targets of [SpringWorkspace.definition].
final class Definitions extends ServerFeature {
  /// Definitions in [session].
  Definitions(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {'definitionProvider': true};

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/definition': (params) {
      final at = session.position(params);
      if (at == null) {
        return null;
      }
      final ranges = session.workspace.definition(at.path, at.offset);
      return ranges.isEmpty
          ? null
          : [for (final range in ranges) _location(range)];
    },
  };

  // An empty range at the start of the target: the editor moves the cursor
  // there without selecting the name or key.
  static Map<String, Object?> _location(SourceRange range) {
    final start = {'line': range.startLine, 'character': range.startColumn};
    return {
      'uri': uriOf(range.path),
      'range': {'start': start, 'end': start},
    };
  }
}
