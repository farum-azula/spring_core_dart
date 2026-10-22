// The dart_spring language server: speaks LSP over stdin/stdout.
//
//   dart run bin/dart_spring_lsp.dart
//   dart compile exe bin/dart_spring_lsp.dart -o dart_spring_lsp
//
// Also creates projects: `dart_spring_lsp create my_app`.
import 'dart:io';

import 'package:dart_spring_language_server/src/create_project.dart';
import 'package:dart_spring_language_server/src/server.dart';

Future<void> main(List<String> args) async {
  switch (args.firstOrNull) {
    case 'create':
      exitCode = await createProject(args.skip(1).toList());
      return;
    case '--help' || '-h' || 'help':
      stdout
        ..writeln(
          'dart_spring_lsp            the language server (LSP over stdin/stdout)',
        )
        ..writeln()
        ..write(createUsage);
      return;
  }
  final code = await SpringLanguageServer(stdin, stdout).serve();
  await stdout.flush();
  exit(code);
}
