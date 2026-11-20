import 'dart:async';
import 'dart:io';

import 'package:dart_spring_language_server/src/protocol/message_channel.dart';

/// Answers a request: its result (JSON), or null.
typedef RequestHandler = Object? Function(Map<String, Object?> params);

/// Handles a notification.
typedef NotificationHandler = void Function(Map<String, Object?> params);

/// One capability of the server: what it announces in the answer to
/// `initialize`, and the requests and notifications it handles. Every
/// member has a default that does nothing, so a feature names only what
/// it does.
abstract class ServerFeature {
  /// What it adds to `capabilities` in the answer to `initialize`.
  Map<String, Object?> get capabilities => const {};

  /// The requests it answers, by method.
  Map<String, RequestHandler> get requests => const {};

  /// The notifications it handles, by method; several features may handle
  /// the same one, in their order.
  Map<String, NotificationHandler> get notifications => const {};

  /// Called once, when the server stops.
  void dispose() {}
}

/// What the features of a session may send to the editor.
abstract interface class Editor {
  /// Sends the notification [method].
  void notify(String method, Map<String, Object?> params);

  /// Sends the request [method], without waiting for its answer (such as
  /// `workspace/inlayHint/refresh`).
  void request(String method, [Map<String, Object?>? params]);
}

/// What a request handler throws when it cannot do what was asked, for a
/// reason the user should read (a rename that would break code): the
/// editor gets [message] as the error, nothing goes to stderr.
final class RequestFailure implements Exception {
  /// A failure the editor shows as [message].
  const RequestFailure(this.message);

  /// Why the request failed, for the user.
  final String message;

  /// The protocol's code for a request that failed although it was valid.
  static const code = -32803;

  @override
  String toString() => message;
}

/// Builds the features of a session from the `initialize` parameters, once
/// the editor has said which folders it opened.
typedef SessionFactory = List<ServerFeature> Function(
  Map<String, Object?> initializeParams,
  Editor editor,
);

/// A language server: the protocol's lifecycle (`initialize`, `shutdown`,
/// `exit`) around the features a [SessionFactory] builds. A request goes to
/// the feature that answers its method, a notification to every feature
/// that handles it; an unknown request gets "method not found", a handler
/// that throws a [RequestFailure] answers with its message, and one that
/// throws anything else answers with an internal error (its stack trace
/// goes to stderr). The exit code is 0 when `shutdown` came before `exit`
/// or the end of the input, 1 otherwise, as the protocol asks.
final class LanguageServer implements Editor {
  /// A server named [name] in `serverInfo`, talking over its channel, with
  /// the features its session factory builds at `initialize`.
  LanguageServer(this.name, this._channel, this._session);

  /// The name in `serverInfo`.
  final String name;

  final MessageChannel _channel;
  final SessionFactory _session;
  var _features = const <ServerFeature>[];
  final _requests = <String, RequestHandler>{};
  final _notifications = <String, List<NotificationHandler>>{};
  var _shutdown = false;
  var _nextRequest = 0;

  /// Handles messages until `exit` or the end of the input; the exit code.
  Future<int> serve() async {
    await for (final message in _channel.messages) {
      if (_handle(message) case final code?) {
        _dispose();
        return code;
      }
    }
    _dispose();
    return _shutdown ? 0 : 1;
  }

  @override
  void notify(String method, Map<String, Object?> params) =>
      _channel.send({'method': method, 'params': params});

  @override
  void request(String method, [Map<String, Object?>? params]) => _channel.send({
    'id': '$name-${_nextRequest++}',
    'method': method,
    'params': ?params,
  });

  /// Handles [message]; the exit code when the editor asked to exit.
  int? _handle(Map<String, Object?> message) {
    final method = message['method'] as String?;
    final id = message['id'];
    final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
    try {
      switch (method) {
        case null:
          break; // the answer to a request of the server
        case 'initialize':
          _channel.send({'id': id, 'result': _initialize(params)});
        case 'shutdown':
          _shutdown = true;
          _channel.send({'id': id, 'result': null});
        case 'exit':
          return _shutdown ? 0 : 1;
        case final method when id != null:
          final handler = _requests[method];
          if (handler == null) {
            _error(id, -32601, 'Method not found: $method');
          } else {
            _channel.send({'id': id, 'result': handler(params)});
          }
        case final method:
          for (final handler
              in _notifications[method] ?? const <NotificationHandler>[]) {
            handler(params);
          }
      }
    } on RequestFailure catch (failure) {
      if (id != null) {
        _error(id, RequestFailure.code, failure.message);
      }
    } on Object catch (error, stackTrace) {
      stderr.writeln('$name: $method failed: $error\n$stackTrace');
      if (id != null) {
        _error(id, -32603, '$error');
      }
    }
    return null;
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    _features = _session(params, this);
    for (final feature in _features) {
      _requests.addAll(feature.requests);
      for (final MapEntry(key: method, value: handler)
          in feature.notifications.entries) {
        (_notifications[method] ??= []).add(handler);
      }
    }
    return {
      'capabilities': {
        'positionEncoding': 'utf-16',
        for (final feature in _features) ...feature.capabilities,
      },
      'serverInfo': {'name': name},
    };
  }

  void _error(Object id, int code, String message) => _channel.send({
    'id': id,
    'error': {'code': code, 'message': message},
  });

  void _dispose() {
    for (final feature in _features) {
      feature.dispose();
    }
    _features = const [];
  }
}
