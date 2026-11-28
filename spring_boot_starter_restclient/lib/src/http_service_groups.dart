import 'package:spring_boot_starter_restclient/src/config/http_client_properties.dart';
import 'package:spring_boot_starter_restclient/src/rest_client_customizer.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A group of HTTP service interfaces that share one `RestClient`: its
/// [name] (the key of `spring.http.serviceclient.<name>.*`) and the
/// interfaces imported into it.
///
/// The groups are those configured under `spring.http.serviceclient` and
/// those of the `HttpServiceGroup` beans (the generator declares one for
/// each `@ImportHttpServices`).
///
/// Spring (Java): `org.springframework.web.service.registry.HttpServiceGroup`.
final class HttpServiceGroup {
  /// The group [name] with the interfaces [types].
  const HttpServiceGroup(this.name, {this.types = const []});

  /// The group's name.
  final String name;

  /// The HTTP service interfaces of the group.
  final List<Type> types;

  @override
  String toString() => 'HttpServiceGroup($name)';
}

/// Configures the `RestClientBuilder` instances of HTTP service groups beyond
/// their properties: a header for one group, an interceptor for all. Declare
/// one as a bean; it runs after the properties are applied, in `@Order`.
///
/// ```dart
/// @Bean()
/// RestClientHttpServiceGroupConfigurer catalogAuth(TokenSource tokens) =>
///     RestClientHttpServiceGroupConfigurer.of(
///       (groups) => groups.filterByName(['catalog']).forEachClient(
///         (group, builder) => builder.requestInterceptor(
///           BearerInterceptor(tokens),
///         ),
///       ),
///     );
/// ```
///
/// Spring (Java): `RestClientHttpServiceGroupConfigurer`:
/// ```java
/// @Bean
/// RestClientHttpServiceGroupConfigurer catalogAuth() {
///   return groups -> groups.filterByName("catalog")
///       .forEachClient((group, builder) -> builder.requestInterceptor(...));
/// }
/// ```
abstract interface class RestClientHttpServiceGroupConfigurer {
  /// The configurer that calls [configure].
  const factory RestClientHttpServiceGroupConfigurer.of(
    void Function(HttpServiceGroupBuilders groups) configure,
  ) = _FunctionGroupConfigurer;

  /// Changes the builders of [groups].
  void configureGroups(HttpServiceGroupBuilders groups);
}

final class _FunctionGroupConfigurer
    implements RestClientHttpServiceGroupConfigurer {
  const _FunctionGroupConfigurer(this._configure);

  final void Function(HttpServiceGroupBuilders groups) _configure;

  @override
  void configureGroups(HttpServiceGroupBuilders groups) => _configure(groups);
}

/// The groups a [RestClientHttpServiceGroupConfigurer] configures, each
/// with its `RestClientBuilder`; [filterByName] and [filter] narrow them.
///
/// Spring (Java): `HttpServiceGroupConfigurer.Groups<RestClient.Builder>`.
final class HttpServiceGroupBuilders {
  /// The [builders] of their groups.
  HttpServiceGroupBuilders(Map<HttpServiceGroup, RestClientBuilder> builders)
    : _builders = builders;

  final Map<HttpServiceGroup, RestClientBuilder> _builders;

  /// The groups named in [names].
  HttpServiceGroupBuilders filterByName(List<String> names) =>
      filter((group) => names.contains(group.name));

  /// The groups [predicate] takes.
  HttpServiceGroupBuilders filter(
    bool Function(HttpServiceGroup group) predicate,
  ) => HttpServiceGroupBuilders({
    for (final MapEntry(key: group, value: builder) in _builders.entries)
      if (predicate(group)) group: builder,
  });

  /// Runs [configure] on the builder of each group.
  void forEachClient(
    void Function(HttpServiceGroup group, RestClientBuilder builder) configure,
  ) => _builders.forEach(configure);
}

