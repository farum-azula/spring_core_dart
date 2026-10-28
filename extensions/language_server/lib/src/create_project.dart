import 'dart:io';

import 'package:dart_spring_language_server/src/project_template.dart';

/// Runs `executable` with `arguments` in `workingDirectory`, letting its
/// output through, and returns its exit code. [createProject] takes one so
/// that tests can create a project without running `dart pub get`.
typedef ProcessRunner = Future<int> Function(
  String executable,
  List<String> arguments,
  String workingDirectory,
);

/// The help text of the `create` command, printed for `--help` and after a
/// missing argument.
const createUsage = '''
Creates a Spring Boot application (like Spring Initializr).

Usage:
  dart_spring_lsp create <directory> [options]

Options:
  --name=<package>   the package name (default: from the directory name)
  --no-pub           do not run `dart pub get` and `build_runner build`
  --force            write into a directory that is not empty

Examples:
  dart_spring_lsp create my_app
  dart_spring_lsp create .        # into the current (empty) directory
''';

/// Runs `dart_spring_lsp create <directory> [options]` with [args] (the
/// words after `create`) and returns the process exit code.
///
/// It writes [springBootProjectFiles] into the directory, then runs
/// `dart pub get` and `dart run build_runner build` there unless
/// `--no-pub` is given. A directory with visible files is refused unless
/// `--force` is given. Exit codes: 0 on success, 64 for a usage error (an
/// unknown option, no directory, an invalid `--name`), 73 for a directory
/// that is not empty, 1 when `pub get` or `build_runner` fails. Messages go
/// to [out] and [err] (stdout and stderr by default); [run] starts the
/// processes.
Future<int> createProject(
  List<String> args, {
  IOSink? out,
  IOSink? err,
  ProcessRunner? run,
}) => _create(args, out ?? stdout, err ?? stderr, run ?? _runProcess);

Future<int> _create(
  List<String> args,
  IOSink out,
  IOSink err,
  ProcessRunner run,
) async {
  String? target;
  String? name;
  var pub = true;
  var force = false;
  if (args.contains('--help') || args.contains('-h')) {
    out.write(createUsage);
    return 0;
  }
  for (final arg in args) {
    if (arg.startsWith('--name=')) {
      name = arg.substring('--name='.length);
    } else if (arg == '--no-pub') {
      pub = false;
    } else if (arg == '--force') {
      force = true;
    } else if (arg.startsWith('-')) {
      err.writeln("Unknown option '$arg'.");
      return 64;
    } else if (target == null) {
      target = arg;
    } else {
      err.writeln("Unexpected argument '$arg'.");
      return 64;
    }
  }
  if (target == null) {
    err
      ..writeln(
        'Where should the project go? e.g. dart_spring_lsp create my_app',
      )
      ..write(createUsage);
    return 64;
  }
  final directory = Directory(target).absolute;
  final path = directory.uri.normalizePath().toFilePath();
  final folder = Uri.directory(path).pathSegments
      .lastWhere((segment) => segment.isNotEmpty, orElse: () => 'app');
  name ??= packageNameFrom(folder);
  if (packageNameProblem(name) case final problem?) {
    err.writeln(problem);
    return 64;
  }
  if (!force && directory.existsSync()) {
    final visible = directory
        .listSync()
        .map((entity) => entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .where((entry) => !entry.startsWith('.'))
        .toList();
    if (visible.isNotEmpty) {
      err.writeln(
        '$path is not empty (${visible.take(3).join(', ')}'
        '${visible.length > 3 ? ', ...' : ''}). Choose an empty directory '
        'or pass --force.',
      );
      return 73;
    }
  }

  out.writeln('Creating Spring Boot application $name in $path');
  springBootProjectFiles(name).forEach((relative, content) {
    final file = File('${directory.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    out.writeln('  $relative');
  });

  if (pub) {
    out.writeln('\nRunning dart pub get ...');
    if (await run('dart', ['pub', 'get'], directory.path) != 0) {
      err.writeln('dart pub get failed; fix the problem and run it again.');
      return 1;
    }
    out.writeln('\nGenerating bin/main.spring.dart ...');
    final built = await run('dart', [
      'run',
      'build_runner',
      'build',
    ], directory.path);
    if (built != 0) {
      err.writeln('build_runner failed; run `dart run build_runner build`.');
      return 1;
    }
  }

  final cd = target == '.' ? '' : '  cd $target\n';
  out.write('''

Done. Next:
$cd${pub ? '' : '  dart pub get\n  dart run build_runner build\n'}  dart run bin/main.dart
  dart test

Beans go to lib/src/, configuration to lib/resources/application.properties.
After changing beans: dart run build_runner build (or watch).
''');
  return 0;
}

Future<int> _runProcess(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode;
}
