import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_endpoint.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.websocket.server');

// A client's text, quoted and cut for a log line.
String _quoted(String? value) => LogFormatUtils.formatValue(value);

/// The bean that routes incoming WebSocket handshakes to the right
/// handler: the `@WebSocketEndpoint` beans and the [WebSocketHandler]s of
/// the [WebSocketConfigurer] beans.
///
/// The starter registers it; applications do not call it. The web
/// starter's dispatcher asks it for each request (it is a
/// `HandlerMapping`), after the filters, so a handshake is authenticated
/// like any request, and after the controllers. For a matching path it
/// checks the origin, picks the subprotocol, runs the handshake
/// interceptors, accepts the connection and registers the session in the
/// [WebSocketSessionRegistry].
///
/// Every endpoint is checked at startup: two handlers on one path, an
/// `@PathVariable` that is not in the path or of a type the
/// `ConversionService` cannot make from a String, a parameter of no known
/// kind,
/// several methods with the same annotation, an endpoint without any of
/// `@OnOpen`, `@OnMessage` and `@OnClose`.
///
/// Spring (Java): `WebSocketHandlerMapping`.
final class WebSocketHandlerMapping
    implements HandlerMapping, Ordered, SmartInitializingSingleton {
  /// The mapping of the endpoints found in [beanFactory] and the handlers
  /// of [configurers].
  WebSocketHandlerMapping({
    required this.beanFactory,
    required this.mapper,
    required this.sessions,
    this.configurers = const [],
  });

  /// Where the `@WebSocketEndpoint` beans are found and taken from.
  final ListableBeanFactory beanFactory;

  /// Reads and writes the JSON messages of the endpoints.
  final ObjectMapper mapper;

  /// Where each accepted session is registered until it closes.
  final WebSocketSessionRegistry sessions;

  /// The beans that register Spring-style handlers.
  final List<WebSocketConfigurer> configurers;

  final _routes = <_Route>[];
  var _initialized = false;

  /// 1: asked after the controllers' mapping (order 0), as in Spring.
  @override
  int get order => 1;

  /// The path patterns of every endpoint and handler, most specific
  /// first; empty before [initialize].
  List<String> get paths => [
    for (final route in _routes) route.pattern.pattern,
  ];

  @override
  void afterSingletonsInstantiated() => initialize();

  /// Finds the handlers and endpoints and checks them; throws a
  /// [StateError] listing every problem. Runs once, when the singletons are
  /// ready or at the first request; later calls do nothing.
  void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    final problems = <String>[];
    final registry = WebSocketHandlerRegistry();
    for (final configurer in configurers) {
      configurer.registerWebSocketHandlers(registry);
    }
    for (final registration in registry.registrations) {
      for (final path in registration.paths) {
        final pattern = _parse(
          path,
          '${registration.handler.runtimeType}',
          problems,
        );
        if (pattern == null) {
          continue;
        }
        _routes.add(
          _Route(
            pattern,
            path,
            registration.handler,
            allowedOrigins: registration.allowedOrigins,
            allowedOriginPatterns: registration.allowedOriginPatterns,
            protocols: registration.protocols,
            interceptors: registration.interceptors,
          ),
        );
      }
    }
    final definitions = beanFactory as BeanDefinitionRegistry;
    for (final name
        in beanFactory.getBeanNamesForAnnotation<WebSocketEndpoint>()) {
      if (!definitions.containsBeanDefinition(name)) {
        continue;
      }
      final definition = definitions.getBeanDefinition(name);
      final endpoint = definition.annotations
          .whereType<WebSocketEndpoint>()
          .first;
      final typeName = '${definition.beanType}';
      final pattern = _parse(endpoint.path, typeName, problems);
      if (pattern == null) {
        continue;
      }
      final adapter = _EndpointAdapter.compile(
        this,
        name,
        typeName,
        pattern,
        definition.annotatedMethods,
        problems,
      );
      if (adapter != null) {
        _routes.add(
          _Route(
            pattern,
            endpoint.path,
            adapter,
            allowedOrigins: endpoint.allowedOrigins,
            allowedOriginPatterns: endpoint.allowedOriginPatterns,
            protocols: endpoint.protocols,
            interceptors: const [],
          ),
        );
      }
    }
    final seen = <String>{};
    for (final route in _routes) {
      if (!seen.add(route.pattern.pattern)) {
        problems.add('Two WebSocket handlers for ${route.pattern.pattern}');
      }
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid WebSocket endpoints:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
      );
    }
    _routes.sort((a, b) => a.pattern.compareTo(b.pattern));
  }

  static PathPattern? _parse(String path, String owner, List<String> problems) {
    try {
      return PathPattern.parse(path);
    } on FormatException catch (error) {
      problems.add('$owner: ${error.message} in "$path"');
      return null;
    }
  }

  @override
  HttpHandler? getHandler(ServerHttpRequest request) {
    if (!_initialized) {
      initialize();
    }
    for (final route in _routes) {
      final match = route.pattern.match(request.path);
      if (match != null) {
        return FunctionHttpHandler(
          (request, response) =>
              _handshake(route, match.variables, request, response),
        );
      }
    }
    return null;
  }

  Future<void> _handshake(
    _Route route,
    Map<String, String> variables,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (!request.isWebSocketUpgrade) {
      _log.debug(
        () => 'Handshake refused for ${route.pattern.pattern}: not an upgrade',
      );
      return await response.send(400, 'Can "Upgrade" only to "WebSocket".');
    }
    if (!route.allowsOrigin(request)) {
      _log.debug(
        () =>
            'Handshake from origin '
            '${_quoted(request.headers[HttpHeaders.originHeader])} '
            'refused for ${route.pattern.pattern}',
      );
      return await response.send(403, 'Origin not allowed');
    }
    final offered = [
      for (final value in request.headers.getAll('Sec-WebSocket-Protocol'))
        for (final protocol in value.split(','))
          if (protocol.trim().isNotEmpty) protocol.trim(),
    ];
    final protocol = offered
        .where((p) => route.protocols.contains(p))
        .firstOrNull;
    if (route.handler case final _EndpointAdapter adapter) {
      // Like a controller's path variable that does not convert: 400.
      if (adapter.checkVariables(variables) case final problem?) {
        _log.debug(
          () =>
              'Handshake refused for ${route.pattern.pattern}: a path '
              'variable does not convert',
        );
        return await response.send(400, problem);
      }
    }
    final attributes = <String, Object?>{};
    for (final interceptor in route.interceptors) {
      if (!await interceptor.beforeHandshake(request, response, attributes)) {
        _log.debug(
          () =>
              'Handshake refused for ${route.pattern.pattern} by '
              '${interceptor.runtimeType}',
        );
        if (!response.isCommitted) {
          await response.send(403, 'Handshake refused');
        }
        return;
      }
    }
    final WebSocketSession connection;
    try {
      connection = await request.upgradeToWebSocket(protocol: protocol);
    } on Object catch (error) {
      for (final interceptor in route.interceptors) {
        await interceptor.afterHandshake(request, error);
      }
      rethrow;
    }
    for (final interceptor in route.interceptors) {
      await interceptor.afterHandshake(request, null);
    }
    final session = DefaultServerWebSocketSession(
      connection,
      request,
      mapper: mapper,
      pathVariables: variables,
      attributes: attributes,
    );
    sessions.register(route.path, session);
    _log.debug(
      () =>
          'Handshake accepted for ${route.pattern.pattern}'
          '${protocol == null ? '' : ' (subprotocol ${_quoted(protocol)})'}',
    );
    unawaited(
      _run(route, session).catchError((Object error, StackTrace stackTrace) {
        _log.error(
          'WebSocket session ${session.id} failed',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  // The life of one connection. Nothing thrown here reaches the zone of
  // the server (an uncaught error would end the process): the handler's
  // errors go to its handleTransportError, anything else is logged, and
  // the session always leaves the registry, with afterConnectionClosed
  // called once when afterConnectionEstablished was.
  Future<void> _run(_Route route, ServerWebSocketSession session) async {
    final handler = route.handler;
    Future<void> guarded(FutureOr<void> Function() body) async {
      try {
        await body();
      } on Object catch (error, stackTrace) {
        await _failed(handler, session, error, stackTrace);
      }
    }

    var established = false;
    try {
      // One message after the other, in order. While a message is handled
      // the connection is not read (the web starter's socket stops
      // reading from the network), so a client sending faster than the
      // handler works waits instead of filling the server's memory.
      final closed = Completer<void>();
      late final StreamSubscription<Object> subscription;
      void handle(Future<void> Function() work) {
        subscription.pause();
        unawaited(work().whenComplete(subscription.resume));
      }

      // Listened to before afterConnectionEstablished, paused: its
      // messages wait (unread) until it is done, and a session it closes
      // (refusing the client, or after an error) still ends the stream
      // here, with the close status.
      subscription = session.messages.listen(
        (message) {
          _log.trace(
            () => message is String
                ? 'Received a text message of ${message.length} characters'
                : 'Received a binary message of '
                      '${(message as List<int>).length} bytes',
          );
          handle(() => guarded(() => handler.handleMessage(session, message)));
        },
        onError: (Object error, StackTrace stackTrace) =>
            handle(() => _failed(handler, session, error, stackTrace)),
        // Delivered after the last message has been handled.
        onDone: closed.complete,
        cancelOnError: false,
      )..pause();
      established = true;
      _log.debug(
        () =>
            'Opened WebSocket session ${session.id} at '
            '${route.pattern.pattern}',
      );
      await guarded(() => handler.afterConnectionEstablished(session));
      subscription.resume();
      await closed.future;
      await subscription.cancel(); // done already
    } on Object catch (error, stackTrace) {
      _log.error(
        'WebSocket session ${session.id} failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (session.isOpen) {
        unawaited(
          session.close(CloseStatus.serverError).catchError((Object _) {}),
        );
      }
    } finally {
      sessions.unregister(route.path, session);
      if (established) {
        _log.debug(
          () =>
              'Closed WebSocket session ${session.id} with code '
              '${(session.closeStatus ?? CloseStatus.noStatusCode).code}',
        );
        await guarded(
          () => handler.afterConnectionClosed(
            session,
            session.closeStatus ?? CloseStatus.noStatusCode,
          ),
        );
      }
    }
  }

  Future<void> _failed(
    WebSocketHandler handler,
    ServerWebSocketSession session,
    Object error,
    StackTrace stackTrace,
  ) async {
    try {
      await handler.handleTransportError(session, error);
    } on Object catch (handlerError, handlerStack) {
      _log.warning(
        'WebSocket session ${session.id}: the error handler failed',
        error: handlerError,
        stackTrace: handlerStack,
      );
    }
  }
}

final class _Route {
  _Route(
    this.pattern,
    this.path,
    this.handler, {
    required this.allowedOrigins,
    required this.allowedOriginPatterns,
    required this.protocols,
    required this.interceptors,
  });

  final PathPattern pattern;
  final String path;
  final WebSocketHandler handler;
  final List<String> allowedOrigins;
  final List<String> allowedOriginPatterns;
  final List<String> protocols;
  final List<HandshakeInterceptor> interceptors;

  // Checked as Spring's CorsConfiguration checks them, as the web
  // starter's CORS does.
  late final _origins = AllowedOrigins(
    allowedOrigins: allowedOrigins,
    allowedOriginPatterns: allowedOriginPatterns,
  );

  // Spring's OriginHandshakeInterceptor: no Origin (not a browser) or the
  // server's own origin (WebUtils.isSameOrigin) is fine, others must be
  // allowed (CorsConfiguration.checkOrigin).
  bool allowsOrigin(ServerHttpRequest request) {
    final origin = request.headers[HttpHeaders.originHeader];
    return origin == null ||
        _isSameOrigin(origin, request) ||
        _origins.checkOrigin(origin) != null;
  }

  // The same scheme, host and port (the scheme's default when there is
  // none) as the request. A handshake is an HTTP request: its scheme is
  // http or https.
  static bool _isSameOrigin(String origin, ServerHttpRequest request) {
    final parsed = Uri.tryParse(origin);
    final scheme = request.isSecure ? 'https' : 'http';
    final own = request.uri;
    return parsed != null &&
        parsed.scheme == scheme &&
        parsed.host == own.host &&
        _port(scheme, parsed) == _port(scheme, own);
  }

  static int _port(String scheme, Uri uri) =>
      uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
}

typedef _Binder = FutureOr<Object?> Function(_Call call);

typedef _Convert = Object? Function(String text);

final class _Call {
  _Call(this.session, {this.message, this.status, this.error});

  final ServerWebSocketSession session;
  final Object? message;
  final CloseStatus? status;
  final Object? error;
}

final class _Handler {
  _Handler(this.method, this.binders);

  final BeanMethod<Object> method;
  final List<(BeanParameter, _Binder)> binders;
}

/// Calls the annotated methods of a `@WebSocketEndpoint` bean, with their
/// parameters bound, as a [WebSocketHandler].
final class _EndpointAdapter implements WebSocketHandler {
  _EndpointAdapter(
    this.owner,
    this.beanName,
    this.onOpen,
    this.onMessage,
    this.onClose,
    this.onError,
    this.variables,
  );

  static _EndpointAdapter? compile(
    WebSocketHandlerMapping owner,
    String beanName,
    String typeName,
    PathPattern pattern,
    List<BeanMethod<Object>> methods,
    List<String> problems,
  ) {
    final before = problems.length;
    // The path variables that are not Strings: converted, and checked at
    // the handshake.
    final variables = <String, (_Convert, TypeInfo<Object?>)>{};
    _Handler? find<A>(String kind) {
      final found = [
        for (final method in methods)
          if (method.annotations.whereType<A>().isNotEmpty) method,
      ];
      if (found.length > 1) {
        problems.add('$typeName has several @$kind methods');
      }
      final method = found.firstOrNull;
      if (method == null) {
        return null;
      }
      final binders = <(BeanParameter, _Binder)>[];
      var payload = false;
      for (final parameter in method.parameters) {
        final where = '$typeName.${method.name}(${parameter.name})';
        final type = parameter.type;
        final variable = parameter.annotations
            .whereType<PathVariable>()
            .firstOrNull;
        if (variable != null) {
          final name = variable.name ?? parameter.name;
          if (!pattern.variableNames.contains(name)) {
            problems.add('$where: {$name} is not in "${pattern.pattern}"');
          }
          final convert = owner._pathVariable(type, where, problems);
          if (convert != null) {
            variables[name] = (convert, type);
          }
          binders.add((
            parameter,
            (call) => switch (call.session.pathVariables[name]) {
              final text? when convert != null => convert(text),
              final text => text,
            },
          ));
        } else if (type.type == ServerWebSocketSession ||
            type.type == WebSocketSession) {
          binders.add((parameter, (call) => call.session));
        } else if (type.type == Principal) {
          binders.add((parameter, (call) => call.session.principal));
        } else if (type.type == CloseStatus && kind == 'OnClose') {
          binders.add((parameter, (call) => call.status));
        } else if (kind == 'OnMessage' && !payload) {
          payload = true;
          binders.add((
            parameter,
            (call) => owner._decode(call.message!, type, where),
          ));
        } else if (kind == 'OnError' && !payload) {
          payload = true;
          binders.add((parameter, (call) => call.error));
        } else {
          problems.add(
            '$where: a parameter of @$kind must be the session, an '
            '@PathVariable, the Principal'
            '${switch (kind) {
              'OnMessage' => ' or the message',
              'OnClose' => ' or the CloseStatus',
              'OnError' => ' or the error',
              _ => '',
            }}',
          );
        }
      }
      return _Handler(method, binders);
    }

    final adapter = _EndpointAdapter(
      owner,
      beanName,
      find<OnOpen>('OnOpen'),
      find<OnMessage>('OnMessage'),
      find<OnClose>('OnClose'),
      find<OnError>('OnError'),
      variables,
    );
    if (adapter.onOpen == null &&
        adapter.onMessage == null &&
        adapter.onClose == null) {
      problems.add(
        '$typeName (@WebSocketEndpoint) has no @OnOpen, @OnMessage or '
        '@OnClose method',
      );
    }
    return problems.length == before ? adapter : null;
  }

  final WebSocketHandlerMapping owner;
  final String beanName;
  final _Handler? onOpen;
  final _Handler? onMessage;
  final _Handler? onClose;
  final _Handler? onError;
  final Map<String, (_Convert, TypeInfo<Object?>)> variables;

  /// Why the path [values] of a handshake do not fit the parameters
  /// (`{id}` is not a number for an `int`), or `null` when they do.
  String? checkVariables(Map<String, String> values) {
    for (final MapEntry(key: name, value: (convert, type))
        in variables.entries) {
      final text = values[name];
      if (text == null) {
        continue;
      }
      try {
        convert(text);
      } on Object catch (_) {
        return 'The path variable {$name} is not a valid $type';
      }
    }
    return null;
  }

  Future<Object?> _invoke(_Handler handler, _Call call) async {
    final positional = <Object?>[];
    final named = <Symbol, Object?>{};
    for (final (parameter, binder) in handler.binders) {
      var value = binder(call);
      if (value is Future) {
        value = await value;
      }
      if (parameter.symbol case final symbol?) {
        named[symbol] = value;
      } else {
        positional.add(value);
      }
    }
    final bean = owner.beanFactory.getBeanByName(beanName);
    final target = handler.method.appliesTo(bean)
        ? bean
        : AopUtils.getTarget(bean);
    var result = handler.method.invoke(target, positional, named);
    if (result is Future) {
      result = await result;
    }
    return result;
  }

  @override
  Future<void> afterConnectionEstablished(
    ServerWebSocketSession session,
  ) async {
    if (onOpen case final handler?) {
      await _invoke(handler, _Call(session));
    }
  }

  @override
  Future<void> handleMessage(
    ServerWebSocketSession session,
    Object message,
  ) async {
    final handler = onMessage;
    if (handler == null) {
      return;
    }
    final reply = await _invoke(handler, _Call(session, message: message));
    if (reply == null || handler.method.isVoid || !session.isOpen) {
      return;
    }
    switch (reply) {
      case String() || Uint8List():
        session.sendMessage(reply);
      default:
        session.sendJson(reply);
    }
  }

  @override
  Future<void> handleTransportError(
    ServerWebSocketSession session,
    Object error,
  ) async {
    final handler = onError;
    if (handler == null) {
      _log.warning('WebSocket session ${session.id} failed', error: error);
      if (session.isOpen) {
        await session.close(CloseStatus.serverError);
      }
      return;
    }
    await _invoke(handler, _Call(session, error: error));
  }

  @override
  Future<void> afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) async {
    if (onClose case final handler?) {
      await _invoke(handler, _Call(session, status: status));
    }
  }
}

extension on WebSocketHandlerMapping {
  // The ConversionService of `@Value`, as controllers convert their path
  // variables: Boot's ApplicationConversionService in an application.
  ConversionService get _conversion => switch (beanFactory) {
    final ConfigurableBeanFactory factory => factory.conversionService,
    _ => DefaultConversionService.sharedInstance,
  };

  // How a path variable becomes the parameter's [type]: `null` for a
  // String (as it is); a problem when nothing converts a String to it.
  _Convert? _pathVariable(
    TypeInfo<Object?> type,
    String where,
    List<String> problems,
  ) {
    final target = type.type;
    if (target == String || target == Object || type is DynamicType) {
      return null;
    }
    if (type is EnumType<Enum>) {
      // Spring's StringToEnumConverterFactory: the constant's name.
      return (text) => type.values.firstWhere(
        (value) => value.name == text.trim(),
        orElse: () => throw FormatException('No ${type.type} named $text'),
      );
    }
    if (!_conversion.canConvertType<String>(target)) {
      problems.add(
        '$where: a @PathVariable must be a String or a type the '
        'ConversionService converts a String to (int, double, bool, an '
        'enum, ...), not $type',
      );
      return null;
    }
    return (text) =>
        _conversion.convertTo(text, target) ??
        (throw FormatException('Not a $type', text));
  }

  Object? _decode(Object message, TypeInfo<Object?> type, String where) {
    final base = type.capture(<T>() => _typeOf<T>());
    if (base == String) {
      return message is String ? message : utf8.decode(message as List<int>);
    }
    if (base == Uint8List || base == List<int>) {
      return message is String ? utf8.encode(message) : message;
    }
    if (base == Object || type is DynamicType) {
      return message;
    }
    final text = message is String
        ? message
        : utf8.decode(message as List<int>, allowMalformed: true);
    try {
      return mapper.treeToValue<Object?>(jsonDecode(text), type);
    } on Object catch (error) {
      throw FormatException('$where: cannot read the message as $type: $error');
    }
  }
}

Type _typeOf<T>() => T;
