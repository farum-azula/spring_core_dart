import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_endpoint.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.websocket.server');

/// Maps WebSocket handshakes to the [WebSocketHandler]s of the
/// [WebSocketConfigurer] beans and to the `@WebSocketEndpoint` beans, like
/// Spring's `WebSocketHandlerMapping`. The web starter's dispatcher asks it
/// (it is a `HandlerMapping`), after the filters: a handshake is
/// authenticated like any request.
///
/// Every endpoint is checked at startup (two endpoints on one path, an
/// `@PathVariable` that is not in the path, a parameter without a role).
final class WebSocketHandlerMapping
    implements HandlerMapping, Ordered, SmartInitializingSingleton {
  /// The mapping of the handlers and endpoints of [beanFactory].
  WebSocketHandlerMapping({
    required this.beanFactory,
    required this.mapper,
    required this.sessions,
    this.configurers = const [],
  });

  /// Where the endpoints are found.
  final ListableBeanFactory beanFactory;

  /// Reads and writes JSON messages.
  final ObjectMapper mapper;

  /// Tracks the open sessions.
  final WebSocketSessionRegistry sessions;

  /// Register handlers.
  final List<WebSocketConfigurer> configurers;

  final _routes = <_Route>[];
  var _initialized = false;

  /// After the controllers' mapping (order 0), like Spring.
  @override
  int get order => 1;

  /// The mapped paths.
  List<String> get paths => [
    for (final route in _routes) route.pattern.pattern,
  ];

  @override
  void afterSingletonsInstantiated() => initialize();

  /// Finds the handlers and endpoints; throws a [StateError] listing every
  /// problem.
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
      return await response.send(400, 'Can "Upgrade" only to "WebSocket".');
    }
    if (!route.allowsOrigin(request)) {
      _log.debug(
        'Handshake from origin ${request.headers[HttpHeaders.originHeader]} '
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
    final attributes = <String, Object?>{};
    for (final interceptor in route.interceptors) {
      if (!await interceptor.beforeHandshake(request, response, attributes)) {
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
    unawaited(_run(route, session));
  }

  Future<void> _run(_Route route, ServerWebSocketSession session) async {
    final handler = route.handler;
    // One message after the other, in order.
    var last = Future<void>.value();
    Future<void> guarded(FutureOr<void> Function() body) async {
      try {
        await body();
      } on Object catch (error, stackTrace) {
        await _failed(handler, session, error, stackTrace);
      }
    }

    await guarded(() => handler.afterConnectionEstablished(session));
    final closed = Completer<void>();
    session.messages.listen(
      (message) => last = last.then(
        (_) => guarded(() => handler.handleMessage(session, message)),
      ),
      onError: (Object error, StackTrace stackTrace) =>
          last = last.then((_) => _failed(handler, session, error, stackTrace)),
      onDone: () => closed.complete(),
      cancelOnError: false,
    );
    await closed.future;
    await last;
    sessions.unregister(route.path, session);
    await guarded(
      () => handler.afterConnectionClosed(
        session,
        session.closeStatus ?? CloseStatus.noStatusCode,
      ),
    );
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

  // Like Spring's OriginHandshakeInterceptor: no Origin (not a browser)
  // or the server's own origin is fine, others must be allowed.
  bool allowsOrigin(ServerHttpRequest request) {
    final origin = request.headers[HttpHeaders.originHeader];
    if (origin == null || allowedOrigins.contains('*')) {
      return true;
    }
    final parsed = Uri.tryParse(origin);
    final own = request.uri;
    if (parsed != null &&
        parsed.host == own.host &&
        _port(parsed) == _port(own) &&
        _secure(parsed) == request.isSecure) {
      return true;
    }
    if (allowedOrigins.any((o) => o.toLowerCase() == origin.toLowerCase())) {
      return true;
    }
    return allowedOriginPatterns.any((pattern) => _matches(pattern, origin));
  }

  static bool _secure(Uri uri) => uri.scheme == 'https' || uri.scheme == 'wss';

  static int _port(Uri uri) =>
      uri.hasPort ? uri.port : (_secure(uri) ? 443 : 80);

  static bool _matches(String pattern, String origin) {
    final regex = StringBuffer('^');
    for (final char in pattern.split('')) {
      regex.write(char == '*' ? '.*' : RegExp.escape(char));
    }
    regex.write(r'$');
    return RegExp(regex.toString(), caseSensitive: false).hasMatch(origin);
  }
}

typedef _Binder = FutureOr<Object?> Function(_Call call);

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

/// A `@WebSocketEndpoint` bean as a [WebSocketHandler].
final class _EndpointAdapter implements WebSocketHandler {
  _EndpointAdapter(
    this.owner,
    this.beanName,
    this.onOpen,
    this.onMessage,
    this.onClose,
    this.onError,
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
          binders.add((parameter, (call) => call.session.pathVariables[name]));
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
