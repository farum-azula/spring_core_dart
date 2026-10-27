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

/// Maps requests to the `@GetMapping`, `@PostMapping`, ... methods of
/// `@RestController` (and `@Controller`) beans, like Spring's
/// `RequestMappingHandlerMapping` with its `RequestMappingHandlerAdapter`.
///
/// Every mapping is checked at startup: a `{variable}` without a
/// `@PathVariable` parameter, a parameter without a role, two methods
/// mapping the same request — the application stops with the reasons.
final class RequestMappingHandlerMapping
    implements HandlerMapping, Ordered, SmartInitializingSingleton {
  /// The mapping of the controllers of [beanFactory].
  RequestMappingHandlerMapping({
    required this.beanFactory,
    required this.writer,
    required this.environment,
    this.argumentResolvers = const [],
    this.interceptors = const [],
    this.corsSource,
    this.validator,
    MultipartResolver? multipartResolver,
  }) : multipartResolver = multipartResolver ?? MultipartResolver();

  /// Where the controllers are found.
  final ListableBeanFactory beanFactory;

  /// Writes results and errors.
  final ResponseWriter writer;

  /// Resolves `${...}` in mapping paths.
  final PropertyResolver environment;

  /// Resolvers of `WebMvcConfigurer.addArgumentResolvers`, asked first.
  final List<HandlerMethodArgumentResolver> argumentResolvers;

  /// Interceptors of `WebMvcConfigurer.addInterceptors`.
  final List<InterceptorRegistration> interceptors;

  /// The global CORS configuration (a `CorsConfigurationSource` bean and
  /// `WebMvcConfigurer.addCorsMappings`).
  final CorsConfigurationSource? corsSource;

  /// Validates `@Valid` arguments.
  final Validator? validator;

  /// Reads `multipart/form-data` requests (`@RequestPart`, files).
  final MultipartResolver multipartResolver;

  final _mappings = <_Mapping>[];
  final _adviceHandlers = <ExceptionHandlerMethod>[];
  var _initialized = false;

  @override
  int get order => 0;

  /// The mappings, as `GET /api/books/{isbn} -> BookController.find`.
  List<String> get mappings => [
    for (final mapping in _mappings) mapping.toString(),
  ];

  /// Checks the controllers once every singleton exists, so an invalid
  /// controller fails the startup.
  @override
  void afterSingletonsInstantiated() => initialize();

  /// Finds the controllers and checks their mappings; throws a
  /// [StateError] listing every problem. Called once at startup.
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
    final advice = <(int, String)>[];
    for (final name in adviceNames) {
      if (!registry.containsBeanDefinition(name)) {
        continue;
      }
      final definition = registry.getBeanDefinition(name);
      advice.add((definition.order ?? Ordered.lowestPrecedence, name));
    }
    advice.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, name) in advice) {
      final definition = registry.getBeanDefinition(name);
      for (final method in definition.annotatedMethods) {
        if (method.annotations.whereType<ExceptionHandler>().isEmpty) {
          continue;
        }
        _adviceHandlers.add(
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
    if (problems.length != before) {
      return null;
    }
    final cors = _crossOrigin(handler);
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

  CorsConfiguration? _crossOrigin(HandlerMethod handler) {
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
            maxAge: annotation.maxAge == null
                ? null
                : Duration(seconds: annotation.maxAge!),
          );
    final combined = (of(onClass) ?? CorsConfiguration()).combine(of(onMethod));
    return combined.applyPermitDefaultValues();
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
    final optional = type.nullable || !parameter.parameter.isRequired;
    void requireOptional(String role) {
      if (!optional) {
        problems.add(
          '$name: the $role parameter ${parameter.name} is not required '
          '(required: false) but its type is not nullable and it has no '
          'default value',
        );
      }
    }

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
            return _absentOr(parameter, 'path variable', key, null, true);
          }
          return _convert([value], parameter, key);
        });
      case final RequestParam param:
        if (!param.required) {
          requireOptional('@RequestParam');
        }
        return _requestParam(
          param.name ?? parameter.name,
          param.required,
          param.defaultValue,
          parameter,
          problems,
        );
      case final RequestHeader header:
        if (!header.required) {
          requireOptional('@RequestHeader');
        }
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
            return _absentOr(
              parameter,
              'header',
              key,
              header.defaultValue,
              header.required,
            );
          }
          return _convert(values, parameter, key);
        });
      case final CookieValue cookie:
        final key = cookie.name ?? parameter.name;
        _checkConvertible(parameter, '@CookieValue', problems);
        return _Binder(parameter, (call) {
          final value = call.request.cookies[key];
          if (value == null) {
            return _absentOr(parameter, 'cookie', key, null, true);
          }
          return _convert([value], parameter, key);
        });
      case final RequestBody body:
        return _Binder(
          parameter,
          (call) => _readBody(call, parameter, required: body.required),
          isBody: true,
        );
      case final RequestPart part:
        if (!part.required) {
          requireOptional('@RequestPart');
        }
        final key = part.name ?? parameter.name;
        return _Binder(
          parameter,
          (call) => _requestPart(call, parameter, key, part.required),
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
      return _requestParam(parameter.name, true, null, parameter, problems);
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
    bool required,
    String? defaultValue,
    MethodParameter parameter,
    List<String> problems,
  ) {
    final type = parameter.type;
    if (_isFileType(type)) {
      return _Binder(
        parameter,
        (call) => _requestPart(call, parameter, key, required),
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
            return _absentOr(
              parameter,
              'parameter',
              key,
              defaultValue,
              required,
            );
          }
          return _convert(fields, parameter, key);
        });
      }
      if (multipartResolver.isMultipart(request)) {
        return multipartResolver.resolve(request).then((multipart) {
          final fields = multipart.fields[key];
          if (fields == null || fields.isEmpty) {
            return _absentOr(
              parameter,
              'parameter',
              key,
              defaultValue,
              required,
            );
          }
          return _convert(fields, parameter, key);
        });
      }
      return _absentOr(parameter, 'parameter', key, defaultValue, required);
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
    bool required,
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
    Object? missing() => _absentOr(parameter, 'part', key, null, required);
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
    final base = type.capture(<T>() => _base<T>());
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

  // A missing value: the default value, else absent (null, or the Dart
  // default of an optional parameter), else a 400.
  Object? _absentOr(
    MethodParameter parameter,
    String kind,
    String key,
    String? defaultValue,
    bool required,
  ) {
    if (defaultValue != null) {
      return _convert([defaultValue], parameter, key);
    }
    final optional = parameter.type.nullable || !parameter.parameter.isRequired;
    if (required && !optional) {
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
    ClassType() => _simpleTypes.contains(type.capture(<T>() => _base<T>())),
    _ => false,
  };

  static Type _base<T>() => T;

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
    final target = type.capture(<T>() => _base<T>());
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

  Future<Object?> _readBody(
    _Call call,
    MethodParameter parameter, {
    required bool required,
  }) async {
    final request = call.request;
    final type = parameter.type;
    final base = type.capture(<T>() => _base<T>());
    Object? value;
    if (type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>()) {
      return request.body;
    }
    final Uint8List bytes;
    try {
      bytes = await request.readBodyBytes();
    } on PayloadTooLargeException catch (error) {
      throw PayloadTooLargeErrorException(error.maxLength);
    }
    final optional =
        !required || type.nullable || !parameter.parameter.isRequired;
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
      final contentType = request.contentType;
      if (contentType != null &&
          contentType.subtype == 'x-www-form-urlencoded' &&
          type is MapType<Object?, Object?>) {
        final form = Uri.splitQueryString(_decodeText(bytes, request));
        value = _convertMap(
          {
            for (final entry in form.entries) entry.key: [entry.value],
          },
          type,
          parameter,
        );
      } else if (contentType != null && !_isJson(contentType)) {
        throw HttpMediaTypeNotSupportedException(
          request.headers.contentType,
          const [MediaType.applicationJson],
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

  /// The exception handler for [error] among the handlers of the
  /// controller of [handler] (if any), then of the `@ControllerAdvice`
  /// beans; `null` when none handles it.
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
    return ExceptionHandlerMethod._best(_adviceHandlers, error);
  }

  /// Answers [error] with an `@ExceptionHandler` method; `false` when none
  /// handles it.
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
      final allowed = {for (final (m, _) in matches) m.method};
      if (allowed.contains(HttpMethod.get)) {
        allowed.add(HttpMethod.head);
      }
      if (method == HttpMethod.options && !preFlight) {
        return FunctionHttpHandler((request, response) async {
          response
            ..statusCode = 200
            ..headers.set(
              HttpHeaders.allowHeader,
              {...allowed, HttpMethod.options}.map((m) => m.value).join(', '),
            );
          await response.close();
        });
      }
      throw HttpRequestMethodNotSupportedException(method, allowed);
    }
    if (preFlight) {
      final (mapping, _) = byMethod.first;
      return FunctionHttpHandler((request, response) async {
        final config = _corsConfig(mapping, request);
        if (config == null ||
            !processCors(config, request, response, preFlight: true)) {
          await response.send(403, 'Invalid CORS request');
          return;
        }
        response.statusCode = 200;
        await response.close();
      });
    }
    final contentType = request.contentType;
    final byConsumes = [
      for (final match in byMethod)
        if (match.$1.consumes.isEmpty ||
            (contentType != null &&
                match.$1.consumes.any((c) => c.includes(contentType))))
          match,
    ];
    if (byConsumes.isEmpty) {
      throw HttpMediaTypeNotSupportedException(
        request.headers.contentType,
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
    return _Execution(mapping, match.variables);
  }

  /// The CORS configuration the router applies to [request]: the global
  /// one combined with the `@CrossOrigin` of the handler the request (or,
  /// for a pre-flight, the request it announces) is mapped to. Like
  /// Spring's `HandlerMappingIntrospector` as a `CorsConfigurationSource`:
  /// a security filter in front answers pre-flights the way the router
  /// would.
  CorsConfiguration? corsConfigurationFor(ServerHttpRequest request) {
    if (!_initialized) {
      initialize();
    }
    var method = request.method;
    if (isPreFlightRequest(request)) {
      final requested =
          request.headers[HttpHeaders.accessControlRequestMethodHeader] ?? '';
      method =
          HttpMethod.values
              .where((m) => m.value == requested.trim())
              .firstOrNull ??
          HttpMethod.options;
    }
    final path = request.path;
    final candidates = [
      for (final mapping in _mappings)
        if ((mapping.method == method ||
                (method == HttpMethod.head &&
                    mapping.method == HttpMethod.get)) &&
            mapping.pattern.match(path) != null)
          mapping,
    ]..sort((a, b) => a.compareTo(b)); // the router's choice first
    return candidates.isEmpty
        ? corsSource?.getCorsConfiguration(request)
        : _corsConfig(candidates.first, request);
  }

  CorsConfiguration? _corsConfig(_Mapping mapping, ServerHttpRequest request) {
    final global = corsSource?.getCorsConfiguration(request);
    final local = mapping.cors;
    if (global == null) {
      return local;
    }
    return local == null ? global : global.combine(local);
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

/// Marks a missing optional argument: a named one is left out (its Dart
/// default applies).
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

/// An `@ExceptionHandler` method of a controller or a controller advice.
final class ExceptionHandlerMethod {
  ExceptionHandlerMethod._(
    this.handler,
    this.declaredTypes,
    this.exceptionParameter,
    this._binders,
  );

  /// The method.
  final HandlerMethod handler;

  /// The types of `@ExceptionHandler(value)`.
  final List<Type> declaredTypes;

  /// The parameter receiving the exception, if any.
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
    if (isCorsRequest(request)) {
      final config = owner._corsConfig(mapping, request);
      if (config != null &&
          !processCors(config, request, response, preFlight: false)) {
        await response.send(403, 'Invalid CORS request');
        return;
      }
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

/// The request attribute holding the [HandlerMethod] of the request.
const bestMatchingHandlerAttribute = 'spring.web.bestMatchingHandler';

/// The request attribute holding the path variables (`Map<String,
/// String>`).
const uriTemplateVariablesAttribute = 'spring.web.uriTemplateVariables';
