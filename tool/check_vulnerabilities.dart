// Known vulnerabilities of the packages the repository resolves: every
// hosted package of the lock files is looked up in the OSV database
// (osv.dev, which carries the GitHub advisories of pub.dev packages). Any
// advisory fails the check. Most important for the third-party
// `pointycastle` of the security packages (docs/dependencies.md).
//
//   dart pub get
//   dart run tool/check_vulnerabilities.dart            # the pub workspace
//   dart run tool/check_vulnerabilities.dart --flutter  # the Flutter packages too
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// The lock files of the Flutter packages (outside the pub workspace).
const _flutterLocks = [
  'spring_boot_starter_flutter/pubspec.lock',
  'example/flutter_counter/pubspec.lock',
  'example/flutter_themes/pubspec.lock',
  'example/flutter_notes/pubspec.lock',
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

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final locks = [
    'pubspec.lock',
    if (args.contains('--flutter')) ..._flutterLocks,
  ];
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
  final entries = packages.entries.toList();
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
          for (final MapEntry(:key, :value) in entries)
            {
              'package': {'name': value, 'ecosystem': 'Pub'},
              'version': key.substring(value.length + 1),
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
    '(${locks.join(', ')}).',
  );
}
