import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';

/// The `dart_spring` language server: answers an editor's questions about
/// a Spring project over the Language Server Protocol, as JSON-RPC
/// messages framed by `Content-Length` headers.
///
/// The editor runs it next to the Dart analysis server, which still
/// handles Dart itself; this server adds what needs Spring knowledge. Go
/// to definition leads from an injection point to its beans and from a
/// `${key}` to the property. Hover shows the candidate beans and the
/// values of a property. Semantic tokens colour placeholders, SpEL,
/// pointcuts and the parameters of closures. Diagnostics report invalid
/// SpEL, unknown keys and the like. [SpringWorkspace] does the work; this
/// class decodes the messages, tracks the open documents and encodes the
/// answers.
///
/// Documents are synchronised as full text on every change. Diagnostics
/// are published for the open documents only, 300 ms after the last
/// change or save. Semantic tokens are offered for whole documents, with
/// no modifiers. An unknown request gets "method not found"; a handler
/// that throws answers with an internal error and logs the stack trace
/// to stderr.
///
/// ```dart
/// // bin/dart_spring_lsp.dart: the editor starts the process and talks to
/// // it over stdin and stdout. Tests pass in-memory streams instead.
/// final code = await SpringLanguageServer(stdin, stdout).serve();
/// exit(code);
/// ```
final class SpringLanguageServer {
  /// A server that reads the editor's messages from the first argument (a
  /// byte stream such as stdin) and writes its answers and notifications to
  /// the second (such as stdout). Nothing happens until [serve].
  SpringLanguageServer(this._input, this._output);

  final Stream<List<int>> _input;
  final IOSink _output;
  SpringWorkspace? _workspace;
  final _open = <String>{};
  var _shutdown = false;
  Timer? _diagnostics;
  final _done = Completer<int>();

  /// Handles messages until the input ends or the editor sends `exit`, and
  /// completes with the exit code the protocol asks for: 0 when a
  /// `shutdown` request came first, 1 otherwise.
  Future<int> serve() {
    final buffer = <int>[];
    _input.listen(
      (chunk) {
        buffer.addAll(chunk);
        while (true) {
          final message = _takeMessage(buffer);
          if (message == null) {
            break;
          }
          _handle(message);
        }
      },
      onDone: () {
        if (!_done.isCompleted) {
          _done.complete(_shutdown ? 0 : 1);
        }
      },
    );
    return _done.future;
  }

