// spring_boot_starter_restclient's part of the scan: the interfaces each
// `@ImportHttpServices` lists, read into the calls the generated class
// makes, with what Spring's HttpServiceProxyFactory would refuse (or do
// wrong) failing the build instead.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/builder/closest_name.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_model.dart';

// The annotations, matched by the URL of the library that declares them
// (the generator depends on neither the web library nor the starter), so
// a move between the libraries that export them changes nothing.
const _service = 'package:spring_web_dart/src/service';

/// `@HttpExchange` and the shortcuts extending it (`@GetExchange`...).
const httpExchangeChecker = TypeChecker.fromUrl(
  '$_service/http_exchange.dart#HttpExchange',
);

/// `@ImportHttpServices`.
const importHttpServicesChecker = TypeChecker.fromUrl(
  '$_service/import_http_services.dart#ImportHttpServices',
);

const _requestAttribute = TypeChecker.fromUrl(
  '$_service/http_request_attribute.dart#HttpRequestAttribute',
);
const _web = 'package:spring_web_dart/src';
const _mapping = TypeChecker.fromUrl('$_web/annotations.dart#Mapping');
const _responseEntity = TypeChecker.fromUrl(
  '$_web/response_entity.dart#ResponseEntity',
);
const _httpHeaders = TypeChecker.fromUrl(
  '$_web/http_headers.dart#HttpHeaders',
);
const _eventStream = TypeChecker.fromUrl(
  '$_web/sse/event_stream.dart#EventStream',
);
const _multipartFile = TypeChecker.fromUrl(
  '$_web/multipart/multipart.dart#MultipartFile',
);
const _httpMethod = TypeChecker.fromUrl('$_web/http_method.dart#HttpMethod');

// The marker of an annotation whose starter implements the interface it is
// on (`@WebSocketClient`).
const _interfaceProxy = TypeChecker.typeNamedLiterally(
  'InterfaceProxy',
  inPackage: 'spring_core_dart',
);

/// `@SpringBootApplication`, which makes a module an application's.
const springBootApplicationOf = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#SpringBootApplication',
);

// Where a parameter's value goes, by its annotation.
enum _Role {
  path('PathVariable'),
  query('RequestParam'),
  header('RequestHeader'),
  cookie('CookieValue'),
  body('RequestBody'),
  part('RequestPart');

  _Role(this.annotation);

  final String annotation;

  TypeChecker get checker =>
      TypeChecker.fromUrl('$_web/annotations.dart#$annotation');
}

// The client's annotation for each server mapping.
const _exchangeOfMapping = {
  'RequestMapping': 'HttpExchange',
  'GetMapping': 'GetExchange',
  'PostMapping': 'PostExchange',
  'PutMapping': 'PutExchange',
  'PatchMapping': 'PatchExchange',
  'DeleteMapping': 'DeleteExchange',
};

const _returnTypes =
    'Future<T> (the body as T), Future<void> (the status only), '
    'Future<ResponseEntity<T>>, Future<HttpHeaders>, EventStream<T> (the '
    'server-sent events) or Stream<List<int>> (the bytes as they arrive)';

/// Reads the HTTP services of a module into its [HttpServiceModuleModel]:
/// each `@ImportHttpServices` and the interfaces it lists, with their
/// methods' calls; each listed interface becomes a bean
/// ([ModuleScan.addGeneratedBean]) made by an [HttpServiceCreation].
final class HttpServiceScanner {
  /// The scanner of the module of [scan].
  HttpServiceScanner(this.scan);

  /// The module's scan, through which problems are reported.
  final ModuleScan scan;

  HttpServiceModuleModel get _model => HttpServiceModuleModel.of(scan.module);

  /// Keeps [element] among the module's interfaces with calls when it or
  /// one of its methods has an exchange annotation.
  void remember(ClassElement element) {
    bool declaresCalls(Element annotated) => httpExchangeChecker
        .hasAnnotationOf(annotated, throwOnUnresolved: false);
    if (declaresCalls(element) || element.methods.any(declaresCalls)) {
      _model.declared.add(element);
    }
  }

