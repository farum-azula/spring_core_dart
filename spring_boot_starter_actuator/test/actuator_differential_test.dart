// Differential test against Spring Boot Actuator itself: the reference
// application of tool/security_reference (profile `actuator`,
// application-actuator.properties) and the Dart test application get the
// same requests with the same management.* settings; the statuses, the
// media types and the JSON must be the same.
//
// What differs on purpose, normalized below:
// - the disk's sizes and the hosts and ports of the links change from
//   run to run;
// - Spring Boot 4 has an `ssl` indicator (certificate chains of SSL
//   bundles), the Dart application its own `inbox`;
// - the order of the keys (Jackson 3 sorts them; JSON objects have no
//   order).
//
// Without the built jar the test is skipped (CI's differential job builds
// it):
//
//   (cd tool/security_reference && mvn -q -DskipTests package)
//   dart test spring_boot_starter_actuator/test/actuator_differential_test.dart
@Tags(['differential'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_actuator/spring_boot_starter_actuator.dart';
import 'package:test/test.dart';

import 'support.dart';

final File _jar = _packageFile(
  '../tool/security_reference/target/security-reference-0.0.0.jar',
);

File _packageFile(String path) {
  final uri = Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_actuator/'),
  )!;
  return File.fromUri(uri.resolve('../$path'));
}

/// The settings of application-actuator.properties.
const _settings = [
  'management.endpoints.web.exposure.include=health,info',
  'management.endpoint.health.show-details=always',
  'management.endpoint.health.probes.enabled=true',
  'management.endpoint.health.probes.add-additional-paths=true',
  'management.endpoint.health.group.core.include=ping',
  'management.endpoint.health.group.core.show-details=never',
  'management.endpoint.health.group.core.show-components=always',
  'management.info.env.enabled=true',
  'info.app.name=reference',
  'info.app.team=books',
];

/// One answer: the status, the media type and the JSON, normalized.
final class Answer {
  Answer(this.status, this.type, this.body);

  final int status;
  final String? type;
  final Object? body;

  Map<String, Object?> toMap() => {
    'status': status,
    'type': type,
    'body': body,
  };

  @override
  String toString() => jsonEncode(toMap());
}

Future<Answer> _ask(
  int port,
  String path, {
  String method = 'GET',
  String? accept,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    if (accept != null) {
      request.headers.set(HttpHeaders.acceptHeader, accept);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return Answer(
      response.statusCode,
      response.statusCode == 200
          ? response.headers.contentType?.mimeType
          : null,
      text.isEmpty ? null : _normalize(jsonDecode(text), port),
    );
  } finally {
    client.close();
  }
}

// The values that change from run to run, and the indicators only one
// side has.
Object? _normalize(Object? value, int port) => switch (value) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries)
      if (key != 'ssl' && key != 'inbox')
        key: switch (key) {
          'total' || 'free' when value is int => '<bytes>',
          'path' when value is String => '<path>',
          'href' when value is String => value.replaceFirst(
            '127.0.0.1:$port',
            'host',
          ),
          _ => _normalize(value, port),
        },
  },
  final List<Object?> list => [for (final item in list) _normalize(item, port)],
  _ => value,
};

/// The requests both applications get.
const _requests = <(String, String?)>[
  ('/actuator', null),
  ('/actuator/', null),
  ('/actuator/health', null),
  ('/actuator/health/', null),
  ('/actuator/health/ping', null),
  ('/actuator/health/diskSpace', null),
  ('/actuator/health/nope', null),
  ('/actuator/health/core', null),
  ('/actuator/health/core/ping', null),
  ('/actuator/health/liveness', null),
  ('/actuator/health/liveness/livenessState', null),
  ('/actuator/health/readiness', null),
  ('/livez', null),
  ('/readyz', null),
  ('/actuator/info', null),
  ('/actuator/health', 'application/json'),
  ('/actuator/health', 'application/vnd.spring-boot.actuator.v2+json'),
  ('/actuator/health', 'application/vnd.spring-boot.actuator.v3+json'),
  ('/actuator/info', '*/*'),
];

void main() {
  Process? spring;
  late int springPort;

  setUpAll(() async {
    if (!_jar.existsSync()) {
      if (Platform.environment.containsKey('SECURITY_REFERENCE_REQUIRED')) {
        throw StateError('${_jar.path} is missing');
      }
      return;
    }
    final probe = await ServerSocket.bind('127.0.0.1', 0);
    springPort = probe.port;
    await probe.close();
    spring = await Process.start('java', [
      '-jar',
      _jar.path,
      '--spring.profiles.active=actuator',
      '--server.port=$springPort',
      '--server.address=127.0.0.1',
    ]);
    unawaited(spring!.stderr.drain<void>());
    unawaited(spring!.stdout.drain<void>());
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if ((await _ask(springPort, '/actuator/health')).status == 200) {
          return;
        }
      } on Object {
        // Not listening yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    spring!.kill();
    throw StateError('The Spring reference (profile actuator) did not start');
  });

  tearDownAll(() => spring?.kill());

  test('the same answers as Spring Boot Actuator', () async {
    if (spring == null) {
      markTestSkipped('${_jar.path} is not built');
      return;
    }
    await actuatorRunner([
      'spring.test.web-environment=random-port',
      'server.address=127.0.0.1',
      ..._settings,
    ]).runAsync((context) async {
      expect(context.startupFailure, isNull);
      // What SpringApplication publishes once the application is ready.
      AvailabilityChangeEvent.publish(context.context, LivenessState.correct);
      AvailabilityChangeEvent.publish(
        context.context,
        ReadinessState.acceptingTraffic,
      );
      final server = await context
          .getBean<WebServerStartStopLifecycle>()
          .started;
      final dartPort = server!.port;
      final differences = <String>[];
      for (final (path, accept) in _requests) {
        final theirs = await _ask(springPort, path, accept: accept);
        final ours = await _ask(dartPort, path, accept: accept);
        final label = '$path${accept == null ? '' : ' (Accept: $accept)'}';
        // `/actuator/` is not an endpoint for either; Spring's security
        // answers it 401 (the reference's other chain), the Dart
        // application, without security, 404.
        if (path == '/actuator/') {
          expect(theirs.status, isNot(200), reason: label);
          expect(ours.status, 404, reason: label);
          continue;
        }
        if (!const DeepCollectionEquality().equals(
          theirs.toMap(),
          ours.toMap(),
        )) {
          differences.add('$label\n  Spring: $theirs\n  Dart:   $ours');
        }
      }
      expect(differences, isEmpty, reason: differences.join('\n'));

      // HEAD: the GET's status without a body.
      final head = await _ask(dartPort, '/actuator/health', method: 'HEAD');
      final springHead = await _ask(
        springPort,
        '/actuator/health',
        method: 'HEAD',
      );
      expect(head.status, springHead.status);
      expect(head.body, isNull);
    });
  });
}

/// Deep equality of JSON values, without the order of map keys.
final class DeepCollectionEquality {
  const DeepCollectionEquality();

  bool equals(Object? a, Object? b) => switch ((a, b)) {
    (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
      x.length == y.length &&
          x.keys.every((key) => y.containsKey(key) && equals(x[key], y[key])),
    (final List<Object?> x, final List<Object?> y) =>
      x.length == y.length &&
          [for (var i = 0; i < x.length; i++) i].every(
            (i) => equals(x[i], y[i]),
          ),
    _ => a == b,
  };
}
