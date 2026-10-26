// Dependency policy: the packages of this repository use only each other,
// the Dart SDK and packages published by the Dart / Google teams on
// pub.dev — transitive dependencies included. Anything else needs an entry
// in [allowedPackages] with a reason (and, ideally, the workspace packages
// allowed to pull it).
//
//   dart pub get
//   dart run tool/check_dependencies.dart
//   dart run tool/check_dependencies.dart --flutter   # the Flutter packages
//
// Run in CI after `dart pub get`; it asks pub.dev who publishes each hosted
// package. The Flutter packages are outside the pub workspace (flutter_test
// pins package versions that the workspace's package:test cannot use):
// `--flutter` checks each of [flutterPackages] from its own lock file
// (after `flutter pub get` there), with the packages of this repository it
// reaches by path.
import 'dart:convert';
import 'dart:io';

/// pub.dev publishers whose packages are allowed: the Dart and Google
/// teams.
const allowedPublishers = {
  'dart.dev',
  'tools.dart.dev',
  'labs.dart.dev',
  'google.dev',
  'flutter.dev',
};

/// Packages that end up in applications: their (non-dev) dependencies must
/// be packages of this repository only, not even Dart-team packages. New
/// runtime starters belong here too.
const repositoryOnly = {
  'spring_core_dart',
  'spring_boot_dart',
  'spring_boot_starter_logging',
  'spring_boot_starter_scheduling',
  'spring_boot_starter_cache',
  'spring_web_dart',
  'spring_boot_starter_feign',
  'spring_boot_starter_websocket',
  'spring_boot_starter_web',
  'spring_boot_starter_flutter',
};

/// Packages outside the pub workspace, with their own resolution (Flutter:
/// `flutter_test` pins versions the workspace cannot use); checked with
/// `--flutter`. The Flutter SDK's packages count as the SDK.
const flutterPackages = [
  'spring_boot_starter_flutter',
  'example/flutter_counter',
  'example/flutter_themes',
  'example/flutter_notes',
];

/// Dart-team packages that [repositoryOnly] packages may depend on anyway,
/// with the reason (their own dependencies must still be the Dart team's).
const repositoryOnlyExceptions = {
  'yaml':
      "application.yml config files out of the box, like Spring Boot's "
      'SnakeYAML; the Dart team\'s YAML parser (spring_core_dart).',
};

/// A package allowed although it is not published by the Dart team.
final class AllowedPackage {
  /// Allows a package for [reason]; only the workspace packages in [onlyIn]
  /// may pull it (any of them when `null`). What it depends on is allowed
  /// too, but only through it.
  const AllowedPackage(this.reason, {this.onlyIn});

  /// Why it is allowed.
  final String reason;

  /// Workspace packages that may depend on it (directly or not).
  final Set<String>? onlyIn;
}

/// Exceptions to [allowedPublishers]. Database drivers will be added here,
/// e.g.:
///
/// ```dart
/// 'sqlite3': AllowedPackage(
///   'SQLite driver of spring_boot_starter_data_sqlite',
///   onlyIn: {'spring_boot_starter_data_sqlite'},
/// ),
/// ```
const allowedPackages = {
  'melos': AllowedPackage(
    'Workspace scripts (`dart run melos run check`); a dev tool of the '
    'workspace root, never a dependency of a package.',
    onlyIn: {'spring_core_dart_workspace'},
  ),
  'material_color_utilities': AllowedPackage(
    "Part of the Flutter SDK (package:flutter depends on it, pinned by the "
    "SDK); published by Google's material.io.",
    onlyIn: {
      'spring_boot_starter_flutter',
      'flutter_counter',
      'flutter_themes',
      'flutter_notes',
    },
  ),
  'node_preamble': AllowedPackage(
    'Pulled by package:test (Dart team) for browser tests; it has no '
    'publisher on pub.dev.',
  ),
};

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  if (args.contains('--flutter')) {
    for (final directory in flutterPackages) {
      await _check(directory, standalone: true);
    }
  } else {
    await _check('.', standalone: false);
  }
}