  /// Keeps [element], a class with `@ImportHttpServices`, to import its
  /// interfaces once every library is scanned ([importClasses]).
  void rememberImporter(ClassElement element) {
    if (importHttpServicesChecker.hasAnnotationOf(
      element,
      throwOnUnresolved: false,
    )) {
      _model.importingClasses.add(element);
    }
  }

  /// Imports the interfaces of each class [rememberImporter] kept, as
  /// Spring reads `@ImportHttpServices` only from a class registered as a
  /// bean (a `@Configuration()`, a component) and only when it is: their
  /// beans take the class's conditions (`@Profile`, `@Conditional...`, and
  /// those of the class importing it with `@Import`). On a class that is
  /// no bean it fails the build: nothing would read it.
  void importClasses() {
    for (final element in _model.importingClasses) {
      final conditions = scan.beanClassConditions(element);
      if (conditions == null) {
        scan.collectErrors(
          () => throw InvalidGenerationSource(
            '@ImportHttpServices on ${element.displayName}, which is no '
            'bean: as in Spring, the interfaces are imported by a class '
            'the application registers, and only when it is. Put it on '
            "the application's main or a @Configuration() class.",
            element: element,
          ),
        );
        continue;
      }
      importFrom(
        element,
        HttpServiceImporter(
          element,
          key: scan.requireName(element),
          conditions: conditions,
        ),
      );
    }
  }

  /// Imports the interfaces of each `@ImportHttpServices` on [element] (a
  /// bean class, the application's `main`, a `@ComponentScan` variable)
  /// for [importer] (by default [element], without conditions).
  void importFrom(Element element, [HttpServiceImporter? importer]) {
    final by = importer ?? HttpServiceImporter(element);
    for (final annotation in importHttpServicesChecker.annotationsOf(
      element,
      throwOnUnresolved: false,
    )) {
      final reader = ConstantReader(annotation);
      final name = reader.read('group').stringValue;
      final known = _model.groups
          .where((g) => g.name == name && identical(g.importer, by))
          .firstOrNull;
      final group = known ?? HttpServiceGroupModel(name, by);
      if (known == null) {
        _model.groups.add(group);
      }
      for (final value in reader.read('types').listValue) {
        scan.collectErrors(() => _import(value.toTypeValue(), group));
      }
    }
  }

  void _import(DartType? type, HttpServiceGroupModel declared) {
    final importer = declared.importer.element;
    final group = declared.name;
    final listed = declared.types;
    final where = '@ImportHttpServices on ${importer.displayName}';
    final element = type is InterfaceType ? type.element : null;
    if (element is! ClassElement) {
      throw InvalidGenerationSource(
        '$where lists $type, which is no class: list the HTTP service '
        'interfaces, abstract interface classes whose methods carry '
        '@GetExchange, @PostExchange...',
        element: importer,
      );
    }
    final name = scan.requireName(element);
    if (!element.isAbstract || !element.isInterface) {
      throw InvalidGenerationSource(
        '$where lists $name, which is no abstract interface class: the '
        'build writes the class that implements it, so it declares only '
        'the calls. Declare it `abstract interface class $name`.',
        element: element,
      );
    }
    if (element.typeParameters.isNotEmpty) {
      throw InvalidGenerationSource(
        '$where lists $name, which is generic: the build writes one class '
        'for it, so its types must be known. Remove its type parameters.',
        element: element,
      );
    }
    switch (_model.groupOf[element]) {
      case final known? when known == group:
        final first = _model.importerOf[element]!;
        if (identical(first, declared.importer) ||
            (first.conditions.isEmpty &&
                declared.importer.conditions.isEmpty)) {
          return;
        }
        throw InvalidGenerationSource(
          '$name is imported by ${first.element.displayName} and by '
          '${importer.displayName}, which are registered under different '
          'conditions: its bean would follow only one of them. Import it '
          'once, on the class whose conditions it shares.',
          element: importer,
        );
      case final known?:
        throw InvalidGenerationSource(
          '$name is imported into the groups "$known" and "$group": an '
          'interface belongs to one group, whose RestClient its bean calls. '
          'Remove it from one of the @ImportHttpServices.',
          element: importer,
        );
      case null:
        _model.groupOf[element] = group;
        _model.importerOf[element] = declared.importer;
        listed.add(element.thisType);
    }
    for (final annotation in element.metadata.annotations) {
      final marked = annotation.computeConstantValue()?.type?.element;
      if (marked != null && _interfaceProxy.hasAnnotationOf(marked)) {
        throw InvalidGenerationSource(
          '$name has @${marked.name} and is imported by '
          '@ImportHttpServices: both would implement it. Keep '
          '@ImportHttpServices (and the exchange annotations) or '
          '@${marked.name}, not both.',
          element: element,
        );
      }
    }
    final service = _ServiceReader(scan, element, name, group).read();
    if (service != null) {
      _model.services.add(service);
      scan.addGeneratedBean(
        element,
        HttpServiceCreation(service),
        conditions: declared.importer.conditions,
      );
    }
  }
}

