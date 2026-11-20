import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/protocol/line_index.dart';
import 'package:dart_spring_language_server/src/workspace.dart';

/// What the features of a session share: the workspace of the folders the
/// editor opened, the documents open in it, and the editor.
final class SpringSession {
  /// A session over [workspace], talking to [editor], with the settings
  /// and capabilities of the `initialize` parameters.
  SpringSession(this.workspace, this.editor, Map<String, Object?> initialize)
    : settings = SessionSettings.from(initialize['initializationOptions']),
      refreshesInlayHints =
          _capability(initialize, [
            'workspace',
            'inlayHint',
            'refreshSupport',
          ]) ==
          true,
      watchesFiles =
          _capability(initialize, [
            'workspace',
            'didChangeWatchedFiles',
            'dynamicRegistration',
          ]) ==
          true;

  static Object? _capability(
    Map<String, Object?> initialize,
    List<String> path,
  ) {
    var value = initialize['capabilities'];
    for (final key in path) {
      value = value is Map ? value[key] : null;
    }
    return value;
  }

  /// The folders of the `initialize` parameters: its `workspaceFolders`,
  /// else its `rootUri` or `rootPath`.
  static List<String> workspaceRoots(Map<String, Object?> initializeParams) {
    final folders = <String>[
      for (final folder
          in (initializeParams['workspaceFolders'] as List?) ?? const [])
        pathOf((folder as Map)['uri']! as String),
    ];
    if (folders.isNotEmpty) {
      return folders;
    }
    return [
      if (initializeParams['rootUri'] case final String uri)
        pathOf(uri)
      else if (initializeParams['rootPath'] case final String path)
        path,
    ];
  }

  /// What the server knows of the project.
  final SpringWorkspace workspace;

  /// Where notifications go.
  final Editor editor;

  /// The paths of the documents open in the editor.
  final openDocuments = <String>{};

  /// What the user set for the server in the editor.
  SessionSettings settings;

  /// Whether the editor takes `workspace/inlayHint/refresh`, to show the
  /// values of properties again after a change.
  final bool refreshesInlayHints;

  /// Whether the editor watches files for the server when asked
  /// (`client/registerCapability` of `workspace/didChangeWatchedFiles`).
  final bool watchesFiles;

  final _changeListeners = <void Function()>[];

  /// Calls [listener] after each change of the open documents (opened,
  /// edited, saved, closed) or of the files of the workspace.
  void onChange(void Function() listener) => _changeListeners.add(listener);

  /// Tells the listeners of [onChange].
  void changed() {
    for (final listener in _changeListeners) {
      listener();
    }
  }

  /// The document and offset a `TextDocumentPositionParams` points at;
  /// null for a document the workspace cannot read.
  ({String path, int offset})? position(Map<String, Object?> params) {
    workspace.refresh();
    final path = documentPath(params);
    final text = workspace.textOf(path);
    if (text == null) {
      return null;
    }
    final position = params['position']! as Map;
    return (
      path: path,
      offset: LineIndex(
        text,
      ).offsetOf(position['line']! as int, position['character']! as int),
    );
  }

  /// The path of the `textDocument` of [params].
  static String documentPath(Map<String, Object?> params) =>
      pathOf((params['textDocument']! as Map)['uri']! as String);
}

/// The file path of a `file:` [uri].
String pathOf(String uri) => Uri.parse(uri).toFilePath();

/// The `file:` URI of [path].
String uriOf(String path) => Uri.file(path).toString();

/// [range] as a protocol `Range`.
Map<String, Object?> rangeJson(SourceRange range) => {
  'start': {'line': range.startLine, 'character': range.startColumn},
  'end': {'line': range.endLine, 'character': range.endColumn},
};

/// What the user sets for the server: the `initialization_options` of
/// `dart-spring` in the editor's settings, and its `settings` later
/// (`workspace/didChangeConfiguration`).
///
/// ```json
/// { "lsp": { "dart-spring": { "settings": { "activeProfiles": ["dev"] } } } }
/// ```
final class SessionSettings {
  /// Settings with [activeProfiles].
  const SessionSettings({this.activeProfiles = const []});

  /// The settings in [json] (a JSON object); the defaults for anything
  /// else.
  factory SessionSettings.from(Object? json) {
    final profiles = json is Map ? json['activeProfiles'] : null;
    return SessionSettings(
      activeProfiles: switch (profiles) {
        final List<Object?> list => [
          for (final name in list)
            if (name is String && name.trim().isNotEmpty) name.trim(),
        ],
        final String text => [
          for (final name in text.split(','))
            if (name.trim().isNotEmpty) name.trim(),
        ],
        _ => const [],
      },
    );
  }

  /// The profiles the values of properties are shown for; when empty, the
  /// `spring.profiles.active` of the package's config (or a test's
  /// `@ActiveProfiles`).
  final List<String> activeProfiles;
}
