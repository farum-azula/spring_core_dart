// The editor sends only what changed in a document, and watches the files
// for the server when it can (the server then stops scanning for changes).
import 'dart:io';

import 'package:dart_spring_language_server/src/features/document_sync.dart';
import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

final class _Editor implements Editor {
  final requests = <(String, Map<String, Object?>?)>[];

  @override
  void notify(String method, Map<String, Object?> params) {}

  @override
  void request(String method, [Map<String, Object?>? params]) =>
      requests.add((method, params));
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lsp_sync_'));
  tearDown(() => root.deleteSync(recursive: true));

  DocumentSync sync(_Editor editor, {required bool watches}) => DocumentSync(
    SpringSession(SpringWorkspace([root.path]), editor, {
      'capabilities': {
        'workspace': {
          'didChangeWatchedFiles': {'dynamicRegistration': watches},
        },
      },
    }),
  );

  test('a change is applied where it is, in UTF-16 positions', () {
    final feature = sync(_Editor(), watches: false);
    final path = '${root.path}/lib/a.dart';
    final uri = uriOf(path);
    feature.notifications['textDocument/didOpen']!({
      'textDocument': {'uri': uri, 'text': "var a = 'é';\nvar b = 1;\n"},
    });
    feature.notifications['textDocument/didChange']!({
      'textDocument': {'uri': uri},
      'contentChanges': [
        {
          'range': {
            'start': {'line': 1, 'character': 8},
            'end': {'line': 1, 'character': 9},
          },
          'text': '42',
        },
        {
          'range': {
            'start': {'line': 0, 'character': 9},
            'end': {'line': 0, 'character': 10},
          },
          'text': 'e',
        },
      ],
    });
    expect(
      feature.session.workspace.textOf(path),
      "var a = 'e';\nvar b = 42;\n",
    );
    feature.notifications['textDocument/didChange']!({
      'textDocument': {'uri': uri},
      'contentChanges': [
        {'text': 'var c = 3;\n'},
      ],
    });
    expect(feature.session.workspace.textOf(path), 'var c = 3;\n');
  });

  test('the editor watches the files when it can; the scans stop', () {
    final editor = _Editor();
    final watched = sync(editor, watches: true);
    watched.notifications['initialized']!({});
    final (method, params) = editor.requests.single;
    expect(method, 'client/registerCapability');
    expect(
      params.toString(),
      allOf(contains('**/*.dart'), contains('**/*.{yaml,yml,properties}')),
    );
    expect(
      watched.session.workspace.scanInterval,
      const Duration(minutes: 1),
    );

    final unwatched = sync(_Editor(), watches: false);
    unwatched.notifications['initialized']!({});
    expect(
      unwatched.session.workspace.scanInterval,
      const Duration(seconds: 2),
    );
  });
}
