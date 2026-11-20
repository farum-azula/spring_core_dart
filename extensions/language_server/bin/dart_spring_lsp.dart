// The dart_spring language server: speaks LSP over stdin/stdout.
//
//   dart run bin/dart_spring_lsp.dart
//   dart compile exe bin/dart_spring_lsp.dart -o dart_spring_lsp
//
// Also creates projects: `dart_spring_lsp create my_app`, and prints its
// version: `dart_spring_lsp --version` (the editor extensions start a server
// from the PATH only when it is their own version).
import 'dart:io';

import 'package:dart_spring_language_server/src/create_project.dart';
import 'package:dart_spring_language_server/src/server.dart';
// The family is versioned in lockstep (tool/version.dart): the server's
// version is spring_boot_dart's.
import 'package:spring_boot_dart/src/version.dart';

Future<void> main(List<String> args) async {
  switch (args.firstOrNull) {
    case 'create':
      exitCode = await createProject(args.skip(1).toList());
      return;
    case '--version':
      stdout.writeln('dart_spring_lsp $springBootVersion');
      return;
    case '--help' || '-h' || 'help':
      stdout
        ..writeln(
          'dart_spring_lsp            the language server (LSP over stdin/stdout)',
        )
        ..writeln('dart_spring_lsp --version  its version')
        ..writeln()
        ..write(createUsage);
      return;
  }
  final code = await SpringLanguageServer(stdin, stdout).serve();
  await stdout.flush();
  exit(code);
}
