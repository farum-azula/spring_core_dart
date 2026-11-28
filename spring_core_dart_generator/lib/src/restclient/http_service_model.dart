// The model of spring_boot_starter_restclient's part of a module: the HTTP
// service interfaces it imports (`@ImportHttpServices`), each with the
// calls of its methods, and the groups they are in. The scan fills it
// (http_service_scanner.dart), the emitter writes it
// (http_service_emitter.dart). It lives in the module
// ([ModuleModel.packageModel]), so the core knows none of these types.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';

/// What the part of `spring_boot_starter_restclient` found in a module:
/// the imported HTTP service interfaces, the groups they are in, and the
/// interfaces of the module's libraries that declare calls (checked once
/// the module is scanned: one no `@ImportHttpServices` imports is no
/// bean). The services themselves are beans of the module, made by an
/// [HttpServiceCreation].
final class HttpServiceModuleModel {
  /// The model of [module], made the first time it is asked for.
  static HttpServiceModuleModel of(ModuleModel module) =>
      module.packageModel(HttpServiceModuleModel.new);

  /// The services, in the order they were imported.
  final services = <HttpServiceModel>[];

  /// The interfaces imported so far, with their group.
  final groupOf = <InterfaceElement, String>{};

  /// The importer of each interface imported so far.
  final importerOf = <InterfaceElement, HttpServiceImporter>{};

  /// The groups the module's `@ImportHttpServices` declare, one per group
  /// and importer, in the order they were met.
  final groups = <HttpServiceGroupModel>[];

  /// The classes with `@ImportHttpServices`, imported once every library
  /// is scanned: only then is it known which are beans, and under which
  /// conditions.
  final importingClasses = <ClassElement>[];

  /// The interfaces of the scanned libraries with an exchange annotation
  /// (on the interface or a method), in scan order.
  final declared = <ClassElement>[];
}

/// What carries an `@ImportHttpServices`: the application's `main` (or a
/// `@ComponentScan` variable), or a bean class, whose conditions the
/// imported interfaces' beans take, as Spring registers them only when
/// the configuration class that imports them is.
///
/// ```dart
/// // Input:
/// @Profile('prod')
/// @Configuration()
/// @ImportHttpServices(group: 'catalog', types: [BookService])
/// class CatalogConfig {}
/// // Output: the bookService bean and the catalog group's
/// // HttpServiceGroup bean, both with
/// conditions: [ConditionGroup(r'package:shop/config.dart#CatalogConfig',
///     [const ProfileCondition([r'prod'])])],
/// ```
final class HttpServiceImporter {
  /// The importer [element], a bean class when [key] is given (its name),
  /// registered under [conditions].
  HttpServiceImporter(this.element, {this.key, this.conditions = const []});

  /// The class, function or variable carrying the annotation.
  final Element element;

  /// The class's name, which the group bean's name ends with; `null` for
  /// the application's `main` or a `@ComponentScan` variable.
  final String? key;

  /// The conditions of the bean class, evaluated once for it.
  final List<ConditionModel> conditions;
}

/// One group as one importer declares it: the `HttpServiceGroup` bean
/// with its interfaces, under the importer's conditions. The starter's
/// `HttpServiceGroups` joins the groups of the same name.
final class HttpServiceGroupModel {
  /// The group [name] of [importer].
  HttpServiceGroupModel(this.name, this.importer);

  /// The group: the key of `spring.http.serviceclient.<name>.*`.
  final String name;

  /// What declares it.
  final HttpServiceImporter importer;

  /// The interfaces it imports.
  final types = <InterfaceType>[];
}

/// A bean that is the generated implementation of an HTTP service
/// interface: `_$BookServiceHttpService(...)`, on the `RestClient` of its
/// group.
///
/// ```dart
/// // Input:
/// @ImportHttpServices(group: 'catalog', types: [BookService])
/// // Output:
/// create: (r) => _$BookServiceHttpService(
///   r.dependency<HttpServiceGroups>().restClient(r'catalog'),
/// ),
/// ```
///
/// Spring (Java): the proxy `HttpServiceProxyFactory` creates for an
/// interface of `HttpServiceProxyRegistry`'s group.
final class HttpServiceCreation extends PackageCreation {
  /// Creates the service of [model].
  HttpServiceCreation(this.model);

