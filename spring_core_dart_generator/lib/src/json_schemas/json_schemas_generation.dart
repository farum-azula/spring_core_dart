// The JSON Schemas' part of the module build: the classes of
// `spring.json.schemas` as a part of the module's library, their
// introspections and the downloaded schemas.
import 'package:build/build.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:spring_core_dart_generator/src/json_schemas/json_schema_classes.dart';

/// The part of the JSON Schemas of `spring.json.schemas` (a feature of
/// `spring_core_dart`'s `ObjectMapper`) in the module build: the library
/// the classes' file belongs to (the package's `@SpringBootApplication`
/// library, else its outermost `@ComponentScan`) gets
/// `json_schemas.spring.classes.dart` as a part, with the import it needs,
/// the list of the classes' introspections in its module, and the
/// downloaded schemas among its resources (`JsonSchemaLocations
/// .resourceOf`), so the `ObjectMapper` checks a JSON against them. The
/// classes builder ([JsonSchemasBuilder]) writes the file from the same
/// computation ([JsonSchemaPart.of]).
///
/// ```dart
/// // Output (in the module):
/// part 'json_schemas.spring.classes.dart';
///
/// BeanModule get $application => BeanModule(r'application', [...],
///   resources: const {r'json-schemas/example.com/user.json': ...},
///   introspections: [..._$jsonSchemaIntrospections]);
/// ```
final class JsonSchemasGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const JsonSchemasGeneration();

  @override
  String get package => 'spring_core_dart';

  @override
  Future<ModuleParts> moduleParts(BuildStep buildStep) async {
    final part = await JsonSchemaPart.of(buildStep);
    if (part == null || part.parent != buildStep.inputId) {
      return ModuleParts.none;
    }
    return ModuleParts(
      part.parts,
      part.imports,
      introspections: part.introspections,
      resources: part.resources,
    );
  }
}
