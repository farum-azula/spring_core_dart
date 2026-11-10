import 'dart:async';

import 'package:spring_core_dart/src/core/isolate/isolate_info.dart';

/// Something the application's first isolate answers for all of them: a
/// bean that implements it is asked there, whichever isolate the question
/// comes from ([PrimaryIsolate.ask]).
///
/// With a pool of server isolates a request may reach any of them, but
/// some things exist once: the pool itself, the numbers added up from
/// every isolate, a counter the application keeps in one place. Their
/// owner lives in the first isolate and answers through this.
///
/// ```dart
/// @Component()
/// class Tickets implements PrimaryIsolateHandler {
///   var _next = 0;
///
///   @override
///   String get id => 'tickets.next';
///
///   // Runs in the first isolate only: one sequence for the application.
///   @override
///   Object? handle(Object? request) => ++_next;
/// }
/// ```
abstract interface class PrimaryIsolateHandler {
  /// The name questions are sent under, one per handler.
  String get id;

  /// Answers [request] in the first isolate. Both cross isolates as JSON
  /// values (numbers, text, lists and maps of them).
  FutureOr<Object?> handle(Object? request);
}

/// Asks the application's first isolate: the bean `primaryIsolate`.
///
/// In the first isolate (the only one without a pool) the question goes
/// straight to the [PrimaryIsolateHandler] bean of that id; in another
/// isolate of the server's pool it is sent to the first one and the
/// answer comes back. So code that asks is the same in every isolate.
///
/// ```dart
/// final ticket = await primary.ask('tickets.next') as int;
/// ```
final class PrimaryIsolate {
  /// The first isolate's [handlers], asked here when this is it.
  PrimaryIsolate(this.handlers);

  /// The handlers of this isolate; they answer only in the first one.
  final List<PrimaryIsolateHandler> handlers;

  /// Sends a question to the first isolate, in an isolate that is not the
  /// first: a pool sets it in each isolate it starts, before the
  /// application starts there, so a bean may ask as soon as it exists.
  /// `null` in the first isolate.
  static Future<Object?> Function(String id, Object? request)? remote;

  /// Asks the handler named [id] in the first isolate and completes with
  /// its answer. Fails with a [StateError] when no handler has that id,
  /// and with the handler's error (as text, from another isolate) when it
  /// throws.
  Future<Object?> ask(String id, [Object? request]) async {
    final remote = PrimaryIsolate.remote;
    if (remote != null) {
      return await remote(id, request);
    }
    for (final handler in handlers) {
      if (handler.id == id) {
        return await handler.handle(request);
      }
    }
    throw StateError(
      'No PrimaryIsolateHandler bean answers "$id" in '
      '${IsolateInfo.current.name}',
    );
  }
}

/// An error of a [PrimaryIsolateHandler], as it reaches another isolate:
/// its text.
final class PrimaryIsolateException implements Exception {
  /// The error as text.
  const PrimaryIsolateException(this.message);

  /// The error's `toString()` in the first isolate.
  final String message;

  @override
  String toString() => 'PrimaryIsolateException: $message';
}