// The settings of one exchange annotation, as written.
final class _Exchange {
  _Exchange(DartObject annotation) : _reader = ConstantReader(annotation);

  final ConstantReader _reader;

  String get url => _reader.peek('url')?.stringValue ?? '';

  // The enum value's name: `HttpMethod.get` is `get`.
  String? get method =>
      _reader.peek('method')?.objectValue.getField('_name')?.toStringValue();

  String? get contentType => _reader.peek('contentType')?.stringValue;

  List<String> get accept => _strings('accept');

  List<String> get headers => _strings('headers');

  String? get version => _reader.peek('version')?.stringValue;

  List<String> _strings(String field) => [
    for (final value in _reader.peek(field)?.listValue ?? const <DartObject>[])
      ?value.toStringValue(),
  ];
}

// Reads one interface; its problems are reported one by one, and an
// interface with any is no bean.
final class _ServiceReader {
  _ServiceReader(this.scan, this.element, this.name, this.group);

  final ModuleScan scan;
  final ClassElement element;
  final String name;
  final String group;

  var _failed = false;

  late final InterfaceType _type = element.thisType;

  late final List<InterfaceType> _hierarchy = [_type, ..._type.allSupertypes];

  // The interface's own `@HttpExchange`, else the nearest supertype's.
  late final _Exchange? _typeExchange = [
    for (final type in _hierarchy)
      if (!type.element.library.isInSdk)
        ?httpExchangeChecker.firstAnnotationOf(type.element),
  ].map(_Exchange.new).firstOrNull;

  // The request attributes of the interface (and its supertypes).
  late final List<HttpAttributeModel> _typeAttributes = [
    for (final type in _hierarchy.reversed)
      if (!type.element.library.isInSdk) ..._attributes(type.element),
  ];

  void _fail(String message, Element at) {
    _failed = true;
    scan.collectErrors(
      () => throw InvalidGenerationSource(message, element: at),
    );
  }

  HttpServiceModel? read() {
    final calls = <HttpCallModel>[];
    for (final method in _methods()) {
      if (_call(method) case final call?) {
        calls.add(call);
      }
    }
    if (_failed) {
      return null;
    }
    return HttpServiceModel(
      className: scan.module.uniqueClassName('_\$${name}HttpService'),
      type: _type,
      group: group,
      calls: calls,
    );
  }

