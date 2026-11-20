import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/properties/key_rename.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// Rename of a property key: at a key of a config file, a `${key}` or a
/// key the code reads, the new key replaces the old one at every place of
/// the package that names it ([SpringWorkspace.renameKey]); the editor
/// gets the reason when the rename would leave a place reading the old
/// key.
final class KeyRenames extends ServerFeature {
  /// Renames in [session].
  KeyRenames(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {
    'renameProvider': {'prepareProvider': true},
  };

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/prepareRename': (params) {
      final named = _keyAt(params);
      return named == null
          ? null
          : {'range': rangeJson(named.range), 'placeholder': named.key};
    },
    'textDocument/rename': (params) {
      final named = _keyAt(params);
      if (named == null) {
        throw const RequestFailure('No property key here to rename');
      }
      final path = SpringSession.documentPath(params);
      final newKey = params['newName']! as String;
      switch (session.workspace.renameKey(path, named.key, newKey)) {
        case KeyRenameRefused(:final reason):
          throw RequestFailure(reason);
        case KeyRenameEdits(:final edits):
          final changes = <String, List<Map<String, Object?>>>{};
          for (final edit in edits) {
            changes.putIfAbsent(uriOf(edit.range.path), () => []).add({
              'range': rangeJson(edit.range),
              'newText': edit.newText,
            });
          }
          return {'changes': changes};
      }
    },
  };

  ({String key, SourceRange range})? _keyAt(Map<String, Object?> params) {
    final workspace = session.workspace..refresh();
    final position = params['position']! as Map;
    return workspace.keyAt(
      SpringSession.documentPath(params),
      position['line']! as int,
      position['character']! as int,
    );
  }
}