  /// The interface and the calls the generated class makes.
  final HttpServiceModel model;
}

/// An HTTP service interface and the class the build writes for it.
final class HttpServiceModel {
  /// The service [type] of [group], written as [className] with [calls].
  HttpServiceModel({
    required this.className,
    required this.type,
    required this.group,
    required this.calls,
  });

  /// The generated class (`_$BookServiceHttpService`).
  final String className;

  /// The interface.
  final InterfaceType type;

  /// The group whose `RestClient` it calls.
  final String group;

  /// One call for each method of the interface.
  final List<HttpCallModel> calls;

  /// Whether a URL or a header holds a `${property}` placeholder, filled
  /// from the `Environment` when the bean is made.
  bool get resolvesPlaceholders => calls.any(
    (call) =>
        call.url.hasPlaceholders ||
        call.headers.any((header) => header.hasPlaceholders),
  );

  /// Whether a part is written as JSON, with the application's
  /// `ObjectMapper`.
  bool get writesJsonParts => calls.any(
    (call) => call.arguments.any(
      (argument) => argument is PartArgument && argument.kind == PartKind.json,
    ),
  );
}

/// The URL of a call: the interface's and the method's joined.
final class HttpUrlModel {
  /// The URL [text] of the method [methodName].
  HttpUrlModel(this.text, this.methodName);

  /// The URL as written, `${...}` placeholders and `{variables}` in it.
  final String text;

  /// The method it is the URL of, which names the field of a URL with
  /// placeholders (`_findUrl`).
  final String methodName;

  /// Whether it holds a `${property}` placeholder.
  bool get hasPlaceholders => text.contains(r'${');

  /// The field holding the URL with its placeholders filled.
  String get fieldName => '_${methodName}Url';

  /// Whether it is a whole URL (`https://...`), not relative to the base
  /// URL of the group.
  bool get isAbsolute => RegExp('^[A-Za-z][A-Za-z0-9+.-]*://').hasMatch(text);

  /// The `{variables}` of the URL, by name, outside `${...}` placeholders.
  Set<String> get variables => {
    for (final match in _variable.allMatches(
      text.replaceAll(_placeholder, ''),
    ))
      match[1]!.trim(),
  };

  /// The URL before its `?`.
  String get path => switch (text.indexOf('?')) {
    -1 => text,
    final at => text.substring(0, at),
  };

  /// The query parameters written in the URL (`?sort=title&flag`), in
  /// order; a `null` value for a name alone.
  List<(String, String?)> get query {
    final at = text.indexOf('?');
    if (at < 0) {
      return const [];
    }
    return [
      for (final pair in text.substring(at + 1).split('&'))
        if (pair.isNotEmpty)
          switch (pair.indexOf('=')) {
            -1 => (pair, null),
            final equals => (
              pair.substring(0, equals),
              pair.substring(equals + 1),
            ),
          },
    ];
  }

  static final _placeholder = RegExp(r'\$\{[^}]*\}');
  static final _variable = RegExp(r'\{([^{}:]+)(?::[^{}]*)?\}');
}

/// A header the annotations set on every call of a method: `Name=value`
/// of `headers`, the value a `${property}` placeholder may fill.
final class HttpHeaderModel {
  /// The header [name] with [values], of the method [methodName].
  HttpHeaderModel(this.name, this.values, this.methodName);

  /// The header's name.
  final String name;

  /// Its values, in order.
  final List<String> values;

  /// The method it is sent by.
  final String methodName;

  /// Whether a value holds a `${property}` placeholder.
  bool get hasPlaceholders => values.any((value) => value.contains(r'${'));