  // The methods the generated class implements: the interface's and its
  // supertypes' (not Object's), one per name.
  List<MethodElement> _methods() {
    final names = <String>{};
    for (final type in _hierarchy) {
      final owner = type.element;
      if (owner.library.isInSdk) {
        continue;
      }
      for (final accessor in [...owner.getters, ...owner.setters]) {
        if (!accessor.isStatic && accessor.name != null) {
          _fail(
            '$name.${accessor.displayName}: an HTTP service interface '
            'declares methods only, each a call; a getter, setter or field '
            'is none. Make it a method with @GetExchange...',
            accessor,
          );
        }
      }
      for (final method in owner.methods) {
        if (method.name case final name? when !method.isStatic) {
          names.add(name);
        }
      }
    }
    return [
      for (final name in names) ?_type.lookUpMethod(name, element.library),
    ];
  }

  HttpCallModel? _call(MethodElement method) {
    final methodName = method.name!;
    final where = '$name.$methodName';
    if (method.isPrivate) {
      _fail(
        '$where is private: the generated class cannot implement it. Make '
        'it public.',
        method,
      );
      return null;
    }
    if (!method.isAbstract) {
      _fail(
        '$where has a body: the generated class implements every method of '
        'the interface as a call, so the body would never run. Remove the '
        'body, or move the code out of the interface.',
        method,
      );
      return null;
    }
    if (method.typeParameters.isNotEmpty) {
      _fail(
        '$where is generic: the call reads the answer as a type the build '
        'must know. Remove its type parameters.',
        method,
      );
      return null;
    }
    for (final annotation in method.metadata.annotations) {
      final type = annotation.computeConstantValue()?.type;
      if (type is InterfaceType && _mapping.isAssignableFromType(type)) {
        final mapping = type.element.name;
        final exchange = _exchangeOfMapping[mapping] ?? 'HttpExchange';
        _fail(
          '@$mapping on $where: it maps the requests a server answers; a '
          'method of an HTTP service interface declares the request it '
          'sends with @$exchange. Write @$exchange instead.',
          method,
        );
        return null;
      }
    }
    final exchanges = httpExchangeChecker.annotationsOf(method).toList();
    if (exchanges.isEmpty) {
      _fail(
        '$where has no exchange annotation, so the build does not know '
        'which request it sends. Add @GetExchange, @PostExchange, '
        '@PutExchange, @PatchExchange, @DeleteExchange or @HttpExchange.',
        method,
      );
      return null;
    }
    if (exchanges.length > 1) {
      _fail(
        '$where has ${exchanges.length} exchange annotations: a method '
        'sends one request. Keep one.',
        method,
      );
      return null;
    }
    final ProxyMember? member;
    try {
      member = scan.proxyMember(
        method,
        _hierarchy,
        method.enclosingElement?.name ?? name,
      );
    } on InvalidGenerationSource catch (error) {
      _fail('$where: ${error.message}', method);
      return null;
    }
    if (member == null) {
      _fail(
        '$where cannot be implemented: a parameter default value is not a '
        'public constant, or its signature uses a private type.',
        method,
      );
      return null;
    }
    final own = _Exchange(exchanges.single);
    final shared = _typeExchange;
    final version = own.version ?? shared?.version;
    if (version != null) {
      _fail(
        '$where asks for the API version "$version": the RestClient has no '
        'API version inserter yet, so the version would not be sent. Send '
        "it as a header (headers: ['X-API-Version=$version']), or as the "
        "group's spring.http.serviceclient.$group.default-header.",
        method,
      );
    }
    final response = _response(method, where);
    final arguments = <HttpArgument>[];
    String? uriParameter;
    String? methodParameter;
    for (final parameter in method.formalParameters) {
      switch (_argument(parameter, where)) {
        case final HttpArgument argument:
          arguments.add(argument);
        case _UriParameter():
          uriParameter = parameter.name;
        case _MethodParameter():
          methodParameter = parameter.name;
        case null:
          break;
      }
    }
    final call = HttpCallModel(
      member: member,
      httpMethod: own.method ?? shared?.method ?? 'get',
      methodParameter: methodParameter,
      url: HttpUrlModel(_joinUrl(shared?.url ?? '', own.url), methodName),
      uriParameter: uriParameter,
      contentType: own.contentType ?? shared?.contentType,
      accept: own.accept.isNotEmpty ? own.accept : shared?.accept ?? const [],
      headers: _headers(shared, own, methodName, method, where),
      attributes: _mergedAttributes(method),
      arguments: arguments,
      response: response ?? const BodilessResponse(),
    );
    _checkUrl(call, method, where);
    _checkBody(call, method, where);
    return _failed || response == null ? null : call;
  }

