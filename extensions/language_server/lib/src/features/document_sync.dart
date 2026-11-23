import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/protocol/line_index.dart';

/// Keeps the workspace in step with the editor: the unsaved text of each
/// open document (the editor sends what changed), saves and changes of
/// files on disk, which the editor watches for the server when it can.
/// Clears a document's diagnostics when it closes.
final class DocumentSync extends ServerFeature {
  /// The synchronisation of [session].
  DocumentSync(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, Object?> get capabilities => const {
    'textDocumentSync': {
      'openClose': true,
      'change': 2, // incremental
      'save': {'includeText': false},
    },
  };

  @override
  Map<String, NotificationHandler> get notifications => {
    'initialized': (_) {
      _watchFiles();
      session.workspace.refresh(force: true);
    },
    'textDocument/didOpen': (params) {
      final document = params['textDocument']! as Map;
      final path = pathOf(document['uri']! as String);
      session.openDocuments.add(path);
      if (document['version'] case final int version) {
        session.documentVersions[path] = version;
      }
      session.workspace.setOverlay(path, document['text']! as String);
      session.changed();
    },
    'textDocument/didChange': (params) {
      final path = SpringSession.documentPath(params);
      if ((params['textDocument']! as Map)['version'] case final int version) {
        session.documentVersions[path] = version;
      }
      var text = session.workspace.textOf(path) ?? '';
      for (final change
          in (params['contentChanges']! as List)
              .cast<Map<Object?, Object?>>()) {
        text = _applied(text, change);
      }
      session.workspace.setOverlay(path, text);
      session.changed();
    },
    'textDocument/didClose': (params) {
      final path = SpringSession.documentPath(params);
      session.openDocuments.remove(path);
      session.documentVersions.remove(path);
      session.workspace.setOverlay(path, null);
      session.editor.notify('textDocument/publishDiagnostics', {
        'uri': uriOf(path),
        'diagnostics': <Object?>[],
      });
    },
    'textDocument/didSave': (_) => _filesChanged(),
    'workspace/didChangeWatchedFiles': (_) => _filesChanged(),
  };

  void _filesChanged() {
    session.workspace.refresh(force: true);
    session.changed();
  }

  /// The files whose changes on disk matter: Dart, config files, the
  /// packages' configuration and their Spring metadata.
  static const _watched = [
    '**/*.dart',
    '**/*.{yaml,yml,properties}',
    '**/.dart_tool/package_config.json',
    '**/spring_metadata.json',
  ];

  /// Asks the editor to report changes of the [_watched] files, when it can
  /// watch files for a server; the workspace then stops scanning for them.
  void _watchFiles() {
    if (!session.watchesFiles) {
      return;
    }
    session.editor.request('client/registerCapability', {
      'registrations': [
        {
          'id': 'dart_spring-files',
          'method': 'workspace/didChangeWatchedFiles',
          'registerOptions': {
            'watchers': [
              for (final glob in _watched) {'globPattern': glob},
            ],
          },
        },
      ],
    });
    session.workspace.editorReportsChanges();
  }

  /// [text] with [change] (a `TextDocumentContentChangeEvent`) applied: its
  /// range replaced by its text, or the whole text without a range.
  static String _applied(String text, Map<Object?, Object?> change) {
    final replacement = change['text']! as String;
    final range = change['range'] as Map?;
    if (range == null) {
      return replacement;
    }
    final lines = LineIndex(text);
    int offset(Map<Object?, Object?> position) => lines.offsetOf(
      (position['line']! as num).toInt(),
      (position['character']! as num).toInt(),
    );
    final start = offset(range['start']! as Map);
    final end = offset(range['end']! as Map);
    return text.replaceRange(start, end < start ? start : end, replacement);
  }
}