  /// The field holding the value number [index] with its placeholders
  /// filled (`_findXTenantHeader`, `_findXTenantHeader2`).
  String fieldName(int index) {
    final words = name
        .split(RegExp('[^A-Za-z0-9]+'))
        .where((word) => word.isNotEmpty);
    final camel = [
      for (final word in words)
        '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
    ].join();
    return '_$methodName${camel}Header${index == 0 ? '' : '${index + 1}'}';
  }
}

/// A request attribute an annotation sets on every call of a method (an
/// annotation extending `HttpRequestAttribute`: the OAuth2 client's
/// `@ClientRegistrationId`).
final class HttpAttributeModel {
  /// The attribute [name] set to [value] (a constant of [element]).
  HttpAttributeModel(this.name, this.value, this.element);

  /// The attribute's name.
  final String name;

  /// Its value.
  final DartObject value;

  /// The declaration the annotation is on.
  final Element element;
}

/// One method of an HTTP service interface and the call it makes.
final class HttpCallModel {
  /// The call of [member].
  HttpCallModel({
    required this.member,
    required this.httpMethod,
    required this.url,
    required this.response,
    this.methodParameter,
    this.uriParameter,
    this.contentType,
    this.accept = const [],
    this.headers = const [],
    this.attributes = const [],
    this.arguments = const [],
  });

  /// The signature the generated method repeats.
  final ProxyMember member;

  /// The name of the `HttpMethod` value (`get`, `post`).
  final String httpMethod;

  /// The parameter of type `HttpMethod` that gives the method of each
  /// call instead of [httpMethod]; `null` for none.
  final String? methodParameter;

  /// The URL.
  final HttpUrlModel url;

  /// The parameter of type `Uri` that is the URL of each call instead of
  /// [url]; `null` for none.
  final String? uriParameter;

  /// The `Content-Type` of the body; `null`: the converter's.
  final String? contentType;

  /// The media types of `Accept`; empty: none sent.
  final List<String> accept;

  /// The headers of the annotations.
  final List<HttpHeaderModel> headers;

  /// The request attributes of the annotations.
  final List<HttpAttributeModel> attributes;

  /// The parameters that go into the request, in order.
  final List<HttpArgument> arguments;

  /// What the method returns.
  final HttpResponseModel response;

  /// Whether the request has a body: a `@RequestBody`, parts, or the
  /// query parameters sent as a form.
  bool get hasBody => arguments.any(
    (argument) =>
        argument is BodyArgument ||
        argument is PartArgument ||
        (argument is QueryArgument && sendsForm),
  );

  /// Whether the query parameters are sent as an
  /// `application/x-www-form-urlencoded` body, as Spring does for a form
  /// content type.
  bool get sendsForm =>
      contentType?.toLowerCase().startsWith(
        'application/x-www-form-urlencoded',
      ) ??
      false;

  /// Whether the call reads a file's bytes first (`await file.bytes`), so
  /// the method is `async`.
  bool get awaitsParts => arguments.any(
    (argument) =>
        argument is PartArgument &&
        (argument.kind == PartKind.multipartFile ||
            argument.kind == PartKind.multipartFiles),
  );
}

/// A parameter of a method and where its value goes in the request.
sealed class HttpArgument {
  HttpArgument(this.parameter, this.type);

  /// The parameter's name.
  final String parameter;

  /// The parameter's type.
  final DartType type;

  /// Whether a `null` leaves the value out.
  bool get isNullable => type.nullabilitySuffix != NullabilitySuffix.none;
}

/// A `@PathVariable`: fills `{name}` of the URL.
final class PathArgument extends HttpArgument {
  /// The variable [name] from [parameter].
  PathArgument(super.parameter, super.type, this.name);

  /// The variable's name.
  final String name;
}

/// A `@RequestParam`: a query parameter, or a field of a form body.
final class QueryArgument extends HttpArgument {
  /// The query parameter [name] from [parameter].
  QueryArgument(
    super.parameter,
    super.type, {
    required this.name,
    required this.text,
    required this.isIterable,
  });

  /// The query parameter's name.
  final String name;

  /// How one value is written as text, for a form body.
  final TextKind text;

  /// Whether the parameter holds several values, one parameter each.
  final bool isIterable;
}