  // Spring's join of the interface's URL and the method's: one `/`
  // between them (none before a method's own query, `?sort=title`).
  static String _joinUrl(String typeUrl, String methodUrl) {
    if (typeUrl.isEmpty) {
      return methodUrl;
    }
    if (methodUrl.isEmpty) {
      return typeUrl;
    }
    if (methodUrl.startsWith('?')) {
      return '$typeUrl$methodUrl';
    }
    final typeSlash = typeUrl.endsWith('/');
    final methodSlash = methodUrl.startsWith('/');
    return switch ((typeSlash, methodSlash)) {
      (true, true) => '$typeUrl${methodUrl.substring(1)}',
      (false, false) => '$typeUrl/$methodUrl',
      _ => '$typeUrl$methodUrl',
    };
  }

  // The interface's headers, then the method's (one of the same name
  // replaces the interface's).
  List<HttpHeaderModel> _headers(
    _Exchange? shared,
    _Exchange own,
    String methodName,
    MethodElement method,
    String where,
  ) {
    final byName = <String, HttpHeaderModel>{};
    for (final text in [...?shared?.headers, ...own.headers]) {
      final equals = text.indexOf('=');
      final headerName = equals < 0 ? '' : text.substring(0, equals).trim();
      if (headerName.isEmpty) {
        _fail(
          '$where: the header "$text" is not written "Name=value" (several '
          'values separated by commas), as in '
          "headers: ['X-API-Version=2'].",
          method,
        );
        continue;
      }
      byName[headerName.toLowerCase()] = HttpHeaderModel(headerName, [
        for (final value in text.substring(equals + 1).split(',')) value.trim(),
      ], methodName);
    }
    return byName.values.toList();
  }

  // The interface's attributes, then the method's (one of the same name
  // replaces the interface's).
  List<HttpAttributeModel> _mergedAttributes(MethodElement method) => {
    for (final attribute in [..._typeAttributes, ..._attributes(method)])
      attribute.name: attribute,
  }.values.toList();

  List<HttpAttributeModel> _attributes(Element annotated) {
    final attributes = <HttpAttributeModel>[];
    for (final annotation in annotated.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (value == null ||
          type is! InterfaceType ||
          !_requestAttribute.isAssignableFromType(type)) {
        continue;
      }
      final reader = ConstantReader(value);
      final attributeValue = reader.read('attributeValue').objectValue;
      if (!scan.isRecreatable(attributeValue)) {
        _fail(
          '@${type.element.name} on ${annotated.displayName}: the value of '
          'its request attribute is not a public constant, so the generated '
          'call cannot set it. Use a public constant.',
          annotated,
        );
        continue;
      }
      attributes.add(
        HttpAttributeModel(
          reader.read('attributeName').stringValue,
          attributeValue,
          annotated,
        ),
      );
    }
    return attributes;
  }

  HttpResponseModel? _response(MethodElement method, String where) {
    final returnType = method.returnType;
    if (returnType is InterfaceType &&
        returnType.nullabilitySuffix == NullabilitySuffix.none) {
      if (returnType.isDartAsyncFuture) {
        final value = returnType.typeArguments.single;
        if (value is VoidType) {
          return const BodilessResponse();
        }
        if (value is InterfaceType &&
            value.nullabilitySuffix == NullabilitySuffix.none) {
          if (_responseEntity.isExactlyType(value)) {
            final body = value.typeArguments.single;
            if (body is VoidType) {
              return const EntityResponse(null);
            }
            _read(body);
            return EntityResponse(body);
          }
          if (_httpHeaders.isExactlyType(value)) {
            return const HeadersResponse();
          }
        }
        _read(value);
        return BodyResponse(value);
      }
      if (_eventStream.isExactlyType(returnType)) {
        final data = returnType.typeArguments.single;
        _read(data);
        return EventStreamResponse(data);
      }
      if (returnType.isDartAsyncStream &&
          _isByteList(returnType.typeArguments.single)) {
        return const BodyStreamResponse();
      }
    }
    _fail(
      '$where returns $returnType, which a call cannot give. An HTTP '
      'service method returns $_returnTypes.',
      method,
    );
    return null;
  }

