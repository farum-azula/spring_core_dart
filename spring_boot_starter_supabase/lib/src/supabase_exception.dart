/// A call to Supabase that failed.
///
/// The services have their own subclasses (`StorageException`, ...); the
/// repositories throw the data starter's `DataAccessException`s and a
/// failed login Spring Security's `AuthenticationException`s, so code
/// written against Spring's types does not change.
///
/// ```dart
/// try {
///   await storage.download('avatars', 'u1.png');
/// } on SupabaseException catch (e) {
///   log.warning('storage answered ${e.statusCode}: ${e.message}');
/// }
/// ```
class SupabaseException implements Exception {
  /// A failure with [message]; [statusCode] and [code] are the answer's
  /// when there was one.
  SupabaseException(this.message, {this.statusCode, this.code, this.cause});

  /// What went wrong, as the service said it. Never contains a key or a
  /// token.
  final String message;

  /// The HTTP status of the answer; `null` when there was none.
  final int? statusCode;

  /// The service's own error code (`PGRST116`, `invalid_credentials`,
  /// `NoSuchKey`, ...), when it gave one.
  final String? code;

  /// The error underneath, when there is one.
  final Object? cause;

  /// The text of [toString] for an exception called [type]: the type,
  /// the status and the code when there are any, then the message.
  /// Subclasses give their own name.
  String describe(String type) {
    final out = StringBuffer(type);
    if (statusCode case final status?) {
      out.write(' ($status)');
    }
    if (code case final code?) {
      out.write(' [$code]');
    }
    out.write(': $message');
    return out.toString();
  }

  @override
  String toString() => describe('SupabaseException');
}

/// The project could not be reached, or did not answer in time.
///
/// Nothing is known about whether the call had an effect.
class SupabaseUnavailableException extends SupabaseException {
  /// No answer from the project; [isTimeout] when it was a timeout.
  SupabaseUnavailableException(
    super.message, {
    super.cause,
    this.isTimeout = false,
  });

  /// Whether the time ran out (rather than the connection failing).
  final bool isTimeout;

  @override
  String toString() => describe('SupabaseUnavailableException');
}
