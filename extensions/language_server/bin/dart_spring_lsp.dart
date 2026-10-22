// The dart_spring language server: speaks LSP over stdin/stdout.
//
//   dart run bin/dart_spring_lsp.dart
//   dart compile exe bin/dart_spring_lsp.dart -o dart_spring_lsp
import 'dart:io';

import 'package:dart_spring_language_server/src/server.dart';

Future<void> main() async {
  final code = await SpringLanguageServer(stdin, stdout).serve();
  await stdout.flush();
  exit(code);
}