  // The classes of the answer are read from JSON: instances are made and
  // filled (`IntrospectionNeed.write`). Those of a body or a JSON part are
  // written to it: their getters are read (`IntrospectionNeed.read`).
  void _read(DartType type) =>
      scan.introspection.need(type, element, IntrospectionNeed.write);

  void _write(DartType type) =>
      scan.introspection.need(type, element, IntrospectionNeed.read);

  Object? _argument(FormalParameterElement parameter, String where) {
    final parameterName = parameter.name ?? '_';
    final subject = '$where: parameter $parameterName';
    final type = parameter.type;
    final roles = [
      for (final role in _Role.values)
        if (role.checker.firstAnnotationOf(parameter) case final annotation?)
          (role, annotation),
    ];
    if (roles.length > 1) {
      _fail(
        '$subject has ${roles.map((r) => '@${r.$1.annotation}').join(' and ')}'
        ': a value goes to one place of the request. Keep one.',
        parameter,
      );
      return null;
    }
    if (roles.isEmpty) {
      if (type is InterfaceType &&
          type.nullabilitySuffix == NullabilitySuffix.none) {
        if (_isCore(type, 'Uri')) {
          return const _UriParameter();
        }
        if (_httpMethod.isExactlyType(type)) {
          return const _MethodParameter();
        }
      }
      _fail(
        '$subject has no annotation, so the build does not know where it '
        'goes in the request (Spring fails such a parameter: "No suitable '
        'resolver"). Add @PathVariable, @RequestParam, @RequestHeader, '
        '@CookieValue, @RequestBody or @RequestPart; a Uri parameter is the '
        'URL of the call, an HttpMethod one its method.',
        parameter,
      );
      return null;
    }
    final (role, annotation) = roles.single;
    final named = ConstantReader(annotation).peek('name')?.stringValue;
    final name = named == null || named.isEmpty ? parameterName : named;
    if (role != _Role.body &&
        role != _Role.part &&
        type is InterfaceType &&
        type.isDartCoreMap) {
      _fail(
        '$subject is a Map with @${role.annotation}: one parameter is one '
        'value (or a list of values) of the name it gives. Declare one '
        'parameter for each name.',
        parameter,
      );
      return null;
    }
    switch (role) {
      case _Role.path:
        if (type.nullabilitySuffix != NullabilitySuffix.none) {
          _fail(
            '$subject is nullable with @PathVariable: a URL has no empty '
            'path segment for null. Make it non-nullable, or send it as '
            'an optional @RequestParam.',
            parameter,
          );
          return null;
        }
        return PathArgument(parameterName, type, name);
      case _Role.query:
        final item = _itemType(type);
        return QueryArgument(
          parameterName,
          type,
          name: name,
          text: _textKind(item ?? type) ?? TextKind.other,
          isIterable: item != null,
        );
      case _Role.header || _Role.cookie:
        final item = _itemType(type);
        final text = _textKind(item ?? type);
        if (item != null && item.nullabilitySuffix != NullabilitySuffix.none) {
          _fail(
            '$subject is a list of nullable values with '
            '@${role.annotation}: a null has no text to send. Make the '
            'items non-nullable.',
            parameter,
          );
          return null;
        }
        if (text == null) {
          _fail(
            '$subject is a ${item ?? type} with @${role.annotation}: a '
            '${role == _Role.header ? 'header' : 'cookie'} is text, and the '
            'build writes a String, a number, a bool, an enum (its name), a '
            'DateTime (ISO-8601) or a list of them. Pass one of those.',
            parameter,
          );
          return null;
        }
        return role == _Role.header
            ? HeaderArgument(
                parameterName,
                type,
                name: name,
                text: text,
                isIterable: item != null,
              )
            : CookieArgument(
                parameterName,
                type,
                name: name,
                text: text,
                isIterable: item != null,
              );
      case _Role.body:
        _write(type);
        return BodyArgument(parameterName, type);
      case _Role.part:
        return _part(parameterName, type, name);
    }
  }