/// Checks the resolution of [directory]: the workspace root, or a
/// [standalone] package whose repository packages come by path.
Future<void> _check(String directory, {required bool standalone}) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: directory);
  if (result.exitCode != 0) {
    stderr.writeln(
      'pub deps failed in $directory (run `${standalone ? 'flutter' : 'dart'} '
      'pub get` there first):',
    );
    stderr.write(result.stderr);
    exit(1);
  }
  final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final packages = {
    for (final package
        in (json['packages']! as List).cast<Map<String, Object?>>())
      package['name']! as String: package,
  };
  // The workspace packages; for a standalone package, itself and the
  // packages of this repository it reaches by path (checked by the
  // workspace run themselves).
  final workspace = {
    for (final MapEntry(:key, :value) in packages.entries)
      if (value['kind'] == 'root' || (standalone && value['source'] == 'path'))
        key,
  };

  // Every package reachable from a workspace package, with one path to it;
  // packages under an allowed exception are skipped.
  final reached = <String, List<String>>{};
  // Exceptions only for the Flutter packages are reported by those runs.
  final flutterNames = {
    for (final path in flutterPackages) path.split('/').last,
  };
  final unusedExceptions = {
    for (final MapEntry(:key, :value) in allowedPackages.entries)
      if (standalone == (value.onlyIn?.every(flutterNames.contains) ?? false))
        key,
  };
  for (final root in workspace) {
    final pending = <List<String>>[
      for (final dependency in _dependencies(packages[root]!))
        [root, dependency],
    ];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      final name = path.last;
      if (workspace.contains(name) || !seen.add(name)) {
        continue; // workspace packages are checked as roots themselves
      }
      final exception = allowedPackages[name];
      if (exception != null &&
          (exception.onlyIn == null || exception.onlyIn!.contains(root))) {
        unusedExceptions.remove(name);
        continue;
      }
      reached.putIfAbsent(name, () => path);
      final package = packages[name];
      if (package != null) {
        for (final dependency in _dependencies(package)) {
          pending.add([...path, dependency]);
        }
      }
    }
  }

  final problems = <String>[];
  for (final name in repositoryOnly) {
    final package = packages[name];
    final here = standalone
        ? (package != null && package['kind'] == 'root')
        : !flutterPackages.contains(name);
    if (!here) {
      continue; // checked with (or without) --flutter
    }
    if (package == null) {
      problems.add('$name: listed in repositoryOnly but not in the workspace');
      continue;
    }
    for (final dependency
        in ((package['directDependencies'] as List?) ?? const [])
            .cast<String>()) {
      // The Flutter SDK (`flutter: sdk: flutter`) counts as the SDK.
      if (!workspace.contains(dependency) &&
          packages[dependency]?['source'] != 'sdk' &&
          !repositoryOnlyExceptions.containsKey(dependency)) {
        problems.add(
          '$dependency: a dependency of $name, which may depend only on '
          'packages of this repository (repositoryOnly)',
        );
      }
    }
  }
  final hosted = <String>[];
  for (final MapEntry(key: name, value: path) in reached.entries) {
    final source = packages[name]?['source'];
    if (source == 'sdk') {
      continue;
    }
    if (source == 'hosted') {
      hosted.add(name);
    } else {
      problems.add('$name: from $source, not pub.dev (${path.join(' → ')})');
    }
  }
  final publishers = await _publishers(hosted);
  for (final name in hosted..sort()) {
    final publisher = publishers[name];
    if (!allowedPublishers.contains(publisher)) {
      problems.add(
        '$name: published by ${publisher ?? 'nobody (no verified publisher)'}'
        ' (${reached[name]!.join(' → ')})',
      );
    }
  }

  if (problems.isNotEmpty) {
    stderr
      ..writeln(
        '${standalone ? '$directory: ' : ''}Dependencies outside the policy (this repository, the Dart SDK and '
        'packages published by ${allowedPublishers.join(', ')}):',
      )
      ..writeln(problems.map((problem) => '  - $problem').join('\n'))
      ..writeln(
        'Remove them, or add an exception with a reason to allowedPackages '
        'in tool/check_dependencies.dart.',
      );
    exit(1);
  }
  if (standalone) {
    stdout.writeln(
      '$directory: dependencies ok (${hosted.length} packages from pub.dev, '
      'all published by the Dart and Flutter teams).',
    );
    return;
  }
  stdout.writeln(
    'Dependencies ok: ${repositoryOnly.join(', ')} depend only on this '
    'repository (and ${repositoryOnlyExceptions.keys.join(', ')}); ${hosted.length} packages from pub.dev, all published by '
    'the Dart team; exceptions: ${allowedPackages.keys.join(', ')}.',
  );
  if (unusedExceptions.isNotEmpty) {
    stdout.writeln(
      'Exceptions no longer needed: ${unusedExceptions.join(', ')} '
      '(remove them from allowedPackages).',
    );
  }
}

List<String> _dependencies(Map<String, Object?> package) => [
  ...((package['dependencies'] as List?) ?? const []).cast<String>(),
];

// The pub.dev publisher of each package (`null`: none), a few requests at
// a time, with retries.
Future<Map<String, String?>> _publishers(List<String> names) async {
  final client = HttpClient();
  final result = <String, String?>{};
  try {
    final queue = [...names];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final name = queue.removeLast();
        result[name] = await _publisher(client, name);
      }
    }

    await Future.wait([for (var i = 0; i < 8; i++) worker()]);
  } finally {
    client.close();
  }
  return result;
}

Future<String?> _publisher(HttpClient client, String name) async {
  final url = Uri.https('pub.dev', '/api/packages/$name/publisher');
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return (jsonDecode(body) as Map)['publisherId'] as String?;
      }
      lastError = 'HTTP ${response.statusCode}';
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(Duration(seconds: attempt + 1));
  }
  stderr.writeln('Could not ask pub.dev who publishes $name: $lastError');
  exit(1);
}