/// A value sent as text by a method of the request spec of its own: a
/// header or a cookie.
sealed class TextArgument extends HttpArgument {
  TextArgument(
    super.parameter,
    super.type, {
    required this.name,
    required this.text,
    required this.isIterable,
  });

  /// The header's or cookie's name.
  final String name;

  /// How one value is written as text.
  final TextKind text;

  /// Whether the parameter holds several values, one each.
  final bool isIterable;

  /// The method of the request spec that adds one (`header`, `cookie`).
  String get specMethod;
}

/// A `@RequestHeader`: a header.
final class HeaderArgument extends TextArgument {
  /// The header [name] from [parameter].
  HeaderArgument(
    super.parameter,
    super.type, {
    required super.name,
    required super.text,
    required super.isIterable,
  });

  @override
  String get specMethod => 'header';
}

/// A `@CookieValue`: a cookie.
final class CookieArgument extends TextArgument {
  /// The cookie [name] from [parameter].
  CookieArgument(
    super.parameter,
    super.type, {
    required super.name,
    required super.text,
    required super.isIterable,
  });

  @override
  String get specMethod => 'cookie';
}

/// A `@RequestBody`: the body, written by the client's converters.
final class BodyArgument extends HttpArgument {
  /// The body from [parameter].
  BodyArgument(super.parameter, super.type);
}

/// A `@RequestPart`: one part (or several) of a `multipart/form-data` body.
final class PartArgument extends HttpArgument {
  /// The part [name] from [parameter], written as [kind].
  PartArgument(
    super.parameter,
    super.type, {
    required this.name,
    required this.kind,
    this.text = TextKind.string,
  });

  /// The part's name.
  final String name;

  /// How the value becomes parts.
  final PartKind kind;

  /// How a text field's value is written as text.
  final TextKind text;
}

/// How a `@RequestPart` value becomes parts of the body.
enum PartKind {
  /// A `MultipartFile`: a file part with its name and content type.
  multipartFile,

  /// Several `MultipartFile` values: a file part each.
  multipartFiles,

  /// Bytes (`Uint8List`, `List<int>`): a file part without a file name.
  bytes,

  /// A simple value: a text field.
  field,

  /// Several simple values: a text field each.
  fields,

  /// Anything else: a JSON part written with the `ObjectMapper`.
  json,
}

/// How a simple value is written as the text of a header, a cookie, a
/// form field or a text part.
enum TextKind {
  /// A `String`, as it is.
  string,

  /// An enum, by its name.
  enumName,

  /// A `DateTime`, in ISO-8601.
  dateTime,

  /// A number, a `bool`, a `Uri`...: `toString()`.
  other,
}

/// What a method returns, and so what the call reads of the response.
sealed class HttpResponseModel {
  const HttpResponseModel();
}

/// `Future<T>`: the body read as `T`.
final class BodyResponse extends HttpResponseModel {
  /// The body as [type].
  const BodyResponse(this.type);

  /// The type of the body.
  final DartType type;
}

/// `Future<void>`: the status only (an error status throws).
final class BodilessResponse extends HttpResponseModel {
  /// The status only.
  const BodilessResponse();
}

/// `Future<ResponseEntity<T>>`: the status, the headers and the body
/// (`null` [type]: `ResponseEntity<void>`, no body).
final class EntityResponse extends HttpResponseModel {
  /// The entity of a body of [type].
  const EntityResponse(this.type);

  /// The type of the body; `null` for none.
  final DartType? type;
}

/// `Future<HttpHeaders>`: the headers of the response.
final class HeadersResponse extends HttpResponseModel {
  /// The headers.
  const HeadersResponse();
}

/// `EventStream<T>`: the server-sent events, their data as `T`.
final class EventStreamResponse extends HttpResponseModel {
  /// The events of [type].
  const EventStreamResponse(this.type);

  /// The type of each event's data.
  final DartType type;
}

/// `Stream<List<int>>`: the bytes of the body as they arrive.
final class BodyStreamResponse extends HttpResponseModel {
  /// The bytes.
  const BodyStreamResponse();
}