  PartArgument _part(String parameter, DartType type, String name) {
    if (_isBytes(type)) {
      return PartArgument(parameter, type, name: name, kind: PartKind.bytes);
    }
    if (_multipartFile.isAssignableFromType(type)) {
      return PartArgument(
        parameter,
        type,
        name: name,
        kind: PartKind.multipartFile,
      );
    }
    final item = _itemType(type);
    if (item != null && _multipartFile.isAssignableFromType(item)) {
      return PartArgument(
        parameter,
        type,
        name: name,
        kind: PartKind.multipartFiles,
      );
    }
    if (_textKind(item ?? type) case final text?) {
      return PartArgument(
        parameter,
        type,
        name: name,
        kind: item == null ? PartKind.field : PartKind.fields,
        text: text,
      );
    }
    _write(type);
    return PartArgument(parameter, type, name: name, kind: PartKind.json);
  }

  // `Uint8List` or `List<int>`: the bytes of a file part.
  static bool _isBytes(DartType type) =>
      type is InterfaceType &&
      ((type.element.name == 'Uint8List' &&
              type.element.library.uri.toString() == 'dart:typed_data') ||
          (type.isDartCoreList && type.typeArguments.single.isDartCoreInt));

  // `List<int>`, the chunks of a body stream.
  static bool _isByteList(DartType type) =>
      type is InterfaceType &&
      type.isDartCoreList &&
      type.nullabilitySuffix == NullabilitySuffix.none &&
      type.typeArguments.single.isDartCoreInt &&
      type.typeArguments.single.nullabilitySuffix == NullabilitySuffix.none;

  // The item type of a List, Set or Iterable; `null` for another type.
  static DartType? _itemType(DartType type) =>
      type is InterfaceType &&
          (type.isDartCoreList ||
              type.isDartCoreSet ||
              type.isDartCoreIterable) &&
          type.typeArguments.length == 1
      ? type.typeArguments.single
      : null;

  // How a simple value is written as text; `null` for one that is not.
  static TextKind? _textKind(DartType type) {
    if (type is! InterfaceType) {
      return null;
    }
    if (type.isDartCoreString) {
      return TextKind.string;
    }
    if (type.element is EnumElement) {
      return TextKind.enumName;
    }
    if (_isCore(type, 'DateTime')) {
      return TextKind.dateTime;
    }
    if (type.isDartCoreNum ||
        type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreBool ||
        _isCore(type, 'Uri') ||
        _isCore(type, 'BigInt')) {
      return TextKind.other;
    }
    return null;
  }

  // Whether [type] is the class [name] of `dart:core`.
  static bool _isCore(InterfaceType type, String name) =>
      type.element.library.isDartCore && type.element.name == name;

