import 'dart:convert';
import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart/src/core/env/core_properties.dart';
import 'package:test/test.dart';

// The core reads `spring.config.*`, `spring.profiles.*` and
// `spring.main.cloud-platform` by name, while it builds the environment:
// no binder exists yet (it lives in spring_boot_dart). The classes of
// core_properties.dart describe the same keys, and the editor metadata is
// generated from them. These tests keep the two from drifting apart: the
// keys the readers use are the keys of the classes, and the defaults of
// the classes are the defaults the readers apply.
void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('core_properties_');
    root = temp.path.replaceAll(r'\', '/');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  StandardEnvironment env([Map<String, Object?> props = const {}]) =>
      StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(MapPropertySource('cli', props));

  void process(StandardEnvironment environment) => ConfigDataEnvironment(
    environment,
    defaultLocations: ['optional:file:$root/'],
  ).processAndApplySync();

  test('the keys the readers use are the keys of the classes', () {
    final metadata = jsonDecode(
      File('lib/spring_gen/spring_metadata.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final described = {
      for (final property in metadata['properties']! as List<Object?>)
        (property! as Map<String, Object?>)['name']! as String,
    };
    final read = {
      ConfigDataEnvironment.configNameProperty,
      ConfigDataEnvironment.locationProperty,
      ConfigDataEnvironment.additionalLocationProperty,
      ConfigDataEnvironment.importProperty,
      ConfigDataEnvironment.onProfileProperty,
      ConfigDataEnvironment.onCloudPlatformProperty,
      ConfigDataEnvironment.onNotFoundProperty,
      ConfigDataEnvironment.includeProfilesProperty,
      '${ConfigDataEnvironment.profileGroupPrefix}*',
      ConfigDataEnvironment.validateProfilesProperty,
      StandardEnvironment.activeProfilesPropertyName,
      StandardEnvironment.defaultProfilesPropertyName,
      CloudPlatform.propertyName,
    };
    expect(read, described);
  });

  test('the base name defaults to the class default', () {
    File('$root/${ConfigProperties().name.single}.properties')
        .writeAsStringSync('from.default=yes');
    final e = env();
    process(e);
    expect(e.getProperty('from.default'), 'yes');
  });

  test('on-not-found defaults to the class default', () {
    expect(ConfigProperties().onNotFound, OnNotFound.fail);
    expect(
      () => process(
        env({'spring.config.import': 'file:$root/missing.properties'}),
      ),
      throwsA(isA<ConfigDataResourceNotFoundException>()),
    );
  });

  test('profile names are validated by default, like the class', () {
    expect(ProfilesProperties().validate, isTrue);
    expect(
      () => process(env({'spring.profiles.active': 'dev!'})),
      throwsA(isA<StateError>()),
    );
  });

  test('the profile lists have no value and no default profile set', () {
    final properties = ProfilesProperties();
    expect(properties.active, isNull);
    expect(properties.include, isNull);
    expect(properties.defaults, isNull);
    expect(properties.group, isEmpty);
    final e = env();
    process(e);
    expect(e.activeProfiles, isEmpty);
    expect(e.defaultProfiles, [StandardEnvironment.reservedDefaultProfileName]);
  });

  test('the other settings have no value by default', () {
    final config = ConfigProperties();
    expect(config.location, isNull);
    expect(config.additionalLocation, isNull);
    expect(config.imports, isNull);
    expect(CloudPlatformProperties().cloudPlatform, isNull);
  });
}
