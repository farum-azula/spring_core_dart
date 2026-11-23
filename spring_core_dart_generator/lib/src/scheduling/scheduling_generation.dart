// spring_boot_starter_scheduling's part of the module build: a `@Scheduled`
// method reads and writes none of its values as JSON.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

// Matched by URL (the generator does not depend on the starter).
const _scheduled = TypeChecker.fromUrl(
  'package:spring_boot_starter_scheduling/src/scheduled.dart#Scheduled',
);

/// The part of `spring_boot_starter_scheduling` in the module build: the
/// scheduler calls a `@Scheduled` method without reading or writing its
/// values, so the build describes none of its types for it (an annotation
/// of a `@BeanMethodAnnotation()` it did not know would have them
/// described entirely). It writes nothing of its own.
final class SchedulingGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const SchedulingGeneration();

  @override
  String get package => 'spring_boot_starter_scheduling';

  @override
  List<AnnotationPlacement> get placements => const [
    MethodPlacement([_scheduled], does: 'the scheduler runs it'),
  ];

  @override
  AnnotatedMethodNeeds? methodNeeds(
    InterfaceType annotation,
    MethodElement method,
    ModuleScan scan,
  ) => _scheduled.isExactlyType(annotation)
      ? (
          result: IntrospectionNeed.none,
          parameters: [
            for (final _ in method.formalParameters) IntrospectionNeed.none,
          ],
        )
      : null;
}