  void _checkUrl(HttpCallModel call, MethodElement method, String where) {
    final paths = [
      for (final argument in call.arguments)
        if (argument is PathArgument) argument,
    ];
    if (call.uriParameter case final uri?) {
      final templated = [
        for (final argument in call.arguments)
          if (argument is PathArgument ||
              (argument is QueryArgument && !call.sendsForm))
            argument.parameter,
      ];
      if (templated.isNotEmpty) {
        _fail(
          '$where: the Uri parameter $uri is the whole URL of the call, and '
          '${templated.join(', ')} would fill the URL of the annotation, '
          'which is not used then. Put the values into the Uri, or remove '
          'the Uri parameter.',
          method,
        );
      }
      return;
    }
    final url = call.url;
    final variables = url.variables;
    final bound = {for (final path in paths) path.name};
    for (final variable in variables.difference(bound)) {
      final close = closestName(variable, {
        ...bound,
        for (final parameter in method.formalParameters) ?parameter.name,
      });
      _fail(
        '$where: the URL "${url.text}" has {$variable}, and no parameter is '
        "@PathVariable('$variable'), so the call could not fill it. Add "
        '@PathVariable() to a parameter named $variable'
        '${close == null ? '' : ' (did you mean $close?)'}, or name it: '
        "@PathVariable('$variable').",
        method,
      );
    }
    for (final path in paths) {
      if (!variables.contains(path.name)) {
        _fail(
          '$where: parameter ${path.parameter} is '
          "@PathVariable('${path.name}'), and the URL \"${url.text}\" has "
          'no {${path.name}}, so its value would go nowhere. Add '
          '{${path.name}} to the URL, or send it as a @RequestParam.',
          method,
        );
      }
    }
  }

  void _checkBody(HttpCallModel call, MethodElement method, String where) {
    final bodies = [
      for (final argument in call.arguments)
        if (argument is BodyArgument) argument.parameter,
    ];
    final parts = [
      for (final argument in call.arguments)
        if (argument is PartArgument) argument.parameter,
    ];
    if (bodies.length > 1) {
      _fail(
        '$where has ${bodies.length} @RequestBody parameters '
        '(${bodies.join(', ')}): a request has one body. Keep one, put the '
        'values into one object, or send them as @RequestPart parts of a '
        'multipart body.',
        method,
      );
    }
    if (bodies.isNotEmpty && parts.isNotEmpty) {
      _fail(
        '$where has @RequestBody ${bodies.first} and @RequestPart '
        '${parts.join(', ')}: a multipart body is made of the parts only. '
        'Make ${bodies.first} a @RequestPart too, or remove the parts.',
        method,
      );
    }
    final contentType = call.contentType?.toLowerCase();
    if (parts.isNotEmpty &&
        contentType != null &&
        !contentType.startsWith('multipart/')) {
      _fail(
        '$where has @RequestPart parameters and the content type '
        '"${call.contentType}": parts are sent as multipart/form-data. '
        'Remove the contentType (the parts set it), or send a @RequestBody.',
        method,
      );
    }
    if (call.sendsForm && bodies.isNotEmpty) {
      _fail(
        '$where sends its @RequestParam values as a form (the content type '
        'is application/x-www-form-urlencoded) and has a @RequestBody: a '
        'request has one body. Remove the @RequestBody, or the form content '
        'type.',
        method,
      );
    }
    final httpMethod = call.httpMethod;
    if (call.methodParameter == null &&
        (httpMethod == 'get' || httpMethod == 'head') &&
        call.hasBody) {
      final what = bodies.isNotEmpty
          ? '@RequestBody ${bodies.first}'
          : parts.isNotEmpty
          ? '@RequestPart ${parts.first}'
          : 'a form of its @RequestParam values';
      _fail(
        '$where is a ${httpMethod.toUpperCase()} request and sends $what: a '
        '${httpMethod.toUpperCase()} request has no body (a browser refuses '
        'one, as Spring advises against it). Use @PostExchange or '
        '@PutExchange, or send the values as @RequestParam.',
        method,
      );
    }
    final streams =
        call.response is EventStreamResponse ||
        call.response is BodyStreamResponse;
    if (streams && call.awaitsParts) {
      _fail(
        '$where returns a stream and sends a MultipartFile: its bytes are '
        'read asynchronously, which a method returning a stream cannot '
        'wait for. Pass the bytes (Uint8List), or return a Future.',
        method,
      );
    }
  }
}

// A parameter of type `Uri`: the URL of the call.
final class _UriParameter {
  const _UriParameter();
}

// A parameter of type `HttpMethod`: the method of the call.
final class _MethodParameter {
  const _MethodParameter();
}
