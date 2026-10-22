// Compiles the dart_spring language server to a native executable and
// installs it as `dart_spring_lsp` in ~/.pub-cache/bin (on the PATH of
// most Dart setups), where the editor extensions find it.
//
//   dart run tool/install_language_server.dart            # install
//   dart run tool/install_language_server.dart <dir>      # into <dir>
//
// A native executable, not `dart pub global run`: pub prints resolution
// messages to stdout, which is the channel the editor talks LSP on.
import 'dart:io';

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final directory = args.isNotEmpty
      ? args.first
      : Platform.environment['PUB_CACHE'] != null
      ? '${Platform.environment['PUB_CACHE']}/bin'
      : '$home/.pub-cache/bin';
  Directory(directory).createSync(recursive: true);
  final output =
      '$directory/dart_spring_lsp${Platform.isWindows ? '.exe' : ''}';
  final result = await Process.start(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'extensions/language_server/bin/dart_spring_lsp.dart',
    '-o',
    output,
  ], mode: ProcessStartMode.inheritStdio);
  if (await result.exitCode != 0) {
    stderr.writeln('Compilation failed.');
    exit(1);
  }
  stdout.writeln('\nInstalled $output');
  final path = Platform.environment['PATH'] ?? '';
  if (!path.split(Platform.isWindows ? ';' : ':').contains(directory)) {
    stdout.writeln(
      'Note: $directory is not on your PATH; add it, or set '
      'lsp.dart-spring.binary.path in Zed settings to $output.',
    );
  }
}
