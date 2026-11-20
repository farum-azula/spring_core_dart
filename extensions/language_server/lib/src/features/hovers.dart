import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Hovers: the values of a property, the candidate beans of an injection
/// point, and the rest of [SpringWorkspace.hover], as Markdown.
final class Hovers extends ServerFeature {
  /// Hovers in [session].
  Hovers(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {'hoverProvider': true};

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/hover': (params) {
      final at = session.position(params);
      final text = at == null
          ? null
          : session.workspace.hover(at.path, at.offset);
      return text == null
          ? null
          : {
              'contents': {'kind': 'markdown', 'value': text},
            };
    },
  };
}
