import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A handler mapping that can list its handlers, for the actuator's
/// `mappings` endpoint.
///
/// The controllers' `RequestMappingHandlerMapping`, the static resources'
/// `ResourceHandlerMapping` and the actuator's endpoints implement it;
/// implement it in a handler mapping of your own to have it listed.
///
/// ```dart
/// @override
/// List<Map<String, Object?>> describeHandlers() => [
///   {'predicate': '/legacy/**', 'handler': 'LegacyProxy'},
/// ];
/// ```
///
/// Spring Boot (Java): the `HandlerMappingDescriptionProvider`s of
/// `DispatcherHandlersMappingDescriptionProvider`.
abstract interface class DescribableHandlerMapping {
  /// One map per handler, in Spring WebFlux's shape: `predicate`,
  /// `handler` and, for a method, `details` (see
  /// [describeRequestMapping]).
  List<Map<String, Object?>> describeHandlers();
}

/// The description of one request mapping in Spring WebFlux's shape, as
/// the actuator's `mappings` endpoint lists it:
///
/// ```json
/// {"predicate": "{GET [/api/books/{isbn}], produces [application/json]}",
///  "handler": "BookController#find(String)",
///  "details": {
///    "handlerMethod": {"className": "BookController", "name": "find",
///      "descriptor": "(String isbn) -> Future<Book>"},
///    "requestMappingConditions": {"consumes": [], "headers": [],
///      "methods": ["GET"], "params": [], "patterns": ["/api/books/{isbn}"],
///      "produces": [{"mediaType": "application/json", "negated": false}]}}}
/// ```
///
/// [headers] and [params] are conditions such as `X-Api=2` or `!debug`.
/// Spring's `descriptor` is the JVM's; here it is the Dart signature.
///
/// Spring Boot (Java): `DispatcherHandlerMappingDescription` with
/// `RequestMappingConditionsDescription`; the predicate is Spring's
/// `RequestMappingInfo.toString()`.
Map<String, Object?> describeRequestMapping({
  required String handler,
  required List<String> patterns,
  String? className,
  String? methodName,
  String? descriptor,
  List<String> methods = const [],
  List<String> consumes = const [],
  List<String> produces = const [],
  List<String> headers = const [],
  List<String> params = const [],
}) {
  String list(List<String> values) => '[${values.join(' || ')}]';
  final predicate = StringBuffer('{')
    ..write(
      methods.isEmpty
          ? ''
          : methods.length == 1
          ? methods.single
          : '[${methods.join(', ')}]',
    )
    ..write(' ${list(patterns)}');
  if (params.isNotEmpty) {
    predicate.write(', params ${list(params)}');
  }
  if (headers.isNotEmpty) {
    predicate.write(', headers ${list(headers)}');
  }
  if (consumes.isNotEmpty) {
    predicate.write(', consumes ${list(consumes)}');
  }
  if (produces.isNotEmpty) {
    predicate.write(', produces ${list(produces)}');
  }
  predicate.write('}');
  return {
    'predicate': '$predicate',
    'handler': handler,
    'details': {
      if (className != null && methodName != null)
        'handlerMethod': {
          'className': className,
          'name': methodName,
          'descriptor': ?descriptor,
        },
      'requestMappingConditions': {
        'consumes': [for (final type in consumes) _mediaType(type)],
        'headers': [for (final header in headers) _nameValue(header)],
        'methods': methods,
        'params': [for (final param in params) _nameValue(param)],
        'patterns': patterns,
        'produces': [for (final type in produces) _mediaType(type)],
      },
    },
  };
}

Map<String, Object?> _mediaType(String type) => {
  'mediaType': type.startsWith('!') ? type.substring(1) : type,
  'negated': type.startsWith('!'),
};

// `name`, `!name`, `name=value` or `name!=value`.
Map<String, Object?> _nameValue(String condition) {
  final notEquals = condition.indexOf('!=');
  if (notEquals > 0) {
    return {
      'name': condition.substring(0, notEquals),
      'value': condition.substring(notEquals + 2),
      'negated': true,
    };
  }
  final equals = condition.indexOf('=');
  if (equals > 0) {
    return {
      'name': condition.substring(0, equals),
      'value': condition.substring(equals + 1),
      'negated': false,
    };
  }
  final negated = condition.startsWith('!');
  return {
    'name': negated ? condition.substring(1) : condition,
    'value': null,
    'negated': negated,
  };
}

/// The web server's handlers for the actuator's `mappings` endpoint,
/// under `dispatcherHandlers` in Spring WebFlux's shape: every handler of
/// every [DescribableHandlerMapping] of the dispatcher, in the order they
/// are asked, under `webHandler` (Spring's name of the dispatcher bean).
///
/// ```json
/// {"webHandler": [
///   {"predicate": "{GET [/api/books/{isbn}]}", "handler": "...",
///    "details": {...}},
///   {"predicate": "/**", "handler": "ResourceWebHandler [resources:static/]"}]}
/// ```
///
/// The web starter declares it as the `dispatcherHandlersMappingDescriptions`
/// bean. Spring Boot (Java): `DispatcherHandlersMappingDescriptionProvider`.
final class DispatcherHandlersMappingDescriptions
    implements MappingDescriptions {
  /// The descriptions of the dispatcher [dispatcher] gives, asked when
  /// the mappings are read.
  DispatcherHandlersMappingDescriptions(this.dispatcher);

  /// Gives the dispatcher.
  final DispatcherHandler? Function() dispatcher;

  @override
  String get mappingsName => 'dispatcherHandlers';

  @override
  Map<String, Object?> describeMappings() => {
    'webHandler': [
      for (final mapping in dispatcher()?.handlerMappings ?? const [])
        if (mapping is DescribableHandlerMapping) ...mapping.describeHandlers(),
    ],
  };
}
