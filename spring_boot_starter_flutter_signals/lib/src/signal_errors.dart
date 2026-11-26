import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog('spring.flutter.signals');

/// Which of a bean's followed methods failed.
enum SignalExecutionKind {
  /// An `@Effect` method.
  effect,

  /// An `@OnWatched` method.
  watched,

  /// An `@OnUnwatched` method.
  unwatched,
}

/// A failure of followed code that no caller is waiting for: an effect run
/// again by a change, after a flush or a commit, or a watch callback.
///
/// It says where, never with what value: the state may be a secret.
///
/// ```dart
/// @Component()
/// class SignalErrors
///     implements TypedErrorHandler<SignalExecutionException> {
///   @override
///   void handleError(SignalExecutionException error, StackTrace stack) =>
///       crashReporter.record(error.cause, stack, reason: '$error');
/// }
/// ```
final class SignalExecutionException implements Exception {
  /// The failure of the member [member] of the bean [bean].
  const SignalExecutionException({
    required this.kind,
    required this.bean,
    required this.member,
    required this.cause,
  });

  /// What failed.
  final SignalExecutionKind kind;

  /// The bean's class.
  final String bean;

  /// The method.
  final String member;

  /// What the method threw.
  final Object cause;

  @override
  String toString() =>
      'SignalExecutionException: ${kind.name} $bean.$member failed with '
      '${cause.runtimeType}';
}

/// Hands the errors of followed code to the application.
final class SignalErrorReporter {
  /// The reporter that asks [handler] for the handler bean, when it runs.
  SignalErrorReporter([this.handler]);

  /// Finds the `TypedErrorHandler<SignalExecutionException>` bean; `null`
  /// without one.
  final TypedErrorHandler<SignalExecutionException>? Function()? handler;

  /// Reports [error] of the member [member] of [bean]. Never throws:
  /// what is running goes on.
  void report(
    SignalExecutionKind kind,
    String bean,
    String member,
    Object error,
    StackTrace stackTrace,
  ) {
    final failure = SignalExecutionException(
      kind: kind,
      bean: bean,
      member: member,
      cause: error,
    );
    try {
      final target = handler?.call();
      if (target != null) {
        target.handleError(failure, stackTrace);
        return;
      }
    } on Object catch (thrown, trace) {
      _log.error(
        'The handler of signal errors failed for $failure',
        error: thrown,
        stackTrace: trace,
      );
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: failure,
        stack: stackTrace,
        library: 'spring_boot_starter_flutter_signals',
        context: ErrorDescription('while running ${kind.name} $bean.$member'),
      ),
    );
  }
}
