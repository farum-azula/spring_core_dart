/// Receives the errors of work that has no caller to throw them to, such
/// as a scheduled task.
///
/// Each component that takes one says how it picks it and what a handler
/// that throws means there. There is no application-wide channel of
/// errors: a handler gets only what the component it is given to reports.
///
/// ```dart
/// // Every failed run of a task is reported, and the task keeps running.
/// @Component()
/// class ReportErrors implements ErrorHandler {
///   @override
///   void handleError(Object error, StackTrace stackTrace) =>
///       crashReporter.record(error, stackTrace);
/// }
/// ```
///
/// Spring (Java): `org.springframework.util.ErrorHandler`.
/// ```java
/// scheduler.setErrorHandler(t -> crashReporter.record(t));
/// ```
abstract interface class ErrorHandler {
  /// Called with [error] and its [stackTrace].
  void handleError(Object error, StackTrace stackTrace);
}

/// An [ErrorHandler] for the errors of one type [E], which a component
/// that reports errors of that type asks the container for.
///
/// It is deliberately no [ErrorHandler]: Dart's generics are covariant, so
/// were it one, a component asking for any handler would find this one
/// too and pass it errors of other types.
///
/// ```dart
/// @Component()
/// class PaymentErrors implements TypedErrorHandler<PaymentFailure> {
///   @override
///   void handleError(PaymentFailure error, StackTrace stackTrace) =>
///       alerts.send(error.orderId);
/// }
/// ```
///
/// Spring has no counterpart: its `ErrorHandler` takes any `Throwable`.
abstract interface class TypedErrorHandler<E extends Object> {
  /// Called with [error] and its [stackTrace].
  void handleError(E error, StackTrace stackTrace);
}
