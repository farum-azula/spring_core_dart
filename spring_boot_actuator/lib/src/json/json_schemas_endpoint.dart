import 'package:spring_boot_actuator/src/endpoint/annotations.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `jsonschemas` endpoint: the JSON Schemas of the application.
///
/// - `registry`: the schemas of the context's `JsonSchemaRegistry` (those
///   of `spring.json.schemas`, of `@JsonSchemaSource`, of `JsonSchema`
///   beans and of the app's own customizers), by the location or `$id`
///   each is known by;
/// - `introspected`: the schema of every `@Introspected` class of the
///   application, made from its introspection with the `ObjectMapper`'s
///   naming ([JsonSchemaGenerator]): what its JSON looks like.
///
/// `GET /actuator/jsonschemas/{name}` gives one: a class name, else a
/// location (`/actuator/jsonschemas/resources:schemas/order.json`);
/// nothing (404) when there is none. Like every endpoint but `health`, it
/// answers over HTTP once exposed:
/// `management.endpoints.web.exposure.include=health,jsonschemas`.
///
/// ```json
/// {"registry": {"resources:schemas/order.json": {"type": "object", ...}},
///  "introspected": {"Book": {"$schema": "...", "title": "Book", ...}}}
/// ```
///
/// Spring has no counterpart.
@Endpoint(id: 'jsonschemas')
class JsonSchemasEndpoint {
  /// The endpoint of [registry] (none: an empty `registry`) and of the
  /// classes [generator] knows.
  JsonSchemasEndpoint({this.registry, JsonSchemaGenerator? generator})
    : generator = generator ?? JsonSchemaGenerator();

  /// The context's registry; `null` when it has none.
  final JsonSchemaRegistry? registry;

  /// Makes the schemas of the `@Introspected` classes.
  final JsonSchemaGenerator generator;

  /// Every schema: those of the registry and those of the classes.
  @ReadOperation()
  Map<String, Object?> schemas() => {
    'registry': {
      for (final MapEntry(:key, :value)
          in (registry?.schemas ?? const <Uri, JsonSchema>{}).entries)
        '$key': value.document,
    },
    'introspected': generator.all(),
  };

  /// The schema named by [path]: a class name, else a location of the
  /// registry (its segments joined by `/`); `null` when there is none.
  @ReadOperation()
  Map<String, Object?>? schema(
    @Selector(match: SelectorMatch.allRemaining) List<String> path,
  ) {
    final name = Uri.decodeComponent(path.join('/'));
    final introspected = generator.all();
    if (introspected[name] case final schema?) {
      return schema;
    }
    for (final MapEntry(:key, :value)
        in (registry?.schemas ?? const <Uri, JsonSchema>{}).entries) {
      if ('$key' == name) {
        return value.document;
      }
    }
    final uri = Uri.tryParse(name);
    return uri == null ? null : registry?.resolve(uri)?.document;
  }
}
