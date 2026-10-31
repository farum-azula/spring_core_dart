// Known vulnerabilities of the packages the repository resolves: every
// hosted package of the lock files is looked up in the OSV database
// (osv.dev, which carries the GitHub advisories of pub.dev packages). Any
// advisory fails the check. Most important for the third-party
// `pointycastle` of the security packages (docs/dependencies.md).
//
// With `--maven <file>` it checks the Maven modules listed in the file
// too (`group:name:version`, one per line after `CLASSPATH `, as
// tool/gradle/build_classpath.init.gradle prints the Android build's
// classpath: the Android and Kotlin Gradle plugins and what they pull).
//
//   dart pub get
//   dart run tool/check_vulnerabilities.dart            # the pub workspace
//   dart run tool/check_vulnerabilities.dart --flutter  # the Flutter packages too
//   dart run tool/check_vulnerabilities.dart --maven /tmp/classpath.txt
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// The lock files of the Flutter packages (outside the pub workspace).
const _flutterLocks = [
  'spring_boot_starter_flutter/pubspec.lock',
  'spring_boot_starter_flutter_security/pubspec.lock',
  'example/flutter_guide/pubspec.lock',
];

/// The hosted packages of the lock file at [path]: name → version.
Map<String, String> hostedPackages(String path) {
  final lock = loadYaml(File(path).readAsStringSync()) as YamlMap;
  final packages = lock['packages'] as YamlMap? ?? YamlMap();
  return {
    for (final MapEntry(:key, :value) in packages.entries)
      if ((value as YamlMap)['source'] == 'hosted')
        key as String: value['version'] as String,
  };
}

/// The Maven modules in [text]: each line `CLASSPATH group:name:version`
/// (or `group:name:version` alone), as `(name, version)` pairs, once each.
Set<(String, String)> mavenModules(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (RegExp(
          r'^(?:CLASSPATH )?([\w.-]+:[\w.-]+):([\w.+-]+)$',
        ).firstMatch(line.trim())
        case final match?)
      (match[1]!, match[2]!),
};

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final locks = [
    'pubspec.lock',
    if (args.contains('--flutter')) ..._flutterLocks,
  ];
  final mavenFile = switch (args.indexOf('--maven')) {
    -1 => null,
    final i when i + 1 < args.length => args[i + 1],
    _ => throw ArgumentError('--maven needs a file'),
  };
  final maven = mavenFile == null
      ? <(String, String)>{}
      : mavenModules(File(mavenFile).readAsStringSync());
  if (mavenFile != null && maven.isEmpty) {
    stderr.writeln('$mavenFile lists no Maven module.');
    exit(1);
  }
  final packages = <String, String>{};
  for (final lock in locks) {
    if (!File(lock).existsSync()) {
      stderr.writeln('$lock is missing: run `pub get` there first.');
      exit(1);
    }
    for (final MapEntry(:key, :value) in hostedPackages(lock).entries) {
      packages['$key@$value'] = key;
    }
  }
  // name@version → (ecosystem, name).
  final entries = [
    for (final MapEntry(:key, :value) in packages.entries)
      MapEntry(key, ('Pub', value)),
    for (final (name, version) in maven)
      MapEntry('$name@$version', ('Maven', name)),
  ];
  final client = HttpClient();
  final found = <String>[];
  try {
    final request = await client.postUrl(
      Uri.https('api.osv.dev', '/v1/querybatch'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'queries': [
          for (final MapEntry(:key, value: (ecosystem, name)) in entries)
            {
              'package': {'name': name, 'ecosystem': ecosystem},
              'version': key.substring(name.length + 1),
            },
        ],
      }),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      stderr.writeln('osv.dev answered ${response.statusCode}: $body');
      exit(1);
    }
    final results = (jsonDecode(body) as Map)['results'] as List;
    for (final (i, result) in results.indexed) {
      final vulns = (result as Map)['vulns'] as List? ?? const [];
      for (final vuln in vulns) {
        found.add('${entries[i].key}: ${(vuln as Map)['id']}');
      }
    }
  } finally {
    client.close();
  }
  if (found.isNotEmpty) {
    stderr.writeln(
      'Known vulnerabilities (details: https://osv.dev/vulnerability/<id>):\n'
      '${found.map((f) => '  $f').join('\n')}',
    );
    exit(1);
  }
  stdout.writeln(
    'No known vulnerabilities in ${entries.length} packages '
    '(${[...locks, ?mavenFile].join(', ')}).',
  );
}
