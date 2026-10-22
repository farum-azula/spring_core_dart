// The flutter_spring language server: speaks LSP over stdin/stdout.
//
//   dart run bin/flutter_spring_lsp.dart
//   dart compile exe bin/flutter_spring_lsp.dart -o flutter_spring_lsp
import 'dart:io';

import 'package:flutter_spring_language_server/src/server.dart';

Future<void> main() async {
  final code = await SpringLanguageServer(stdin, stdout).serve();
  await stdout.flush();
  exit(code);
}
