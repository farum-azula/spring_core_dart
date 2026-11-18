// spring_boot_actuator's part of the module build: the application's
// `build-info.properties`, which the `info` endpoint shows.
import 'package:build/build.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:yaml/yaml.dart';

/// The part of `spring_boot_actuator` in the module build: an application
/// that lists the actuator (or its starter) among its `dependencies` gets
/// `build-info.properties` among its resources (Spring Boot's
/// `META-INF/build-info.properties`), with the name and version of its
/// `pubspec.yaml`, which the `info` endpoint shows.
///
/// Only for an application (`publish_to: none`): the example of a published
/// package would change with every release of the family. No build time,
/// so the generated code stays the same from one build to the next; an app
/// that wants it writes the file itself
/// (`lib/resources/build-info.properties`), which wins.
///
/// ```properties
/// build.artifact=shop
/// build.name=shop
/// build.version=1.2.0
/// ```
final class ActuatorGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const ActuatorGeneration();

  @override
  String get package => 'spring_boot_actuator';

  @override
  Future<Map<String, String>> applicationResources(BuildStep buildStep) async {
    final id = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    if (!await buildStep.canRead(id)) {
      return const {};
    }
    final Object? pubspec;
    try {
      pubspec = loadYaml(await buildStep.readAsString(id));
    } on YamlException {
      return const {};
    }
    if (pubspec is! YamlMap || '${pubspec['publish_to']}' != 'none') {
      return const {};
    }
    final dependencies = pubspec['dependencies'];
    final actuator =
        dependencies is YamlMap &&
        dependencies.keys.any(
          (name) =>
              name == 'spring_boot_actuator' ||
              name == 'spring_boot_starter_actuator',
        );
    if (!actuator) {
      return const {};
    }
    final name = '${pubspec['name'] ?? ''}';
    final version = pubspec['version'];
    return {
      'build-info.properties': [
        'build.artifact=$name',
        'build.name=$name',
        if (version != null) 'build.version=$version',
        '',
      ].join('\n'),
    };
  }
}
