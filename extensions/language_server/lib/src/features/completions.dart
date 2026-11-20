import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Completion of config keys and values, bean names, SpEL and the rest of
/// [SpringWorkspace.completion].
final class Completions extends ServerFeature {
  /// Completion in [session].
  Completions(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {
    'completionProvider': {
      'triggerCharacters': ['.', r'$', '{', '@', '#', '-', ':'],
      'resolveProvider': false,
    },
  };

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/completion': (params) {
      final at = session.position(params);
      final result = at == null
          ? null
          : session.workspace.completion(at.path, at.offset);
      if (result == null) {
        return null;
      }
      final range = rangeJson(result.replace);
      return {
        'isIncomplete': false,
        'items': [
          for (final item in result.items)
            {
              'label': item.label,
              'kind': item.kind,
              'detail': ?item.detail,
              if (item.documentation != null)
                'documentation': {
                  'kind': 'markdown',
                  'value': item.documentation,
                },
              'sortText': ?item.sortText,
              'filterText': item.label,
              'textEdit': {
                'range': range,
                'newText': item.insertText ?? item.label,
              },
            },
        ],
      };
    },
  };
}
