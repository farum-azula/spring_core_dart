/// Describes the addresses a part of the application answers, for
/// `/actuator/mappings` and the editor: the web server's handlers, the
/// static resources, an app's screens.
///
/// Each kind of mappings is one bean; the actuator's `mappings` endpoint
/// puts every bean's [describeMappings] under its [mappingsName], so one
/// answer shows the server's handlers (`dispatcherHandlers`, in Spring
/// WebFlux's shape) and, in a Flutter app, its screens (`screens`, our
/// own addition).
///
/// ```dart
/// @Component()
/// class JobMappings implements MappingDescriptions {
///   @override
///   String get mappingsName => 'jobs';
///
///   @override
///   Object? describeMappings() => [
///     {'pattern': '/jobs/{id}', 'handler': 'JobController.byId'},
///   ];
/// }
/// ```
///
/// Spring Boot (Java): the `MappingDescriptionProvider`s of the actuator's
/// `MappingsEndpoint`.
abstract interface class MappingDescriptions {
  /// The key of these mappings in the actuator's answer
  /// (`dispatcherHandlers`, `screens`).
  String get mappingsName;

  /// The mappings as JSON values (maps, lists, strings, numbers, booleans),
  /// in Spring Boot's shape where Spring has one.
  Object? describeMappings();
}