  // `Content-Length: n\r\n\r\n<n bytes of JSON>`.
  static Map<String, Object?>? _takeMessage(List<int> buffer) {
    const separator = [13, 10, 13, 10];
    var headerEnd = -1;
    for (var i = 0; i + 3 < buffer.length; i++) {
      if (buffer[i] == separator[0] &&
          buffer[i + 1] == separator[1] &&
          buffer[i + 2] == separator[2] &&
          buffer[i + 3] == separator[3]) {
        headerEnd = i;
        break;
      }
    }
    if (headerEnd < 0) {
      return null;
    }
    final headers = ascii.decode(buffer.sublist(0, headerEnd));
    final match = RegExp(
      r'Content-Length:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(headers);
    if (match == null) {
      buffer.removeRange(0, headerEnd + 4);
      return null;
    }
    final length = int.parse(match.group(1)!);
    final start = headerEnd + 4;
    if (buffer.length < start + length) {
      return null;
    }
    final body = utf8.decode(buffer.sublist(start, start + length));
    buffer.removeRange(0, start + length);
    return jsonDecode(body) as Map<String, Object?>;
  }

  void _send(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
    _output
      ..add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'))
      ..add(body);
  }

  void _respond(Object? id, Object? result) =>
      _send({'id': id, 'result': result});

  void _error(Object? id, int code, String message) => _send({
    'id': id,
    'error': {'code': code, 'message': message},
  });

  void _handle(Map<String, Object?> message) {
    final method = message['method'] as String?;
    final id = message['id'];
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
    try {
      switch (method) {
        case 'initialize':
          _respond(id, _initialize(params));
        case 'initialized':
          _workspace?.refresh(force: true);
        case 'shutdown':
          _shutdown = true;
          _respond(id, null);
        case 'exit':
          _diagnostics?.cancel();
          if (!_done.isCompleted) {
            _done.complete(_shutdown ? 0 : 1);
          }
        case 'textDocument/didOpen':
          final document = params['textDocument']! as Map;
          final path = _path(document['uri']! as String);
          _open.add(path);
          _workspace?.setOverlay(path, document['text']! as String);
          _scheduleDiagnostics();
        case 'textDocument/didChange':
          final path = _path(
            (params['textDocument']! as Map)['uri']! as String,
          );
          final changes = params['contentChanges']! as List;
          if (changes.isNotEmpty) {
            _workspace?.setOverlay(
              path,
              (changes.last as Map)['text']! as String,
            );
          }
          _scheduleDiagnostics();
        case 'textDocument/didClose':
          final path = _path(
            (params['textDocument']! as Map)['uri']! as String,
          );
          _open.remove(path);
          _workspace?.setOverlay(path, null);
          _send({
            'method': 'textDocument/publishDiagnostics',
            'params': {
              'uri': Uri.file(path).toString(),
              'diagnostics': <Object?>[],
            },
          });
        case 'textDocument/didSave' || 'workspace/didChangeWatchedFiles':
          _workspace?.refresh(force: true);
          _scheduleDiagnostics();
        case 'textDocument/definition':
          _respond(id, _definition(params));
        case 'textDocument/hover':
          _respond(id, _hover(params));
        case 'textDocument/semanticTokens/full':
          _respond(id, _semanticTokens(params));
        default:
          if (id != null) {
            _error(id, -32601, 'Method not found: $method');
          }
      }
    } on Object catch (error, stackTrace) {
      stderr.writeln('dart_spring_lsp: $method failed: $error\n$stackTrace');
      if (id != null) {
        _error(id, -32603, '$error');
      }
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final roots = <String>[
      for (final folder in (params['workspaceFolders'] as List?) ?? const [])
        _path((folder as Map)['uri']! as String),
    ];
    if (roots.isEmpty) {
      final rootUri = params['rootUri'] as String?;
      final rootPath = params['rootPath'] as String?;
      if (rootUri != null) {
        roots.add(_path(rootUri));
      } else if (rootPath != null) {
        roots.add(rootPath);
      }
    }
    _workspace = SpringWorkspace(roots);
    return {
      'capabilities': {
        'positionEncoding': 'utf-16',
        'textDocumentSync': {
          'openClose': true,
          'change': 1, // full text
          'save': {'includeText': false},
        },
        'definitionProvider': true,
        'hoverProvider': true,
        'semanticTokensProvider': {
          'legend': {
            'tokenTypes': semanticTokenTypes,
            'tokenModifiers': <String>[],
          },
          'full': true,
        },
      },
      'serverInfo': {'name': 'dart_spring_lsp'},
    };
  }

  static String _path(String uri) => Uri.parse(uri).toFilePath();

  (String, int)? _position(Map<String, Object?> params) {
    final workspace = _workspace;
    if (workspace == null) {
      return null;
    }
    workspace.refresh();
    final path = _path((params['textDocument']! as Map)['uri']! as String);
    final position = params['position']! as Map;
    final file = workspace.file(path);
    if (file == null) {
      return null;
    }
    final line = position['line']! as int;
    final character = position['character']! as int;
    if (line >= file.lineInfo.lineCount) {
      return null;
    }
    return (path, file.lineInfo.getOffsetOfLine(line) + character);
  }

  Object? _definition(Map<String, Object?> params) {
    final at = _position(params);
    if (at == null) {
      return null;
    }
    final ranges = _workspace!.definition(at.$1, at.$2);
    if (ranges.isEmpty) {
      return null;
    }
    return [for (final range in ranges) _location(range)];
  }

  Object? _hover(Map<String, Object?> params) {
    final at = _position(params);
    if (at == null) {
      return null;
    }
    final text = _workspace!.hover(at.$1, at.$2);
    if (text == null) {
      return null;
    }
    return {
      'contents': {'kind': 'markdown', 'value': text},
    };
  }

  Object? _semanticTokens(Map<String, Object?> params) {
    final workspace = _workspace;
    if (workspace == null) {
      return {'data': <int>[]};
    }
    final path = _path((params['textDocument']! as Map)['uri']! as String);
    final data = <int>[];
    var line = 0;
    var column = 0;
    for (final token in workspace.semanticTokens(path)) {
      final deltaLine = token.line - line;
      final deltaColumn = deltaLine == 0 ? token.column - column : token.column;
      data.addAll([deltaLine, deltaColumn, token.length, token.type, 0]);
      line = token.line;
      column = token.column;
    }
    return {'data': data};
  }

  void _scheduleDiagnostics() {
    _diagnostics?.cancel();
    _diagnostics = Timer(
      const Duration(milliseconds: 300),
      _publishDiagnostics,
    );
  }

  void _publishDiagnostics() {
    final workspace = _workspace;
    if (workspace == null) {
      return;
    }
    workspace.refresh();
    for (final path in _open) {
      _send({
        'method': 'textDocument/publishDiagnostics',
        'params': {
          'uri': Uri.file(path).toString(),
          'diagnostics': [
            for (final problem in workspace.problems(path))
              {
                'range': _range(problem.range),
                'severity': problem.error ? 1 : 2,
                'source': 'dart_spring',
                'message': problem.message,
              },
          ],
        },
      });
    }
  }

  // An empty range at the start of the target: the editor moves the cursor
  // there without selecting the name or key.
  static Map<String, Object?> _location(SourceRange range) {
    final start = {'line': range.startLine, 'character': range.startColumn};
    return {
      'uri': Uri.file(range.path).toString(),
      'range': {'start': start, 'end': start},
    };
  }

  static Map<String, Object?> _range(SourceRange range) => {
    'start': {'line': range.startLine, 'character': range.startColumn},
    'end': {'line': range.endLine, 'character': range.endColumn},
  };
}
