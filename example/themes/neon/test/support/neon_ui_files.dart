import 'dart:convert';
import 'dart:io';

/// A file of the neon_ui package by its [path] in the package (wherever
/// pub put it: the git cache of github.com/farum-azula/themes), found in
/// `.dart_tool/package_config.json`.
File neonUiFile(String path) {
  final config = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final neonUi = packages.cast<Map<String, Object?>>().firstWhere(
    (package) => package['name'] == 'neon_ui',
  );
  final root = config.uri.resolve(neonUi['rootUri']! as String);
  return File.fromUri(
    root.path.endsWith('/') ? root.resolve(path) : Uri.parse('$root/$path'),
  );
}
