// Differential test against Spring itself (roadmap/spring_boot_starter_data.md,
// step 4): the Spring Boot twin of the matrix scenarios (tool/data_reference,
// built with `mvn -q -DskipTests package`, Spring Boot 4.1, Spring Data JDBC,
// real `@Transactional` services) and the starter run the same scenarios on
// the same PostgreSQL server, each on a database of its own; the normalized
// outcomes (committed rows, values read, exception kinds) must be equal, or
// the difference is listed in `knownDifferences` with its reason. Without
// the built jar the test is skipped (it fails instead with
// DATA_REFERENCE_REQUIRED set, as in CI).
//
//   (cd tool/data_reference && mvn -q -DskipTests package)
//   SPRING_TEST_POSTGRES_URL=postgresql://postgres:test@localhost:5432/postgres \
//     dart test -t differential test/transaction_matrix/differential_test.dart
@Tags(['differential'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../postgres/support.dart';
import 'comparison.dart';
import 'env.dart';
import 'expectations.dart';
import 'expected_outcomes.dart';
import 'scenarios.dart';

/// [path] in this package (the tests also run from the workspace root).
File _packageFile(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_data/'),
  )!.resolve('../$path'),
);

final File _jar = _packageFile(
  '../tool/data_reference/target/data-reference-0.0.0.jar',
);

final bool _required =
    Platform.environment['DATA_REFERENCE_REQUIRED'] == 'true';

/// Why the test is skipped, or null.
String? get _skip {
  if (postgresSkip != null) {
    return postgresSkip;
  }
  if (!_jar.existsSync() && !_required) {
    return 'Build the Spring application first: '
        '(cd tool/data_reference && mvn -q -DskipTests package)';
  }
  return null;
}

/// Runs the Spring reference on a new database and returns its outcomes.
Future<Map<String, Object?>> _runSpring() async {
  final (url, dispose) = await createDatabase('spring_ref');
  final directory = Directory.systemTemp.createTempSync('data_reference');
  final out = File('${directory.path}/outcomes.json');
  try {
    final user = url.userInfo.split(':').map(Uri.decodeComponent).toList();
    final jdbcUrl = 'jdbc:postgresql://${url.host}:${url.port}${url.path}';
    final process = await Process.start('java', [
      '-jar',
      _jar.path,
      '--spring.datasource.url=$jdbcUrl',
      '--spring.datasource.username=${user.first}',
      '--spring.datasource.password=${user.length > 1 ? user[1] : ''}',
      '--out=${out.path}',
    ]);
    final log = StringBuffer();
    final drains = [
      process.stdout.transform(utf8.decoder).forEach(log.write),
      process.stderr.transform(utf8.decoder).forEach(log.write),
    ];
    final code = await process.exitCode.timeout(
      const Duration(minutes: 8),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await Future.wait(drains);
    if (code != 0) {
      fail('The Spring reference failed ($code):\n$log');
    }
    return jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
  } finally {
    await dispose();
    directory.deleteSync(recursive: true);
  }
}

/// Runs the scenarios of the starter; the outcomes as JSON.
Future<Map<String, Object?>> _runStarter() async {
  final outcomes = <String, Object?>{};
  await withEnv((env) async {
    for (final scenario in allScenarios()) {
      final outcome = await runScenario(env, scenario).timeout(
        const Duration(seconds: 60),
        onTimeout: () => {'TIMEOUT': true},
      );
      outcomes[scenario.id] = jsonDecode(jsonEncode(outcome));
    }
  });
  return outcomes;
}

void main() {
  group('the starter and Spring', () {
    late Map<String, Object?> spring;
    late Map<String, Object?> starter;

    setUpAll(() async {
      final runs = await Future.wait([_runSpring(), _runStarter()]);
      spring = runs[0];
      starter = runs[1];
    });

    final scenarios = allScenarios();
    for (final scenario in scenarios) {
      final id = scenario.id;
      final known = knownDifferences[id];
      if (known == null) {
        test(id, () {
          expect(starter[id], normalizeSpring(spring[id]));
        });
      } else {
        test('$id (deliberate: ${known.reason})', () {
          // Both sides are pinned: the difference neither grows nor
          // disappears unnoticed.
          expect(starter[id], known.starter);
          expect(normalizeSpring(spring[id]), expectedOutcomes[id]);
          expect(starter[id], isNot(normalizeSpring(spring[id])));
        });
      }
    }

    test('both sides ran the same scenarios', () {
      final ids = {for (final s in scenarios) s.id};
      expect(spring.keys.toSet(), ids);
      expect(starter.keys.toSet(), ids);
    });

    test('the propagation model is Spring', () {
      for (final id in spring.keys.where((k) => k.startsWith('propagation/'))) {
        expect(
          normalizeSpring(spring[id]),
          jsonDecode(jsonEncode(expectedOutcome(id))),
          reason: id,
        );
      }
    });
  }, skip: _skip);
}
