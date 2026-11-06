import 'package:spring_boot_actuator/src/endpoint/annotations.dart';
import 'package:spring_boot_actuator/src/endpoint/operation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog('spring.boot.actuate.endpoint.EndpointDiscoverer');

/// Finds the endpoints of an application: the beans marked [Endpoint],
/// with their [ReadOperation] methods, and for HTTP the operations of
/// their [EndpointWebExtension] beans.
///
/// The actuator starter creates one; applications do not. It reads the
/// bean definitions (what the generator wrote for each class: its
/// annotations and annotated methods), so it needs no reflection; the
/// beans themselves are fetched when an operation is called.
///
/// Two endpoints with the same id, or two operations of one endpoint with
/// the same selectors, stop the start with every problem listed.
///
/// Spring Boot (Java): `EndpointDiscoverer` (`WebEndpointDiscoverer`).
final class EndpointDiscoverer {
  /// The discoverer of the endpoint beans of [beanFactory]; arguments are
  /// converted with [conversionService].
  EndpointDiscoverer(this.beanFactory, {ConversionService? conversionService})
    : conversionService = conversionService ?? DefaultConversionService();

  /// The container whose beans are the endpoints.
  final ListableBeanFactory beanFactory;

  /// Converts the text of the request to the parameters' types.
  final ConversionService conversionService;

  List<ExposableEndpoint>? _endpoints;

  /// The endpoints with their operations, found once. The operations of a
  /// web extension replace those of its endpoint with the same selectors
  /// (the endpoints are for HTTP).
  List<ExposableEndpoint> getEndpoints() => _endpoints ??= _discover();

  List<ExposableEndpoint> _discover() {
    final registry = beanFactory as BeanDefinitionRegistry;
    final problems = <String>[];
    final endpoints = <EndpointId, ExposableEndpoint>{};
    final byType = <Type, EndpointId>{};
    for (final name in beanFactory.getBeanNamesForAnnotation<Endpoint>()) {
      if (!registry.containsBeanDefinition(name)) {
        continue;
      }
      final definition = registry.getBeanDefinition(name);
      final annotation = definition.annotations.whereType<Endpoint>().first;
      final EndpointId id;
      try {
        id = EndpointId.of(annotation.id);
      } on ArgumentError catch (error) {
        problems.add(
          "Endpoint bean '$name' has the invalid id '${annotation.id}': "
          '${error.message}',
        );
        continue;
      }
      if (endpoints[id] case final other?) {
        problems.add(
          "Found two endpoints with the id '$id': '${other.beanName}' and "
          "'$name'",
        );
        continue;
      }
      endpoints[id] = ExposableEndpoint(
        id: id,
        enableByDefault: annotation.enableByDefault,
        beanName: name,
        operations: _operations(id, name, definition, problems),
      );
      byType[definition.beanType] = id;
    }
    for (final name
        in beanFactory.getBeanNamesForAnnotation<EndpointWebExtension>()) {
      if (!registry.containsBeanDefinition(name)) {
        continue;
      }
      final definition = registry.getBeanDefinition(name);
      final annotation = definition.annotations
          .whereType<EndpointWebExtension>()
          .first;
      final id = byType[annotation.endpoint];
      if (id == null) {
        problems.add(
          "Web extension '$name' extends ${annotation.endpoint}, which is "
          'not an endpoint bean',
        );
        continue;
      }
      final endpoint = endpoints[id]!;
      final extension = _operations(id, name, definition, problems);
      final replaced = {for (final op in extension) _key(op)};
      endpoints[id] = ExposableEndpoint(
        id: id,
        enableByDefault: endpoint.enableByDefault,
        beanName: endpoint.beanName,
        operations: [
          for (final op in endpoint.operations)
            if (!replaced.contains(_key(op))) op,
          ...extension,
        ],
      );
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid actuator endpoints:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
      );
    }
    _log.debug(
      () => 'Discovered endpoints ${endpoints.keys.map((id) => '$id')}',
    );
    return List.unmodifiable(endpoints.values);
  }

  // What makes two operations answer the same requests: the type and the
  // selectors.
  static String _key(EndpointOperation operation) =>
      '${operation.type.name}'
      '${[for (final s in operation.selectors) '/${s.selector!.name}'].join()}';

  List<EndpointOperation> _operations(
    EndpointId id,
    String beanName,
    BeanDefinition<Object> definition,
    List<String> problems,
  ) {
    final operations = <EndpointOperation>[];
    final seen = <String, String>{};
    for (final method in definition.annotatedMethods) {
      final read = method.annotation<ReadOperation>();
      if (read == null) {
        continue;
      }
      final parameters = [
        for (final parameter in method.parameters)
          OperationParameter(
            parameter.name,
            type: parameter.type,
            selector: parameter.annotations
                .whereType<Selector>()
                .firstOrNull
                ?.match,
            symbol: parameter.symbol,
            isMandatory:
                !parameter.type.nullable &&
                !parameter.hasDefaultValue &&
                (!parameter.isNamed || parameter.isRequired),
          ),
      ];
      final operation = EndpointOperation(
        endpointId: id,
        type: OperationType.read,
        name: method.name,
        className: '${definition.beanType}',
        parameters: parameters,
        produces: read.produces,
        invoker: (context) {
          final (positional, named) = _arguments(parameters, context);
          return method.invoke(
            beanFactory.getBeanByName(beanName),
            positional,
            named,
          );
        },
      );
      final key = _key(operation);
      if (seen[key] case final other?) {
        problems.add(
          "Endpoint '$id' has two read operations with the same selectors: "
          '$other and ${method.name}',
        );
        continue;
      }
      seen[key] = method.name;
      operations.add(operation);
    }
    return operations;
  }

  // The positional and named arguments of a call, from the context.
  (List<Object?>, Map<Symbol, Object?>) _arguments(
    List<OperationParameter> parameters,
    InvocationContext context,
  ) {
    final positional = <Object?>[];
    final named = <Symbol, Object?>{};
    final missing = <String>[];
    for (final parameter in parameters) {
      final Object? value;
      if (parameter.type.type == SecurityContext) {
        value = context.securityContext;
      } else if (parameter.type.type == ApiVersion) {
        value = context.apiVersion;
      } else if (context.arguments[parameter.name] case final raw?) {
        value = _convert(parameter, raw);
      } else {
        if (parameter.isMandatory) {
          missing.add(parameter.name);
        }
        if (parameter.symbol == null) {
          positional.add(null);
        }
        continue; // an omitted named argument keeps its default
      }
      if (parameter.symbol case final symbol?) {
        named[symbol] = value;
      } else {
        positional.add(value);
      }
    }
    if (missing.isNotEmpty) {
      throw MissingParametersException(missing);
    }
    return (positional, named);
  }

  Object? _convert(OperationParameter parameter, Object raw) {
    final type = parameter.type;
    if (type.isInstance(raw)) {
      return raw;
    }
    // A selector of every remaining segment, read into a String.
    final source = raw is List<String> && type.type == String
        ? raw.join('/')
        : raw;
    try {
      return type.capture(<X>() => conversionService.convert<X>(source));
    } on Object catch (error) {
      throw InvalidEndpointRequestException(
        "Failed to convert '$source' to ${type.type} for parameter "
            "'${parameter.name}': $error",
        "Invalid value for parameter '${parameter.name}'",
      );
    }
  }
}