/// The `RestClient` of each HTTP service group (the `httpServiceGroups`
/// bean): set up like the `RestClientBuilder` bean (the transport, the
/// `ObjectMapper`, `spring.http.clients.*`, the customizers), then by
/// `spring.http.serviceclient.<group>.*` (base URL, default headers, API
/// version, timeouts, redirects), then by the
/// [RestClientHttpServiceGroupConfigurer] beans. A group with a default
/// API version and no `ApiVersionInserter` fails the start.
///
/// ```dart
/// @Service()
/// class Catalog {
///   Catalog(HttpServiceGroups groups) : _rest = groups.restClient('catalog');
///   final RestClient _rest;
///
///   Future<Book> find(String isbn) =>
///       _rest.get().uri('/books/{isbn}', isbn).retrieve().body<Book>();
/// }
/// ```
///
/// Spring (Java): the `HttpServiceProxyRegistry` of Spring's HTTP service
/// clients, whose groups' clients the interfaces' proxies call.
final class HttpServiceGroups {
  /// The groups of [properties] and [declared], with builders from
  /// [newBuilder] set up by [configurers]. Throws a [StateError] for a
  /// group's base URL that cannot be read, or a group with a default API
  /// version and no `ApiVersionInserter`.
  factory HttpServiceGroups({
    required HttpServiceClientProperties properties,
    required RestClientBuilder Function() newBuilder,
    List<HttpServiceGroup> declared = const [],
    List<RestClientHttpServiceGroupConfigurer> configurers = const [],
  }) {
    final groups = <String, HttpServiceGroup>{
      for (final name in properties.serviceclient.keys)
        name: HttpServiceGroup(name),
    };
    for (final group in declared) {
      final known = groups[group.name];
      groups[group.name] = HttpServiceGroup(
        group.name,
        types: [...?known?.types, ...group.types],
      );
    }
    final builders = <HttpServiceGroup, RestClientBuilder>{};
    for (final group in groups.values) {
      final builder = newBuilder();
      final settings = properties.serviceclient[group.name];
      if (settings != null) {
        _apply(group.name, settings, builder);
      }
      builders[group] = builder;
    }
    final configurable = HttpServiceGroupBuilders(builders);
    for (final configurer in configurers) {
      configurer.configureGroups(configurable);
    }
    builders.forEach(_checkApiVersion);
    return HttpServiceGroups._({
      for (final MapEntry(key: group, value: builder) in builders.entries)
        group.name: (group, builder.build()),
    });
  }

  HttpServiceGroups._(this._clients);

  final Map<String, (HttpServiceGroup, RestClient)> _clients;

  static void _apply(
    String name,
    HttpServiceClientGroupProperties settings,
    RestClientBuilder builder,
  ) {
    final baseUrl = settings.baseUrl?.trim();
    if (baseUrl != null && baseUrl.isNotEmpty) {
      builder.baseUrl(baseUrl);
    }
    builder.defaultHeaders((headers) {
      settings.defaultHeader.forEach((header, values) {
        headers
          ..remove(header)
          ..addAll(header, values);
      });
    });
    if (settings.connectTimeout case final timeout?) {
      builder.connectTimeout(
        RestClientBuilderConfigurer.positiveOrNull(timeout),
      );
    }
    if (settings.readTimeout case final timeout?) {
      builder.readTimeout(RestClientBuilderConfigurer.positiveOrNull(timeout));
    }
    if (settings.redirects case final redirects?) {
      builder.followRedirects(redirects.followsRedirects);
    }
    final apiversion = settings.apiversion;
    if (apiversion.defaultVersion?.trim() case final version?
        when version.isNotEmpty) {
      builder.defaultApiVersion(version);
    }
    if (_inserter(apiversion.insert) case final inserter?) {
      builder.apiVersionInserter(inserter);
    }
  }

  // The inserter of [insert]; `null` when it sets no place.
  //
  // Spring (Java): Spring Boot's `PropertiesApiVersionInserter.get(...)`.
  static ApiVersionInserter? _inserter(ApiversionInsertProperties insert) {
    String? text(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final header = text(insert.header);
    final queryParameter = text(insert.queryParameter);
    final mediaTypeParameter = text(insert.mediaTypeParameter);
    final pathSegment = insert.pathSegment;
    if (header == null &&
        queryParameter == null &&
        pathSegment == null &&
        mediaTypeParameter == null) {
      return null;
    }
    return ApiVersionInserter.builder()
        .useHeader(header)
        .useQueryParam(queryParameter)
        .usePathSegment(pathSegment)
        .useMediaTypeParam(mediaTypeParameter)
        .build();
  }

  // A group whose calls ask for a default API version needs a place to
  // put it: without one every call would fail, so the start does.
  static void _checkApiVersion(
    HttpServiceGroup group,
    RestClientBuilder builder,
  ) {
    final version = builder.configuredDefaultApiVersion;
    if (version != null && builder.configuredApiVersionInserter == null) {
      final name = group.name;
      throw StateError(
        'The HTTP service group "$name" asks for the API version '
        '"$version" (spring.http.serviceclient.$name.apiversion.default) '
        'and has no ApiVersionInserter to send it: set '
        'spring.http.serviceclient.$name.apiversion.insert.header (or '
        'query-parameter, path-segment, media-type-parameter).',
      );
    }
  }

  /// The names of the groups.
  Iterable<String> get groupNames => _clients.keys;

  /// The group [name]. Throws an [ArgumentError] for a group that is not
  /// configured, naming the property to set.
  HttpServiceGroup group(String name) => _entry(name).$1;

  /// The `RestClient` of the group [name]. Throws an [ArgumentError] for a
  /// group that is not configured, naming the property to set.
  RestClient restClient(String name) => _entry(name).$2;

  (HttpServiceGroup, RestClient) _entry(String name) {
    final entry = _clients[name];
    if (entry != null) {
      return entry;
    }
    final known = _clients.isEmpty
        ? ''
        : ' (the groups: ${_clients.keys.join(', ')})';
    throw ArgumentError.value(
      name,
      'group',
      'No HTTP service group "$name": set '
          'spring.http.serviceclient.$name.base-url$known',
    );
  }
}
