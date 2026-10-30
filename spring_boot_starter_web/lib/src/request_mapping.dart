import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart';
import 'package:spring_boot_starter_web/src/form_parameters.dart';
import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_boot_starter_web/src/multipart_resolver.dart';
import 'package:spring_boot_starter_web/src/response_writer.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.mvc');

/// The router of the controllers: it finds the controller method for a
/// request, fills its parameters, calls it and writes the result.
///
/// At startup it reads the `@GetMapping`, `@PostMapping`, ... methods of
/// every `@RestController` (and `@Controller`) bean, as the generator
/// described them, and checks them all. A `{variable}` without a
/// `@PathVariable` parameter, a parameter nothing can fill, two
/// `@RequestBody` parameters, two methods mapping the same request, or an
/// `@ExceptionHandler` without an exception type stops the application
/// with the whole list of problems.
///
/// For a request it picks the most specific matching pattern, then checks
/// the method (405), `consumes` (415), `produces` (406) and `headers`
/// (400); it answers `HEAD` with the `GET` mapping, `OPTIONS` with an
/// `Allow` header, and CORS pre-flights from the CORS rules. It also
/// holds the `@ExceptionHandler` methods of the controllers and of the
/// `@ControllerAdvice` beans, which the dispatcher uses for errors.
///
/// The starter declares it as the `requestMappingHandlerMapping` bean at
/// order 0, so it is the first handler mapping asked. Applications do not
/// create it; they write controllers and configure it through
/// `WebMvcConfigurer` beans. The security starter reads its CORS rules
/// (through `DispatcherHandler.corsConfigurationFor`). Spring splits this
/// work between `RequestMappingHandlerMapping` and
/// `RequestMappingHandlerAdapter`.
final class RequestMappingHandlerMapping
    implements HandlerMapping, Ordered, SmartInitializingSingleton {
  /// The router of the controller beans of [beanFactory]. Without a
  /// [multipartResolver], one with the default limits is used.
  RequestMappingHandlerMapping({
    required this.beanFactory,
    required this.writer,
    required this.environment,
    this.argumentResolvers = const [],
    this.interceptors = const [],
    this.corsSource,
    this.corsConfigurationSource,
    this.validator,
    MultipartResolver? multipartResolver,
  }) : multipartResolver = multipartResolver ?? MultipartResolver();

  /// The container whose controller and controller-advice beans are
  /// mapped; the handlers are called on its beans.
  final ListableBeanFactory beanFactory;

  /// Writes the results of handlers and exception handlers.
  final ResponseWriter writer;

  /// Resolves `${...}` placeholders in mapping paths and media types
  /// from the configuration.
  final PropertyResolver environment;

  /// The resolvers added by `WebMvcConfigurer.addArgumentResolvers`;
  /// they are asked before the built-in binding.
  final List<HandlerMethodArgumentResolver> argumentResolvers;

  /// The interceptors added by `WebMvcConfigurer.addInterceptors`, in
  /// order.
  final List<InterceptorRegistration> interceptors;

  /// The global CORS rules of `WebMvcConfigurer.addCorsMappings`,
  /// combined with the `@CrossOrigin` of the handler, as Spring MVC's
  /// global CORS configuration; `null` when there are none.
  final CorsConfigurationSource? corsSource;

  /// The application's `CorsConfigurationSource` bean named
  /// `corsConfigurationSource` (the starter passes no other: beans of the
  /// type with other names are ignored, as by Spring Security), `null`
  /// when there is none. Where it has a configuration for a request, that
  /// configuration alone applies, neither [corsSource] nor `@CrossOrigin`:
  /// as with Spring Security, whose `CorsFilter` applies the
  /// `corsConfigurationSource` bean before Spring MVC, which then leaves
  /// the request as the filter answered it. So CORS works the same with
  /// and without the security starter. Elsewhere [corsSource] and
  /// `@CrossOrigin` apply.
  final CorsConfigurationSource? corsConfigurationSource;

  /// Checks `@Valid()` arguments; `null` when the application has no
  /// unique `Validator`, and then `@Valid()` checks nothing.
  final Validator? validator;

  /// Reads `multipart/form-data` requests for `@RequestPart` parameters,
  /// uploaded files and multipart form fields.
  final MultipartResolver multipartResolver;

  final _mappings = <_Mapping>[];
  final _advice = <_Advice>[];
  // The controllers' definitions, for the selectors of narrowed advice.
  final _controllers = <String, BeanDefinition<Object>>{};
  var _initialized = false;

  @override
  int get order => 0;

  /// Every mapping as text, such as
  /// `GET /api/books/{isbn} -> BookController.find`, in matching order;
  /// for diagnostics. Empty before [initialize].
  List<String> get mappings => [
    for (final mapping in _mappings) mapping.toString(),
  ];

  /// Calls [initialize] once every singleton exists, so an invalid
  /// controller stops the startup instead of the first request.
  @override
  void afterSingletonsInstantiated() => initialize();

  /// Finds the controllers and the controller advice, builds the
  /// mappings and checks them. Throws a [StateError] that lists every
  /// problem found. Later calls do nothing; the lookup methods call it
  /// when it has not run yet.
  void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    final problems = <String>[];
    final registry = beanFactory as BeanDefinitionRegistry;
    final local = <String, List<ExceptionHandlerMethod>>{};
    for (final name in beanFactory.getBeanNamesForAnnotation<Controller>()) {
      if (!registry.containsBeanDefinition(name)) {
        continue;
      }
      final definition = registry.getBeanDefinition(name);
      _controllers[name] = definition;
      final typeName = _typeName(definition.beanType);
      final classMapping = definition.annotations
          .whereType<Mapping>()
          .firstOrNull;
      final handlers = <ExceptionHandlerMethod>[];
      for (final method in definition.annotatedMethods) {
        final handler = HandlerMethod(
          beanName: name,
          beanTypeName: typeName,
          method: method,
          classAnnotations: definition.annotations,
          beanFactory: beanFactory,
        );
        if (method.annotations.whereType<ExceptionHandler>().isNotEmpty) {
          handlers.add(_exceptionHandler(handler, problems));
        }
        final mappings = method.annotations.whereType<Mapping>().toList();
        if (mappings.isEmpty) {
          continue;
        }
        if (mappings.length > 1) {
          problems.add(
            '${handler.description} has several mapping annotations; use '
            'one (@RequestMapping.of for other methods)',
          );
          continue;
        }
        final mapping = _compile(
          handler,
          classMapping,
          mappings.single,
          problems,
        );
        if (mapping != null) {
          _mappings.add(mapping);
        }
      }
      local[name] = handlers;
    }
    for (final mapping in _mappings) {
      mapping.localExceptionHandlers =
          local[mapping.handler.beanName] ?? const [];
    }
    final adviceNames = beanFactory
        .getBeanNamesForAnnotation<ControllerAdvice>();
    final advice = <(int, int, String)>[];
    for (final name in adviceNames) {
      if (!registry.containsBeanDefinition(name)) {
        continue;
      }
      final definition = registry.getBeanDefinition(name);
      advice.add((
        definition.order ?? Ordered.lowestPrecedence,
        advice.length,
        name,
      ));
    }
    // By @Order; equal orders keep the registration order (a stable sort,
    // as Spring's OrderComparator).
    advice.sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );
    for (final (_, _, name) in advice) {
      final definition = registry.getBeanDefinition(name);
      final handlers = <ExceptionHandlerMethod>[];
      for (final method in definition.annotatedMethods) {
        if (method.annotations.whereType<ExceptionHandler>().isEmpty) {
          continue;
        }
        handlers.add(
          _exceptionHandler(
            HandlerMethod(
              beanName: name,
              beanTypeName: _typeName(definition.beanType),
              method: method,
              classAnnotations: definition.annotations,
              beanFactory: beanFactory,
            ),
            problems,
          ),
        );
      }
      final annotation = definition.annotations
          .whereType<ControllerAdvice>()
          .firstOrNull;
      _advice.add(_Advice(name, annotation, handlers));
    }
    // Two methods for the same request.
    final seen = <String, _Mapping>{};
    for (final mapping in _mappings) {
      for (final key in mapping.keys) {
        final other = seen[key];
        if (other != null) {
          problems.add(
            'Ambiguous mapping: ${mapping.handler.description} and '
            '${other.handler.description} both map $key',
          );
        } else {
          seen[key] = mapping;
        }
      }
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid controllers:\n${problems.map((p) => '  - $p').join('\n')}',
      );
    }
    _mappings.sort((a, b) => a.compareTo(b));
    for (final mapping in _mappings) {
      _log.debug('Mapped $mapping');
    }
  }

  static String _typeName(Type type) {
    final text = '$type';
    final generic = text.indexOf('<');
    return generic < 0 ? text : text.substring(0, generic);
  }

  _Mapping? _compile(
    HandlerMethod handler,
    Mapping? classMapping,
    Mapping mapping,
    List<String> problems,
  ) {
    final before = problems.length;
    PathPattern parse(String text) {
      try {
        return PathPattern.parse(environment.resolvePlaceholders(text));
      } on FormatException catch (error) {
        problems.add('${handler.description}: ${error.message} in "$text"');
        return PathPattern.parse('/');
      }
    }

    final base = classMapping == null ? null : parse(classMapping.path);
    final own = parse(mapping.path);
    final pattern = base == null ? own : base.combine(own);
    final produces = _mediaTypes(
      mapping.produces ?? classMapping?.produces,
      handler,
      'produces',
      problems,
    );
    final consumes = _mediaTypes(
      mapping.consumes ?? classMapping?.consumes,
      handler,
      'consumes',
      problems,
    );
    final headerConditions = [...?classMapping?.headers, ...mapping.headers]
        .map((h) => _HeaderCondition.parse(h, handler, problems))
        .nonNulls
        .toList();
    final binders = <_Binder>[];
    final variables = pattern.variableNames.toSet();
    final bound = <String>{};
    var bodies = 0;
    for (final parameter in handler.parameters) {
      final binder = _binderFor(parameter, problems, variables, bound);
      if (binder == null) {
        continue;
      }
      if (binder.isBody) {
        bodies++;
      }
      binders.add(binder);
    }
    if (bodies > 1) {
      problems.add('${handler.description} has more than one @RequestBody');
    }
    for (final variable in variables) {
      if (!bound.contains(variable)) {
        problems.add(
          '${handler.description}: the path variable {$variable} of '
          '"${pattern.pattern}" has no @PathVariable parameter',
        );
      }
    }
    final result = handler.method.returnTypeInfo;
    if (handler.method.isFuture && result != null && _isStream(result)) {
      problems.add(
        '${handler.description} returns a Future of a stream: return the '
        'EventStream / Stream directly',
      );
    }
    final cors = _crossOrigin(handler, mapping.method, problems);
    if (problems.length != before) {
      return null;
    }
    return _Mapping(
      this,
      handler,
      pattern,
      mapping.method,
      produces,
      consumes,
      headerConditions,
      binders,
      cors,
    );
  }

  static bool _isStream(TypeInfo<Object?> type) =>
      type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>();

  CorsConfiguration? _crossOrigin(
    HandlerMethod handler,
    HttpMethod method,
    List<String> problems,
  ) {
    final onClass = handler.classAnnotations
        .whereType<CrossOrigin>()
        .firstOrNull;
    final onMethod = handler.method.annotations
        .whereType<CrossOrigin>()
        .firstOrNull;
    if (onClass == null && onMethod == null) {
      return null;
    }
    CorsConfiguration? of(CrossOrigin? annotation) => annotation == null
        ? null
        : CorsConfiguration(
            allowedOrigins: annotation.origins,
            allowedOriginPatterns: annotation.originPatterns,
            allowedMethods: annotation.methods,
            allowedHeaders: annotation.allowedHeaders,
            exposedHeaders: annotation.exposedHeaders,
            allowCredentials: annotation.allowCredentials,
            allowPrivateNetwork: annotation.allowPrivateNetwork,
            maxAge: annotation.maxAge == null
                ? null
                : Duration(seconds: annotation.maxAge!),
          );
    final combined = (of(onClass) ?? CorsConfiguration()).combine(
      of(onMethod),
    );
    if (combined.allowedMethods.isEmpty) {
      // Spring's initCorsConfiguration: the methods the handler is mapped
      // to (not GET, HEAD and POST).
      combined.allowedMethods.add(method.value);
    }
    combined.applyPermitDefaultValues();
    // Spring's validateAllowCredentials and validateAllowPrivateNetwork,
    // at startup, on the origins as checked ('https://a.example, *' holds
    // "*").
    for (final (validate, attribute, why) in [
      (
        combined.validateAllowCredentials,
        'allowCredentials',
        'with credentials',
      ),
      (
        combined.validateAllowPrivateNetwork,
        'allowPrivateNetwork',
        'to a private network',
      ),
    ]) {
      try {
        validate();
      } on StateError {
        problems.add(
          '${handler.description}: @CrossOrigin($attribute: true) needs '
          'origins or originPatterns (all origins, "*", cannot be allowed '
          '$why)',
        );
      }
    }
    return combined;
  }

  List<MediaType> _mediaTypes(
    String? value,
    HandlerMethod handler,
    String what,
    List<String> problems,
  ) {
    if (value == null || value.trim().isEmpty) {
      return const [];
    }
    try {
      return MediaType.parseMediaTypes(environment.resolvePlaceholders(value));
    } on InvalidMediaTypeException catch (error) {
      problems.add('${handler.description}: invalid $what "$value": $error');
      return const [];
    }
  }

  // ---------------------------------------------------------------------
  // Arguments
  // ---------------------------------------------------------------------

  _Binder? _binderFor(
    MethodParameter parameter,
    List<String> problems,
    Set<String> variables,
    Set<String> bound,
  ) {
    final name = parameter.handler.description;
    for (final resolver in argumentResolvers) {
      if (resolver.supportsParameter(parameter)) {
        return _Binder(
          parameter,
          (call) =>
              resolver.resolveArgument(parameter, call.request, call.response),
        );
      }
    }
    final roles = [
      parameter.annotation<PathVariable>(),
      parameter.annotation<RequestParam>(),
      parameter.annotation<RequestHeader>(),
      parameter.annotation<CookieValue>(),
      parameter.annotation<RequestBody>(),
      parameter.annotation<RequestPart>(),
    ].nonNulls.toList();
    if (roles.length > 1) {
      problems.add('$name: parameter ${parameter.name} has several roles');
      return null;
    }
    final type = parameter.type;
    switch (roles.firstOrNull) {
      case final PathVariable variable:
        final key = variable.name ?? parameter.name;
        if (!variables.contains(key)) {
          problems.add('$name: @PathVariable "$key" is not in the path');
          return null;
        }
        bound.add(key);
        _checkConvertible(parameter, '@PathVariable', problems);
        return _Binder(parameter, (call) {
          final value = call.variables[key];
          if (value == null) {
            return _absentOr(parameter, 'path variable', key);
          }
          return _convert([value], parameter, key);
        });
      case final RequestParam param:
        return _requestParam(param.name ?? parameter.name, parameter, problems);
      case final RequestHeader header:
        final key = header.name ?? parameter.name;
        if (type.type == HttpHeaders) {
          return _Binder(parameter, (call) => call.request.headers);
        }
        if (type is MapType) {
          return _Binder(parameter, (call) {
            final headers = call.request.headers;
            final value = type.value;
            final multi = value is ListType;
            return _convertMap(
              {
                for (final name in headers.names)
                  name: multi ? headers.getAll(name) : [headers[name]!],
              },
              type,
              parameter,
            );
          });
        }
        _checkConvertible(parameter, '@RequestHeader', problems);
        return _Binder(parameter, (call) {
          final values = call.request.headers.getAll(key);
          if (values.isEmpty) {
            return _absentOr(parameter, 'header', key);
          }
          return _convert(values, parameter, key);
        });
      case final CookieValue cookie:
        final key = cookie.name ?? parameter.name;
        _checkConvertible(parameter, '@CookieValue', problems);
        return _Binder(parameter, (call) {
          final value = call.request.cookies[key];
          if (value == null) {
            return _absentOr(parameter, 'cookie', key);
          }
          return _convert([value], parameter, key);
        });
      case RequestBody():
        return _Binder(
          parameter,
          (call) => _readBody(call, parameter),
          isBody: true,
        );
      case final RequestPart part:
        final key = part.name ?? parameter.name;
        return _Binder(
          parameter,
          (call) => _requestPart(call, parameter, key),
        );
    }
    // Without an annotation: the request itself, or a simple value as a
    // query parameter (like Spring's default @RequestParam).
    // The exact type: a subtype of these is a value to convert, not the
    // request.
    // ignore: switch_on_type
    switch (type.type) {
      case const (ServerHttpRequest):
        return _Binder(parameter, (call) => call.request);
      case const (ServerHttpResponse):
        return _Binder(parameter, (call) => call.response);
      case const (HttpHeaders):
        return _Binder(parameter, (call) => call.request.headers);
      case const (HttpMethod):
        return _Binder(parameter, (call) => call.request.method);
      case const (Uri):
        return _Binder(parameter, (call) => call.request.uri);
      case const (Principal):
        return _Binder(parameter, (call) {
          final principal = call.request.principal;
          if (principal == null && !type.nullable) {
            throw ResponseStatusException(HttpStatus.unauthorized);
          }
          return principal;
        });
    }
    if (_isSimple(type) || _isFileType(type)) {
      return _requestParam(parameter.name, parameter, problems);
    }
    problems.add(
      '$name: parameter ${parameter.name} (${parameter.type}) needs '
      '@PathVariable, @RequestParam, @RequestHeader, @CookieValue or '
      '@RequestBody',
    );
    return null;
  }

  _Binder _requestParam(
    String key,
    MethodParameter parameter,
    List<String> problems,
  ) {
    final type = parameter.type;
    if (_isFileType(type)) {
      return _Binder(
        parameter,
        (call) => _requestPart(call, parameter, key),
      );
    }
    if (type is MapType) {
      return _Binder(parameter, (call) async {
        final request = call.request;
        return _convertMap(
          {
            if (multipartResolver.isMultipart(request))
              ...(await multipartResolver.resolve(request)).fields,
            ...?(await readFormParameters(request)).$2,
            ...request.queryParameters,
          },
          type,
          parameter,
        );
      });
    }
    _checkConvertible(parameter, '@RequestParam', problems);
    return _Binder(parameter, (call) {
      final request = call.request;
      final values = request.queryParameters[key];
      if (values != null && values.isNotEmpty) {
        return _convert(values, parameter, key);
      }
      // Like a servlet's parameters: the fields of a form too.
      final contentType = request.contentType;
      if (contentType != null &&
          contentType.type == 'application' &&
          contentType.subtype == 'x-www-form-urlencoded') {
        return readFormParameters(request).then((form) {
          final fields = form.$2?[key];
          if (fields == null || fields.isEmpty) {
            return _absentOr(parameter, 'parameter', key);
          }
          return _convert(fields, parameter, key);
        });
      }
      if (multipartResolver.isMultipart(request)) {
        return multipartResolver.resolve(request).then((multipart) {
          final fields = multipart.fields[key];
          if (fields == null || fields.isEmpty) {
            return _absentOr(parameter, 'parameter', key);
          }
          return _convert(fields, parameter, key);
        });
      }
      return _absentOr(parameter, 'parameter', key);
    });
  }

  static bool _isFileType(TypeInfo<Object?> type) =>
      type.type == MultipartFile ||
      (type is ListType<Object?> && type.element.type == MultipartFile);

  // A part of a multipart request: files, text fields, bytes, or a part
  // read by its Content-Type (JSON) into the parameter's type.
  Future<Object?> _requestPart(
    _Call call,
    MethodParameter parameter,
    String key,
  ) async {
    final request = call.request;
    if (!multipartResolver.isMultipart(request)) {
      throw MultipartRequestException(
        'the request is not a multipart request (Content-Type '
        '${request.headers.contentType ?? 'missing'})',
      );
    }
    final multipart = await multipartResolver.resolve(request);
    final type = parameter.type;
    Object? missing() => _absentOr(parameter, 'part', key);
    if (type is ListType<Object?> && type.element.type == MultipartFile) {
      final files = multipart.files[key];
      if (files == null || files.isEmpty) {
        final value = missing();
        return identical(value, absent) && !type.nullable
            ? <MultipartFile>[]
            : value;
      }
      return List<MultipartFile>.of(files);
    }
    if (type.type == MultipartFile) {
      return multipart.files[key]?.firstOrNull ?? missing();
    }
    final base = type.type;
    final file = multipart.files[key]?.firstOrNull;
    final raw = multipart.part(key);
    if (base == Uint8List || base == List<int>) {
      if (file != null) {
        return await file.bytes;
      }
      return raw?.$2 ?? missing();
    }
    if (_isSimple(type)) {
      final fields = multipart.fields[key];
      if (fields != null && fields.isNotEmpty) {
        return _convert(fields, parameter, key);
      }
      if (file != null) {
        return _convert(
          [utf8.decode(await file.bytes, allowMalformed: true)],
          parameter,
          key,
        );
      }
      return missing();
    }
    // An object: the part's JSON.
    final Uint8List bytes;
    if (raw != null) {
      bytes = raw.$2;
    } else if (file != null) {
      bytes = await file.bytes;
    } else {
      return missing();
    }
    final Object? value;
    try {
      value = writer.mapper.treeToValue<Object?>(
        jsonDecode(utf8.decode(bytes, allowMalformed: true)),
        type,
      );
    } on Object catch (error) {
      throw HttpMessageNotReadableException(
        'JSON parse error in part "$key": $error',
        error,
      );
    }
    if (value != null && _validates(parameter)) {
      _validate(value, parameter);
    }
    return value;
  }

  // A missing value: absent (null, or the Dart default) for a nullable
  // parameter or one with a default value, else a 400.
  Object? _absentOr(MethodParameter parameter, String kind, String key) {
    if (!parameter.type.nullable && parameter.parameter.isRequired) {
      throw MissingRequestValueException(kind, key);
    }
    return absent;
  }

  void _checkConvertible(
    MethodParameter parameter,
    String role,
    List<String> problems,
  ) {
    var type = parameter.type;
    if (type is ListType<Object?>) {
      type = type.element;
    } else if (type is SetType<Object?>) {
      type = type.element;
    }
    if (!_isSimple(type)) {
      problems.add(
        '${parameter.handler.description}: the $role parameter '
        '${parameter.name} (${parameter.type}) is not a simple value; use a '
        'String, number, bool, enum, DateTime, Duration, Uri or a List of '
        'them',
      );
    }
  }

  static const _simpleTypes = {
    String,
    int,
    double,
    num,
    bool,
    BigInt,
    DateTime,
    Duration,
    Uri,
    Object,
  };

  static bool _isSimple(TypeInfo<Object?> type) => switch (type) {
    EnumType() || DynamicType() => true,
    ListType(:final element) || SetType(:final element) =>
      element is! ListType && element is! SetType && _isSimple(element),
    ClassType() => _simpleTypes.contains(type.type),
    _ => false,
  };

  Object? _convert(List<String> values, MethodParameter parameter, String key) {
    final type = parameter.type;
    try {
      return switch (type) {
        ListType(:final element) => _list(values, element, key),
        SetType(:final element) => _list(values, element, key).toSet(),
        _ => _scalar(values.first, type, key),
      };
    } on MethodArgumentTypeMismatchException {
      rethrow;
    } on Object catch (error) {
      throw MethodArgumentTypeMismatchException(
        key,
        values.join(','),
        '${parameter.type}',
        error,
      );
    }
  }

  List<Object?> _list(
    List<String> values,
    TypeInfo<Object?> element,
    String key,
  ) {
    final items = values.length == 1 && values.single.contains(',')
        ? values.single.split(',').map((v) => v.trim()).toList()
        : values;
    return element.capture(
      <E>() => <E>[for (final item in items) _scalar(item, element, key) as E],
    );
  }

  Object? _scalar(String text, TypeInfo<Object?> type, String key) {
    if (type is EnumType<Enum>) {
      return _enum(text, type, key);
    }
    final target = type.type;
    if (target == String || target == Object || type is DynamicType) {
      return text;
    }
    if (target == int) {
      return int.tryParse(text.trim()) ?? _mismatch(key, text, type);
    }
    if (target == double) {
      return double.tryParse(text.trim()) ?? _mismatch(key, text, type);
    }
    if (target == num) {
      return num.tryParse(text.trim()) ?? _mismatch(key, text, type);
    }
    if (target == BigInt) {
      return BigInt.tryParse(text.trim()) ?? _mismatch(key, text, type);
    }
    if (target == bool) {
      return switch (text.trim().toLowerCase()) {
        'true' || 'on' || 'yes' || '1' => true,
        'false' || 'off' || 'no' || '0' => false,
        _ => _mismatch(key, text, type),
      };
    }
    if (target == DateTime) {
      return DateTime.tryParse(text.trim()) ?? _mismatch(key, text, type);
    }
    if (target == Duration) {
      return DurationStyle.parse(text.trim());
    }
    if (target == Uri) {
      return Uri.tryParse(text.trim()) ?? _mismatch(key, text, type);
    }
    return _mismatch(key, text, type);
  }

  Object? _enum(String text, EnumType<Enum> type, String key) {
    final trimmed = text.trim();
    for (final value in type.values) {
      if ('${type.toJsonValue(value)}' == trimmed) {
        return value;
      }
    }
    for (final value in type.values) {
      if (value.name.toLowerCase() == trimmed.toLowerCase()) {
        return value;
      }
    }
    return _mismatch(key, text, type);
  }

  Never _mismatch(String key, String value, TypeInfo<Object?> type) =>
      throw MethodArgumentTypeMismatchException(key, value, '$type');

  Object? _convertMap(
    Map<String, List<String>> values,
    MapType<Object?, Object?> type,
    MethodParameter parameter,
  ) {
    final value = type.value;
    return type.capture(
      <M>() => {
        for (final entry in values.entries)
          if (entry.value.isNotEmpty)
            entry.key: value is ListType<Object?>
                ? _list(entry.value, value.element, entry.key)
                : _scalar(entry.value.first, value, entry.key),
      },
    );
  }

  Future<Object?> _readBody(_Call call, MethodParameter parameter) async {
    final request = call.request;
    final type = parameter.type;
    final base = type.type;
    Object? value;
    if (type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>()) {
      return request.body;
    }
    // The media type is checked before the body is read, as Spring picks
    // its converter first: a body nothing can read is a 415 at once.
    final header = request.headers.contentType;
    final contentType = request.contentType;
    final raw = base == Uint8List || base == (List<int>) || base == String;
    // A Content-Type that does not parse is a 415 whatever the parameter,
    // as Spring's InvalidMediaTypeException.
    if (contentType == null && header != null && header.trim().isNotEmpty) {
      throw HttpMediaTypeNotSupportedException(
        header,
        raw ? const [] : const [MediaType.applicationJson],
      );
    }
    final form =
        contentType != null &&
        contentType.subtype == 'x-www-form-urlencoded' &&
        type is MapType<Object?, Object?>;
    if (!raw && !form && contentType != null && !_isJson(contentType)) {
      throw HttpMediaTypeNotSupportedException(
        request.headers.contentType,
        const [MediaType.applicationJson],
      );
    }
    var bytes = Uint8List(0);
    try {
      if (!raw && contentType == null) {
        // No Content-Type: Spring reads it as application/octet-stream,
        // which JSON does not read. A body in a POST, PUT or PATCH is a
        // 415; no body, or one in another method, is a missing body.
        if (await _hasBody(request) &&
            const {
              HttpMethod.post,
              HttpMethod.put,
              HttpMethod.patch,
            }.contains(request.method)) {
          throw HttpMediaTypeNotSupportedException(
            MediaType.applicationOctetStream,
            const [MediaType.applicationJson],
          );
        }
      } else {
        bytes = await request.readBodyBytes();
      }
    } on PayloadTooLargeException catch (error) {
      throw PayloadTooLargeErrorException(error.maxLength);
    }
    final optional = type.nullable || !parameter.parameter.isRequired;
    if (bytes.isEmpty) {
      if (optional) {
        return type.nullable ? null : absent;
      }
      throw HttpMessageNotReadableException(
        'Required request body is missing: ${parameter.handler.description}',
      );
    }
    if (base == Uint8List || base == List<int>) {
      value = bytes;
    } else if (base == String) {
      value = _decodeText(bytes, request);
    } else {
      if (form) {
        final Map<String, String> fields;
        try {
          fields = Uri.splitQueryString(_decodeText(bytes, request));
        } on Object catch (error) {
          // A malformed %-escape, or one that is not UTF-8.
          throw HttpMessageNotReadableException(
            'Invalid form body: $error',
            error,
          );
        }
        value = _convertMap(
          {
            for (final entry in fields.entries) entry.key: [entry.value],
          },
          type,
          parameter,
        );
      } else {
        try {
          value = writer.mapper.treeToValue<Object?>(
            jsonDecode(_decodeText(bytes, request)),
            type,
          );
        } on Object catch (error) {
          throw HttpMessageNotReadableException(
            'JSON parse error: $error',
            error,
          );
        }
      }
    }
    if (value != null && _validates(parameter)) {
      _validate(value, parameter);
    }
    return value;
  }

  // Whether the body has at least one byte; reads no more than its
  // first chunk, as Spring's EmptyBodyCheckingHttpInputMessage peeks.
  static Future<bool> _hasBody(ServerHttpRequest request) async {
    await for (final chunk in request.body) {
      if (chunk.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static bool _isJson(MediaType type) =>
      (type.type == 'application' &&
          (type.subtype == 'json' || type.subtype.endsWith('+json'))) ||
      type.isWildcardType;

  static String _decodeText(Uint8List bytes, ServerHttpRequest request) {
    final charset = request.contentType?.getParameter('charset')?.toLowerCase();
    return switch (charset) {
      'iso-8859-1' || 'latin1' || 'latin-1' => latin1.decode(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }

  static bool _validates(MethodParameter parameter) =>
      parameter.has<Valid>() || parameter.has<Validated>();

  void _validate(Object value, MethodParameter parameter) {
    final validator = this.validator;
    if (validator == null) {
      return;
    }
    final result = BeanPropertyBindingResult(value, parameter.name);
    final groups = parameter.annotation<Validated>()?.value ?? const <Type>[];
    if (groups.isNotEmpty && validator is SmartValidator) {
      validator.validateWithGroups(value, result, groups);
    } else {
      validator.validate(value, result);
    }
    if (result.hasErrors) {
      throw MethodArgumentNotValidException(parameter.name, result);
    }
  }

  // ---------------------------------------------------------------------
  // Exception handlers
  // ---------------------------------------------------------------------

  ExceptionHandlerMethod _exceptionHandler(
    HandlerMethod handler,
    List<String> problems,
  ) {
    final annotation = handler.method.annotations
        .whereType<ExceptionHandler>()
        .first;
    MethodParameter? exceptionParameter;
    final binders = <_Binder>[];
    for (final parameter in handler.parameters) {
      final type = parameter.type.type;
      if (type == ServerHttpRequest) {
        binders.add(_Binder(parameter, (call) => call.request));
      } else if (type == ServerHttpResponse) {
        binders.add(_Binder(parameter, (call) => call.response));
      } else if (type == HttpHeaders) {
        binders.add(_Binder(parameter, (call) => call.request.headers));
      } else if (exceptionParameter == null) {
        exceptionParameter = parameter;
        binders.add(_Binder(parameter, (call) => call.error));
      } else {
        problems.add(
          '@ExceptionHandler ${handler.description}: parameter '
          '${parameter.name} must be the exception, the ServerHttpRequest, '
          'the ServerHttpResponse or the HttpHeaders',
        );
      }
    }
    if (exceptionParameter == null && annotation.value.isEmpty) {
      problems.add(
        '@ExceptionHandler ${handler.description}: give the exception types '
        '(@ExceptionHandler([MyException])) or take the exception as a '
        'parameter',
      );
    }
    return ExceptionHandlerMethod._(
      handler,
      annotation.value,
      exceptionParameter,
      binders,
    );
  }

  /// The `@ExceptionHandler` method that answers [error], or `null` when
  /// none handles it.
  ///
  /// The methods of the controller of [handler] (the handler that threw)
  /// come first, then the `@ControllerAdvice` beans in `@Order`, as in
  /// Spring's `ExceptionHandlerExceptionResolver`: the first advice bean
  /// that applies to the controller and has a method for the error
  /// answers it, even when a later bean has a more specific one. Within
  /// one bean, a method that lists the error's exact runtime type in
  /// `@ExceptionHandler([...])` wins, else the one whose exception
  /// parameter has the most specific type. An advice narrowed with
  /// `ControllerAdvice.of` applies only to the controllers it selects,
  /// and not to errors without a [handler].
  ExceptionHandlerMethod? exceptionHandlerFor(
    Object error, {
    HandlerMethod? handler,
  }) {
    if (!_initialized) {
      initialize();
    }
    if (handler != null) {
      final mapping = _mappings
          .where((m) => m.handler.beanName == handler.beanName)
          .firstOrNull;
      if (mapping != null) {
        final local = ExceptionHandlerMethod._best(
          mapping.localExceptionHandlers,
          error,
        );
        if (local != null) {
          return local;
        }
      }
    }
    final controller = handler == null ? null : _controllers[handler.beanName];
    for (final advice in _advice) {
      if (!advice.appliesTo(handler == null ? null : controller)) {
        continue;
      }
      if (ExceptionHandlerMethod._best(advice.handlers, error)
          case final found?) {
        return found;
      }
    }
    return null;
  }

  /// Answers [error] with its `@ExceptionHandler` method (see
  /// [exceptionHandlerFor]) and writes the method's result; returns
  /// `true` when it did. Returns `false` when no method handles the
  /// error, when the response is already committed, or when the
  /// exception handler itself throws (that is logged); the caller then
  /// writes the default error answer.
  Future<bool> handleException(
    Object error,
    ServerHttpRequest request,
    ServerHttpResponse response, {
    HandlerMethod? handler,
  }) async {
    final exceptionHandler = exceptionHandlerFor(error, handler: handler);
    if (exceptionHandler == null || response.isCommitted) {
      return false;
    }
    final call = _Call(request, response, const {}, error: error);
    try {
      final result = await exceptionHandler._invoke(call);
      await writer.writeResult(
        result,
        request,
        response,
        handler: exceptionHandler.handler,
      );
      return true;
    } on Object catch (handlerError, stackTrace) {
      _log.warning(
        'The @ExceptionHandler ${exceptionHandler.handler.description} '
        'failed handling $error',
        error: handlerError,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------

  @override
  HttpHandler? getHandler(ServerHttpRequest request) {
    if (!_initialized) {
      initialize();
    }
    return switch (_lookup(request)) {
      null => null,
      _PreFlightLookup(:final mapping?) => _PreFlightHandler(
        (request) => _corsConfig(mapping, request, validate: true),
      ),
      _PreFlightLookup() => _PreFlightHandler(
        (request) => _globalCors(request, validate: true),
      ),
      _OptionsLookup(:final allowed) => _OptionsHandler(
        allowed,
        (request) => _globalCors(request, validate: true),
      ),
      _HandlerLookup(:final mapping, :final variables) => _Execution(
        mapping,
        variables,
      ),
    };
  }

  // The router's choice for [request], made as Spring's
  // RequestMappingInfoHandlerMapping makes it: `null` for a path no
  // handler maps; throws the 405, 415, 406 and 400 exceptions.
  _Lookup? _lookup(ServerHttpRequest request) {
    final path = request.path;
    final matches = <(_Mapping, PathMatch)>[];
    for (final mapping in _mappings) {
      final match = mapping.pattern.match(path);
      if (match != null) {
        matches.add((mapping, match));
      }
    }
    if (matches.isEmpty) {
      return null;
    }
    final preFlight = isPreFlightRequest(request);
    var method = request.method;
    if (preFlight) {
      final requested =
          request.headers[HttpHeaders.accessControlRequestMethodHeader] ?? '';
      method =
          HttpMethod.values
              .where((m) => m.value == requested.trim())
              .firstOrNull ??
          HttpMethod.options;
    }
    final byMethod = [
      for (final match in matches)
        if (match.$1.method == method ||
            (method == HttpMethod.head && match.$1.method == HttpMethod.get))
          match,
    ];
    if (byMethod.isEmpty) {
      if (preFlight) {
        // No handler for the announced method: the global rules alone
        // decide, and a refused pre-flight is a 403, as in Spring (never
        // a 405).
        return const _PreFlightLookup(null);
      }
      final allowed = {for (final (m, _) in matches) m.method};
      if (allowed.contains(HttpMethod.get)) {
        allowed.add(HttpMethod.head);
      }
      if (method == HttpMethod.options) {
        return _OptionsLookup(allowed);
      }
      throw HttpRequestMethodNotSupportedException(method, allowed);
    }
    if (preFlight) {
      // The handler of the announced method; its consumes, produces and
      // headers conditions match any pre-flight, as in Spring.
      return _PreFlightLookup(byMethod.first.$1);
    }
    // A request without a Content-Type is matched as
    // application/octet-stream, as in Spring.
    final contentType =
        request.contentType ??
        (request.headers.contentType == null
            ? MediaType.parse(MediaType.applicationOctetStream)
            : null);
    final byConsumes = [
      for (final match in byMethod)
        if (match.$1.consumes.isEmpty ||
            (contentType != null &&
                match.$1.consumes.any((c) => c.includes(contentType))))
          match,
    ];
    if (byConsumes.isEmpty) {
      throw HttpMediaTypeNotSupportedException(
        request.headers.contentType ?? MediaType.applicationOctetStream,
        {for (final (m, _) in byMethod) ...m.consumes.map((c) => '$c')}
            .toList(),
      );
    }
    final accept = _accept(request);
    final byProduces = [
      for (final match in byConsumes)
        if (match.$1.produces.isEmpty ||
            match.$1.produces.any(
              (p) => accept.any((a) => a.isCompatibleWith(p)),
            ))
          match,
    ];
    if (byProduces.isEmpty) {
      throw HttpMediaTypeNotAcceptableException(
        {for (final (m, _) in byConsumes) ...m.produces.map((p) => '$p')}
            .toList(),
      );
    }
    final byHeaders = [
      for (final match in byProduces)
        if (match.$1.headerConditions.every((c) => c.matches(request))) match,
    ];
    if (byHeaders.isEmpty) {
      throw ResponseStatusException(
        HttpStatus.badRequest,
        'Unsatisfied header conditions',
      );
    }
    byHeaders.sort((a, b) => a.$1.compareTo(b.$1));
    final (mapping, match) = byHeaders.first;
    return _HandlerLookup(mapping, match.variables);
  }

  /// The CORS rules the router applies to [request]: those of the handler
  /// the router would call, chosen as for the request itself (path,
  /// method, `consumes`, `produces` and `headers`): the global rules
  /// combined with its `@CrossOrigin`, or the configuration of the
  /// [corsConfigurationSource] bean alone where it has one. For a
  /// pre-flight, the handler of the method it announces. For a path no
  /// handler maps, or a request the router refuses (405, 415, 406, 400),
  /// and an `OPTIONS` request the router answers itself, the global rules
  /// alone; `null` when there are none.
  ///
  /// It lets a filter that runs before the router check requests as the
  /// router would: the router then leaves a request the filter answered
  /// (with an `Access-Control-Allow-Origin`) as it is. The security
  /// starter's CORS filter uses `DispatcherHandler.corsConfigurationFor`
  /// instead, which also knows the requests another handler mapping
  /// takes (the WebSocket handshakes). Spring uses its
  /// `HandlerMappingIntrospector` for the same purpose.
  CorsConfiguration? corsConfigurationFor(ServerHttpRequest request) {
    if (!_initialized) {
      initialize();
    }
    final _Lookup? lookup;
    try {
      lookup = _lookup(request);
    } on ErrorResponseException {
      // A request the router refuses: as for a path no handler maps
      // (Spring's introspector goes on to the next handler mapping).
      return _globalCors(request);
    }
    return switch (lookup) {
      _HandlerLookup(:final mapping) ||
      _PreFlightLookup(:final mapping?) => _corsConfig(mapping, request),
      _ => _globalCors(request),
    };
  }

  // DispatcherHandler.corsConfigurationFor, as Spring's
  // HandlerMappingIntrospector.getCorsConfiguration: the first of
  // [mappings] (the dispatcher's, in its order) that takes [request]
  // decides. This router: its handler's rules. Another mapping (the
  // WebSocket endpoints'): the bean's rules where it has some, else none;
  // neither the global rules nor @CrossOrigin are for its requests (as
  // Spring's WebSocketHandlerMapping has no global CORS configuration),
  // and the dispatcher never brings them to this router. A mapping that
  // throws (this router's 405, 415, 406, 400) is passed over, as the
  // introspector ignores the exception. No mapping: the global rules, as
  // for a path no handler maps.
  Future<CorsConfiguration?> _dispatcherCors(
    List<HandlerMapping> mappings,
    ServerHttpRequest request,
  ) async {
    if (!_initialized) {
      initialize();
    }
    for (final handlerMapping in mappings) {
      if (identical(handlerMapping, this)) {
        final _Lookup? lookup;
        try {
          lookup = _lookup(request);
        } on ErrorResponseException {
          continue;
        }
        switch (lookup) {
          case null:
            continue;
          case _HandlerLookup(:final mapping) ||
              _PreFlightLookup(:final mapping?):
            return _corsConfig(mapping, request);
          case _:
            return _globalCors(request);
        }
      }
      final HttpHandler? handler;
      try {
        handler = await handlerMapping.getHandler(request);
      } on Object {
        continue;
      }
      if (handler != null) {
        return corsConfigurationSource?.getCorsConfiguration(request);
      }
    }
    return _globalCors(request);
  }

  // The rules of [mapping]'s handler: the bean's alone where it has some,
  // else the global rules combined with the handler's @CrossOrigin. With
  // [validate], the latter are checked as Spring's AbstractHandlerMapping
  // checks them for every request (a StateError, so a 500, for "*" with
  // credentials or a private network).
  CorsConfiguration? _corsConfig(
    _Mapping mapping,
    ServerHttpRequest request, {
    bool validate = false,
  }) {
    if (corsConfigurationSource?.getCorsConfiguration(request)
        case final bean?) {
      return bean;
    }
    final global = corsSource?.getCorsConfiguration(request);
    final local = mapping.cors;
    final config = global == null
        ? local
        : local == null
        ? global
        : global.combine(local);
    if (validate) {
      config
        ?..validateAllowCredentials()
        ..validateAllowPrivateNetwork();
    }
    return config;
  }

  // The rules for a request no handler of the router takes: the bean's
  // where it has some, else the global rules.
  CorsConfiguration? _globalCors(
    ServerHttpRequest request, {
    bool validate = false,
  }) {
    if (corsConfigurationSource?.getCorsConfiguration(request)
        case final bean?) {
      return bean;
    }
    final config = corsSource?.getCorsConfiguration(request);
    if (validate) {
      config
        ?..validateAllowCredentials()
        ..validateAllowPrivateNetwork();
    }
    return config;
  }

  static List<MediaType> _accept(ServerHttpRequest request) {
    try {
      final types = MediaType.parseMediaTypes(
        request.headers.getAll(HttpHeaders.acceptHeader).join(','),
      );
      return types.isEmpty ? [MediaType.parse(MediaType.all)] : types;
    } on InvalidMediaTypeException {
      return [MediaType.parse(MediaType.all)];
    }
  }
}

// A @ControllerAdvice bean: its exception handlers and the controllers
// it applies to (Spring's ControllerAdviceBean and HandlerTypePredicate).
final class _Advice {
  _Advice(this.name, this.annotation, this.handlers);

  final String name;
  final ControllerAdvice? annotation;
  final List<ExceptionHandlerMethod> handlers;

  bool appliesTo(BeanDefinition<Object>? controller) {
    final advice = annotation;
    if (advice == null ||
        (advice.basePackages.isEmpty &&
            advice.assignableTypes.isEmpty &&
            advice.annotations.isEmpty)) {
      return true;
    }
    if (controller == null) {
      return false;
    }
    final source = controller.source ?? '';
    return advice.basePackages.any(source.startsWith) ||
        advice.assignableTypes.any(controller.types.contains) ||
        controller.annotations.any(
          (a) => advice.annotations.contains(a.runtimeType),
        );
  }
}

/// `DispatcherHandler.corsConfigurationFor`: the CORS rules of [request]
/// as the dispatcher asking [mappings] in order, among them [router],
/// routes it. Internal: the library hides it.
Future<CorsConfiguration?> dispatcherCorsConfiguration(
  List<HandlerMapping> mappings,
  RequestMappingHandlerMapping router,
  ServerHttpRequest request,
) => router._dispatcherCors(mappings, request);

/// The value a parameter binder returns for an optional parameter that
/// the request does not fill: a named parameter is then left out of the
/// call, so its Dart default applies. Internal: the library hides it.
const absent = _Absent();

final class _Absent {
  const _Absent();
}

final class _HeaderCondition {
  _HeaderCondition(this.name, this.value, {required this.negated});

  static _HeaderCondition? parse(
    String text,
    HandlerMethod handler,
    List<String> problems,
  ) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final notEquals = trimmed.indexOf('!=');
    if (notEquals > 0) {
      return _HeaderCondition(
        trimmed.substring(0, notEquals).trim(),
        trimmed.substring(notEquals + 2).trim(),
        negated: true,
      );
    }
    final equals = trimmed.indexOf('=');
    if (equals > 0) {
      return _HeaderCondition(
        trimmed.substring(0, equals).trim(),
        trimmed.substring(equals + 1).trim(),
        negated: false,
      );
    }
    if (trimmed.startsWith('!')) {
      return _HeaderCondition(trimmed.substring(1).trim(), null, negated: true);
    }
    return _HeaderCondition(trimmed, null, negated: false);
  }

  final String name;
  final String? value;
  final bool negated;

  bool matches(ServerHttpRequest request) {
    final actual = request.headers[name];
    final present = value == null ? actual != null : actual == value;
    return negated ? !present : present;
  }

  @override
  String toString() =>
      '${negated && value == null ? '!' : ''}$name'
      '${value == null ? '' : '${negated ? '!=' : '='}$value'}';
}

final class _Binder {
  _Binder(this.parameter, this.resolve, {this.isBody = false});

  final MethodParameter parameter;
  final FutureOr<Object?> Function(_Call call) resolve;
  final bool isBody;
}

final class _Call {
  _Call(this.request, this.response, this.variables, {this.error});

  final ServerHttpRequest request;
  final ServerHttpResponse response;
  final Map<String, String> variables;
  final Object? error;
}

Future<Object?> _invokeWith(
  HandlerMethod handler,
  List<_Binder> binders,
  _Call call,
) async {
  final values = List<Object?>.filled(handler.parameters.length, null);
  for (final binder in binders) {
    var value = binder.resolve(call);
    if (value is Future) {
      value = await value;
    }
    values[binder.parameter.index] = value;
  }
  final positional = <Object?>[];
  final named = <Symbol, Object?>{};
  for (final parameter in handler.parameters) {
    final value = values[parameter.index];
    final symbol = parameter.parameter.symbol;
    if (symbol != null) {
      if (!identical(value, absent)) {
        named[symbol] = value;
      }
    } else {
      positional.add(identical(value, absent) ? null : value);
    }
  }
  // Optional positional parameters left out keep their default values.
  for (
    var i = handler.parameters.where((p) => !p.parameter.isNamed).length - 1;
    i >= 0;
    i--
  ) {
    if (identical(values[i], absent) &&
        !handler.parameters[i].parameter.isRequired) {
      positional.removeLast();
    } else {
      break;
    }
  }
  var result = handler.method.invoke(handler.resolveBean(), positional, named);
  if (result is Future) {
    result = await result;
  }
  return result;
}

/// An `@ExceptionHandler` method of a controller or of a
/// `@ControllerAdvice` bean, ready to be called for an error.
///
/// The router builds one per such method at startup and picks among them
/// with [RequestMappingHandlerMapping.exceptionHandlerFor]. Applications
/// write the annotated methods and never create this.
final class ExceptionHandlerMethod {
  ExceptionHandlerMethod._(
    this.handler,
    this.declaredTypes,
    this.exceptionParameter,
    this._binders,
  );

  /// The annotated method and the bean it belongs to.
  final HandlerMethod handler;

  /// The types listed in `@ExceptionHandler([...])`, matched by exact
  /// runtime type; empty when the exception parameter's type decides.
  final List<Type> declaredTypes;

  /// The parameter that receives the exception, or `null` when the method
  /// does not take it: the first parameter that is not a
  /// `ServerHttpRequest`, `ServerHttpResponse` or `HttpHeaders`.
  final MethodParameter? exceptionParameter;

  final List<_Binder> _binders;

  bool _handles(Object error) {
    final parameter = exceptionParameter;
    if (declaredTypes.isNotEmpty) {
      return declaredTypes.contains(error.runtimeType) &&
          (parameter == null || parameter.type.isInstance(error));
    }
    return parameter != null && parameter.type.isInstance(error);
  }

  Future<Object?> _invoke(_Call call) => _invokeWith(handler, _binders, call);

  // The handler for the most specific type: an exact type of
  // `@ExceptionHandler(value)` first, then the parameter type that is a
  // subtype of the others.
  static ExceptionHandlerMethod? _best(
    List<ExceptionHandlerMethod> handlers,
    Object error,
  ) {
    final candidates = handlers.where((h) => h._handles(error)).toList();
    if (candidates.isEmpty) {
      return null;
    }
    final exact = candidates
        .where((h) => h.declaredTypes.contains(error.runtimeType))
        .firstOrNull;
    if (exact != null) {
      return exact;
    }
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      final a = candidate.exceptionParameter?.type;
      final b = best.exceptionParameter?.type;
      if (a != null && b != null && _isSubtype(a, b) && !_isSubtype(b, a)) {
        best = candidate;
      }
    }
    return best;
  }

  static bool _isSubtype(TypeInfo<Object?> a, TypeInfo<Object?> b) =>
      a.capture(<A>() => b.capture(<B>() => <A>[] is List<B>));
}

final class _Mapping implements Comparable<_Mapping> {
  _Mapping(
    this.owner,
    this.handler,
    this.pattern,
    this.method,
    this.produces,
    this.consumes,
    this.headerConditions,
    this.binders,
    this.cors,
  );

  final RequestMappingHandlerMapping owner;
  final HandlerMethod handler;
  final PathPattern pattern;
  final HttpMethod method;
  final List<MediaType> produces;
  final List<MediaType> consumes;
  final List<_HeaderCondition> headerConditions;
  final List<_Binder> binders;
  final CorsConfiguration? cors;
  List<ExceptionHandlerMethod> localExceptionHandlers = const [];

  // What must be unique: method, pattern and conditions.
  Iterable<String> get keys => [
    // One entry, written on several lines to stay within 80 columns.
    // ignore: no_adjacent_strings_in_list
    '${method.value} ${pattern.pattern}'
        '${consumes.isEmpty ? '' : ' consumes $consumes'}'
        '${produces.isEmpty ? '' : ' produces $produces'}'
        '${headerConditions.isEmpty ? '' : ' headers $headerConditions'}',
  ];

  @override
  int compareTo(_Mapping other) {
    final byPattern = pattern.compareTo(other.pattern);
    if (byPattern != 0) {
      return byPattern;
    }
    // More conditions first (more specific).
    final conditions =
        (other.headerConditions.length +
                other.consumes.length +
                other.produces.length)
            .compareTo(
              headerConditions.length + consumes.length + produces.length,
            );
    return conditions;
  }

  @override
  String toString() =>
      '${method.value} ${pattern.pattern} -> ${handler.description}';
}

// The router's choice for a request (_lookup).
sealed class _Lookup {
  const _Lookup();
}

// A request to a handler.
final class _HandlerLookup extends _Lookup {
  const _HandlerLookup(this.mapping, this.variables);

  final _Mapping mapping;
  final Map<String, String> variables;
}

// A pre-flight, with the handler of the method it announces (`null`: no
// handler of the path maps it).
final class _PreFlightLookup extends _Lookup {
  const _PreFlightLookup(this.mapping);

  final _Mapping? mapping;
}

// An OPTIONS request (not a pre-flight) to a path without an OPTIONS
// handler: the router answers it with the methods [allowed].
final class _OptionsLookup extends _Lookup {
  const _OptionsLookup(this.allowed);

  final Set<HttpMethod> allowed;
}

// Answers an OPTIONS request with `Allow`, as Spring's HttpOptionsHandler.
// The CORS rules [configurationFor] finds (the global ones) apply first,
// as Spring's CorsInterceptor applies them to that handler: a CORS request
// is checked, with its method, OPTIONS, and the answer gets Vary.
final class _OptionsHandler implements HttpHandler {
  _OptionsHandler(this.allowed, this.configurationFor);

  final Set<HttpMethod> allowed;
  final CorsConfiguration? Function(ServerHttpRequest request) configurationFor;

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final config = configurationFor(request);
    if (config != null &&
        !processCors(config, request, response, preFlight: false)) {
      await response.send(403, 'Invalid CORS request');
      return;
    }
    response
      ..statusCode = 200
      ..headers.set(
        HttpHeaders.allowHeader,
        {...allowed, HttpMethod.options}.map((m) => m.value).join(', '),
      );
    await response.close();
  }
}

// Answers a pre-flight from the CORS rules [configurationFor] finds, as
// Spring's PreFlightHandler: a 403 when they refuse it, else a 200 with
// the CORS headers. Without rules, a 200 with none (and no Vary), as
// Spring's DefaultCorsProcessor answers a null configuration: the browser
// then blocks the request it announced.
final class _PreFlightHandler implements HttpHandler {
  _PreFlightHandler(this.configurationFor);

  final CorsConfiguration? Function(ServerHttpRequest request) configurationFor;

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final config = configurationFor(request);
    if (config != null &&
        !processCors(config, request, response, preFlight: true)) {
      await response.send(403, 'Invalid CORS request');
      return;
    }
    response.statusCode = 200;
    await response.close();
  }
}

final class _Execution implements HttpHandler {
  _Execution(this.mapping, this.variables);

  final _Mapping mapping;
  final Map<String, String> variables;

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final owner = mapping.owner;
    final handler = mapping.handler;
    // Every request to a handler with CORS rules, as Spring's
    // CorsInterceptor: a CORS request is checked (its origin and its
    // method), and every answer gets Vary. A request a filter answered
    // already (Access-Control-Allow-Origin set) is left as it is.
    final cors = owner._corsConfig(mapping, request, validate: true);
    if (cors != null &&
        !processCors(cors, request, response, preFlight: false)) {
      await response.send(403, 'Invalid CORS request');
      return;
    }
    final target = request.method == HttpMethod.head
        ? HeadResponse(response)
        : response;
    request.attributes[bestMatchingHandlerAttribute] = handler;
    request.attributes[uriTemplateVariablesAttribute] = variables;
    final interceptors = [
      for (final registration in owner.interceptors)
        if (registration.appliesTo(request.path)) registration.interceptor,
    ];
    var preHandled = 0;
    Object? failure;
    try {
      for (final interceptor in interceptors) {
        if (!await interceptor.preHandle(request, target, handler)) {
          return;
        }
        preHandled++;
      }
      final call = _Call(request, target, variables);
      final result = await _invokeWith(handler, mapping.binders, call);
      for (final interceptor in interceptors.reversed) {
        await interceptor.postHandle(request, target, handler, result);
      }
      await owner.writer.writeResult(
        result,
        request,
        target,
        handler: handler,
        produces: mapping.produces,
      );
    } on Object catch (error) {
      failure = error;
      if (!await owner.handleException(
        error,
        request,
        target,
        handler: handler,
      )) {
        rethrow;
      }
    } finally {
      await owner.multipartResolver.cleanup(request);
      for (final interceptor
          in interceptors.take(preHandled).toList().reversed) {
        try {
          await interceptor.afterCompletion(request, target, handler, failure);
        } on Object catch (error, stackTrace) {
          _log.warning(
            'HandlerInterceptor.afterCompletion threw',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
  }
}

/// The name of the request attribute that holds the [HandlerMethod]
/// chosen for the request, once the router has found it. A filter that
/// runs after the handler can read it.
const bestMatchingHandlerAttribute = 'spring.web.bestMatchingHandler';

/// The name of the request attribute that holds the path variables of
/// the matched pattern, as a `Map<String, String>` (`{'isbn': '978-0'}`).
const uriTemplateVariablesAttribute = 'spring.web.uriTemplateVariables';
