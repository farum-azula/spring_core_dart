// spring_boot_actuator's part of the module build: the application's
// `build-info.properties`, which the `info` endpoint shows.
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
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
// The endpoint annotations, matched by URL (the generator does not depend
// on the actuator).
const _annotations =
    'package:spring_boot_actuator/src/endpoint/annotations.dart';
const _endpoint = TypeChecker.fromUrl('$_annotations#Endpoint');
const _webExtension = TypeChecker.fromUrl('$_annotations#EndpointWebExtension');
const _readOperation = TypeChecker.fromUrl('$_annotations#ReadOperation');

// `@Endpoint`: a class with an operation (its own or inherited); without
// one the endpoint answers nothing.
final class _EndpointPlacement extends ClassPlacement {
  const _EndpointPlacement() : super(const [_endpoint]);

  @override
  String? problem(AnnotationSite site) {
    if (super.problem(site) case final problem?) {
      return problem;
    }
    final element = site.element;
    if (element is! ClassElement) {
      return null;
    }
    final classes = [element, ...element.allSupertypes.map((t) => t.element)];
    return classes.any(
          (current) => current.methods.any(_readOperation.hasAnnotationOf),
        )
        ? null
        : '@Endpoint on ${site.subject}: it has no operation, so it would '
              'answer nothing. Add a method with @ReadOperation().';
  }
}

/// The part of `spring_boot_actuator` in the module build.
final class ActuatorGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const ActuatorGeneration();

  @override
  String get package => 'spring_boot_actuator';

  // An operation of an endpoint, and its selectors.
  @override
  List<AnnotationPlacement> get placements => const [
    MethodPlacement(
      [_readOperation],
      does: 'the endpoint answers with it',
      methodOwner: AnnotatedOwner([_endpoint, _webExtension]),
      ownerNoun: '@Endpoint (or @EndpointWebExtension)',
      ownerFix: "@Endpoint('...')",
    ),
    ParameterPlacement(
      [TypeChecker.fromUrl('$_annotations#Selector')],
      methodsWith: [_readOperation],
      methodNoun: 'an endpoint operation (@ReadOperation)',
    ),
    _EndpointPlacement(),
  ];

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
