import 'package:spring_boot_actuator/src/endpoint/annotations.dart';
import 'package:spring_boot_actuator/src/endpoint/operation.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show MappingDescriptions;

/// The `mappings` endpoint: every address the application answers, from
/// every [MappingDescriptions] bean, under its `mappingsName`.
///
/// The web starter's bean describes the server's handlers
/// (`dispatcherHandlers`, in Spring WebFlux's shape); the navigation
/// starter's an app's screens (`screens`, our addition).
///
/// ```json
/// {"contexts": {"application": {"mappings": {
///   "dispatcherHandlers": {"webHandler": [
///     {"predicate": "{GET [/api/books/{isbn}]}",
///      "handler": "BookController#find(String)", "details": {...}}]}},
///   "parentId": null}}}
/// ```
///
/// Spring Boot (Java): `MappingsEndpoint`.
@Endpoint(id: 'mappings')
class MappingsEndpoint {
  /// The endpoint of [descriptions] for the context [contextId].
  MappingsEndpoint(
    List<MappingDescriptions> descriptions, {
    this.contextId = 'application',
  }) : descriptions = List.unmodifiable(descriptions);

  /// The beans describing the mappings.
  final List<MappingDescriptions> descriptions;

  /// The application context's id, the key under `contexts`.
  final String contextId;

  /// The mappings of every [MappingDescriptions] bean.
  @ReadOperation()
  ApplicationMappingsDescriptor mappings() => ApplicationMappingsDescriptor({
    contextId: ContextMappingsDescriptor({
      for (final description in descriptions)
        description.mappingsName: description.describeMappings(),
    }),
  });
}

/// The answer of the `mappings` endpoint: the mappings of each
/// application context by its id.
///
/// Spring Boot (Java): `MappingsEndpoint.ApplicationMappingsDescriptor`.
final class ApplicationMappingsDescriptor implements OperationResponseBody {
  /// The mappings of [contexts], by context id.
  ApplicationMappingsDescriptor(Map<String, ContextMappingsDescriptor> contexts)
    : contexts = Map.unmodifiable(contexts);

  /// The contexts by id.
  final Map<String, ContextMappingsDescriptor> contexts;

  @override
  Map<String, Object?> toJson() => {
    'contexts': {
      for (final MapEntry(:key, :value) in contexts.entries)
        key: value.toJson(),
    },
  };
}

/// The mappings of one application context, by the name of their kind.
///
/// Spring Boot (Java): `MappingsEndpoint.ContextMappingsDescriptor`.
final class ContextMappingsDescriptor implements OperationResponseBody {
  /// The [mappings] of a context whose parent is [parentId].
  ContextMappingsDescriptor(Map<String, Object?> mappings, {this.parentId})
    : mappings = Map.unmodifiable(mappings);

  /// The mappings by kind (`dispatcherHandlers`, `screens`).
  final Map<String, Object?> mappings;

  /// The parent context's id; `null` for none.
  final String? parentId;

  @override
  Map<String, Object?> toJson() => {'mappings': mappings, 'parentId': parentId};
}
