// spring.flutter.security.*: the properties class and its metadata.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/properties/bound_properties.dart';

Environment env(Map<String, String> values) =>
    StandardEnvironment()
      ..propertySources.addFirst(MapPropertySource('test', values));

void main() {
  test('defaults', () {
    final properties = boundSecurityProperties(env({}));
    expect(properties.applicationId, isNull);
    expect(properties.ephemeralSession, isFalse);
  });

  test('application id and ephemeral session', () {
    final properties = boundSecurityProperties(
      env({
        'spring.flutter.security.application-id': 'Neon\\Books',
        'spring.flutter.security.ephemeral-session': 'TRUE',
      }),
    );
    expect(properties.applicationId, 'Neon\\Books');
    expect(properties.ephemeralSession, isTrue);
  });

  test('the web settings are a class of their own', () {
    final values = {'spring.flutter.security.web.mode': 'nonsense'};
    // The security settings do not read them: a bad web value must not stop
    // an app on a phone (the web class is a bean on the web only).
    expect(boundSecurityProperties(env(values)).applicationId, isNull);
    expect(
      () => boundWebSecurityProperties(env(values)),
      throwsA(isA<ConfigurationPropertiesBindException>()),
    );
    expect(
      boundWebSecurityProperties(
        env({'spring.flutter.security.web.mode': 'spa'}),
      ).mode,
      WebLoginMode.spa,
    );
  });

  test('the metadata has every key, and the mode values', () {
    final json = jsonDecode(
      File('lib/spring_gen/spring_metadata.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final names = {
      for (final p in json['properties']! as List)
        (p as Map<String, Object?>)['name']! as String,
    };
    expect(names, {
      'spring.flutter.security.application-id',
      'spring.flutter.security.ephemeral-session',
      'spring.flutter.security.web.authorization-base-uri',
      'spring.flutter.security.web.logout-url',
      'spring.flutter.security.web.mode',
      'spring.flutter.security.web.server-url',
      'spring.flutter.security.web.silent-restore',
      'spring.flutter.security.web.user-endpoint',
    });
    final mode = (json['hints']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere(
          (h) => h['name'] == 'spring.flutter.security.web.mode',
        );
    expect(
      [for (final v in mode['values']! as List) (v as Map)['value']],
      ['server', 'spa'],
    );
  });
}
