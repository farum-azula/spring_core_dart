import 'dart:convert';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// What every exception made from an answer of Supabase Auth carries
/// besides Spring Security's own type: Auth's error code and the HTTP
/// status.
///
/// ```dart
/// try {
///   await auth.signInWithPassword(email: email, password: password);
/// } on BadCredentialsException {
///   showError('Wrong email or password');
/// } on AuthenticationException catch (e) {
///   if (e case SupabaseAuthFailure(errorCode: 'email_not_confirmed')) {
///     showError('Confirm your email address first');
///   }
/// }
/// ```
abstract interface class SupabaseAuthFailure {
  /// Auth's error code (`invalid_credentials`, `otp_expired`,
  /// `over_request_rate_limit`, ...); `null` when the answer had none or
  /// the login was refused before any request.
  String? get errorCode;

  /// The HTTP status of the answer; `null` when the login was refused
  /// before any request.
  int? get statusCode;
}

String _describe(String type, SupabaseAuthFailure failure, String message) {
  final out = StringBuffer(type);
  if (failure.statusCode case final status?) {
    out.write(' ($status)');
  }
  if (failure.errorCode case final code?) {
    out.write(' [$code]');
  }
  out.write(': $message');
  return out.toString();
}

/// A failure of Supabase Auth that has no closer type: a rate limit, a
/// request Auth could not accept, a login refused on this side (a
/// redirect that is not the one asked for, an answer without a session).
/// Read [errorCode] to tell them apart.
class SupabaseAuthenticationException extends AuthenticationException
    implements SupabaseAuthFailure {
  /// A failure with [message], Auth's [errorCode] and the [statusCode].
  SupabaseAuthenticationException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() =>
      _describe('SupabaseAuthenticationException', this, message);
}

/// The email and password, the phone and password, the one-time code or
/// the authorization code were refused (`invalid_credentials`,
/// `otp_expired`, `bad_code_verifier`, ...). Auth does not say which part
/// was wrong, and an application should not either.
class SupabaseBadCredentialsException extends BadCredentialsException
    implements SupabaseAuthFailure {
  /// A refused login with [message], Auth's [errorCode] and the
  /// [statusCode].
  SupabaseBadCredentialsException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() =>
      _describe('SupabaseBadCredentialsException', this, message);
}

/// The user exists but may not sign in yet: the email address or the
/// phone number is not confirmed (`email_not_confirmed`,
/// `phone_not_confirmed`).
class SupabaseAccountDisabledException extends DisabledException
    implements SupabaseAuthFailure {
  /// A refused login with [message], Auth's [errorCode] and the
  /// [statusCode].
  SupabaseAccountDisabledException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() =>
      _describe('SupabaseAccountDisabledException', this, message);
}

/// The user is banned (`user_banned`).
class SupabaseAccountLockedException extends LockedException
    implements SupabaseAuthFailure {
  /// A refused login with [message], Auth's [errorCode] and the
  /// [statusCode].
  SupabaseAccountLockedException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() =>
      _describe('SupabaseAccountLockedException', this, message);
}

/// The login is over: the refresh token was refused, used twice or its
/// session ended (`refresh_token_not_found`, `refresh_token_already_used`,
/// `session_not_found`, `session_expired`). The user was signed out here
/// and signs in again.
class SupabaseSessionExpiredException extends CredentialsExpiredException
    implements SupabaseAuthFailure {
  /// An ended login with [message], Auth's [errorCode] and the
  /// [statusCode].
  SupabaseSessionExpiredException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() =>
      _describe('SupabaseSessionExpiredException', this, message);
}

/// There is no such user (`user_not_found`).
class SupabaseUserNotFoundException extends UsernameNotFoundException
    implements SupabaseAuthFailure {
  /// A missing user with [message], Auth's [errorCode] and the
  /// [statusCode].
  SupabaseUserNotFoundException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() =>
      _describe('SupabaseUserNotFoundException', this, message);
}

/// The password is too weak for the project's rules (`weak_password`);
/// [reasons] says why (`length`, `characters`, `pwned`).
class SupabaseWeakPasswordException extends SupabaseAuthenticationException {
  /// A refused password with [message] and Auth's [reasons].
  SupabaseWeakPasswordException(
    super.message, {
    super.errorCode,
    super.statusCode,
    List<String> reasons = const [],
  }) : reasons = List.unmodifiable(reasons);

  /// Why the password was refused: `length`, `characters`, `pwned`.
  final List<String> reasons;

  @override
  String toString() =>
      _describe('SupabaseWeakPasswordException', this, message);
}

/// Auth itself failed (a status of 500 and above): nothing is known about
/// the login, and nobody is signed out because of it.
class SupabaseAuthServiceException extends AuthenticationServiceException
    implements SupabaseAuthFailure {
  /// A failure of the service with [message], Auth's [errorCode] and the
  /// [statusCode].
  SupabaseAuthServiceException(
    super.message, {
    this.errorCode,
    this.statusCode,
  });

  @override
  final String? errorCode;

  @override
  final int? statusCode;

  @override
  String toString() => _describe('SupabaseAuthServiceException', this, message);
}

/// An answer of Supabase Auth that is not a success, as Auth said it.
///
/// Auth answers `{"code": 400, "error_code": "invalid_credentials",
/// "msg": "..."}`; older versions and its OAuth endpoints
/// `{"error": "invalid_grant", "error_description": "..."}`; with the
/// header `X-Supabase-Api-Version` `{"code": "invalid_credentials",
/// "message": "..."}`. All three are read.
final class SupabaseAuthError {
  /// The error of an answer with [statusCode].
  SupabaseAuthError({
    required this.message,
    this.statusCode,
    this.code,
    List<String> weakPasswordReasons = const [],
  }) : weakPasswordReasons = List.unmodifiable(weakPasswordReasons);

  /// The HTTP status; `null` for an error that came in a redirect.
  final int? statusCode;

  /// Auth's error code, when the answer had one.
  final String? code;

  /// What Auth said, shortened, with everything secret that the request
  /// carried replaced by `[PROTECTED]`.
  final String message;

  /// The `weak_password.reasons` of the answer.
  final List<String> weakPasswordReasons;

  @override
  String toString() => 'SupabaseAuthError(${[?statusCode, ?code].join(' ')})';
}

/// One link of the chain that turns an answer of Auth into an exception.
///
/// Declare a bean of this type to give an error of your project (a hook
/// that refuses a login with its own code, say) an exception of its own;
/// the beans are asked before the starter's own links.
///
/// ```dart
/// @Component()
/// class TrialEnded implements SupabaseAuthErrorTranslator {
///   @override
///   AuthenticationException? translate(SupabaseAuthError error) =>
///       error.code == 'trial_ended'
///           ? AccountExpiredException(error.message)
///           : null;
/// }
/// ```
abstract interface class SupabaseAuthErrorTranslator {
  /// The exception of [error], or `null` to leave it to the next link.
  AuthenticationException? translate(SupabaseAuthError error);
}

/// A [SupabaseAuthErrorTranslator] for a set of Auth's error codes.
final class SupabaseAuthErrorCodes implements SupabaseAuthErrorTranslator {
  /// Answers with `exception` for an error whose code is one of [codes].
  const SupabaseAuthErrorCodes(this.codes, this._exception);

  /// The error codes this link answers for.
  final Set<String> codes;

  final AuthenticationException Function(SupabaseAuthError error) _exception;

  @override
  AuthenticationException? translate(SupabaseAuthError error) =>
      codes.contains(error.code) ? _exception(error) : null;
}

/// Reads the errors of Supabase Auth and turns them into Spring Security's
/// exceptions (the bean `supabaseAuthErrors`): the application's
/// [SupabaseAuthErrorTranslator] beans first, then [defaults].
///
/// - `invalid_credentials`, `invalid_grant`, `otp_expired`,
///   `bad_code_verifier`, `flow_state_*`:
///   [SupabaseBadCredentialsException], a `BadCredentialsException`;
/// - `email_not_confirmed`, `phone_not_confirmed`,
///   `provider_email_needs_verification`:
///   [SupabaseAccountDisabledException], a `DisabledException`;
/// - `user_banned`: [SupabaseAccountLockedException], a
///   `LockedException`;
/// - `refresh_token_not_found`, `refresh_token_already_used`,
///   `session_not_found`, `session_expired`:
///   [SupabaseSessionExpiredException], a `CredentialsExpiredException`;
/// - `user_not_found`: [SupabaseUserNotFoundException], a
///   `UsernameNotFoundException`;
/// - `weak_password`: [SupabaseWeakPasswordException];
/// - a status of 500 and above: [SupabaseAuthServiceException], an
///   `AuthenticationServiceException`;
/// - anything else: [SupabaseAuthenticationException].
final class SupabaseAuthErrors {
  /// The chain: [translators], then [defaults].
  SupabaseAuthErrors([
    Iterable<SupabaseAuthErrorTranslator> translators = const [],
  ]) : translators = List.unmodifiable([...translators, ...defaults]);

  /// The starter's own links, in order.
  static final List<SupabaseAuthErrorTranslator> defaults = List.unmodifiable([
    // First: a failure of the service says nothing about the login,
    // whatever code comes with it.
    const _ServerFailure(),
    SupabaseAuthErrorCodes(
      const {
        'invalid_credentials',
        'invalid_grant',
        'otp_expired',
        'bad_code_verifier',
        'flow_state_not_found',
        'flow_state_expired',
        'flow_state_already_used',
      },
      (e) => SupabaseBadCredentialsException(
        e.message,
        errorCode: e.code,
        statusCode: e.statusCode,
      ),
    ),
    SupabaseAuthErrorCodes(
      const {
        'email_not_confirmed',
        'phone_not_confirmed',
        'provider_email_needs_verification',
      },
      (e) => SupabaseAccountDisabledException(
        e.message,
        errorCode: e.code,
        statusCode: e.statusCode,
      ),
    ),
    SupabaseAuthErrorCodes(
      const {'user_banned'},
      (e) => SupabaseAccountLockedException(
        e.message,
        errorCode: e.code,
        statusCode: e.statusCode,
      ),
    ),
    SupabaseAuthErrorCodes(
      const {
        'refresh_token_not_found',
        'refresh_token_already_used',
        'session_not_found',
        'session_expired',
      },
      (e) => SupabaseSessionExpiredException(
        e.message,
        errorCode: e.code,
        statusCode: e.statusCode,
      ),
    ),
    SupabaseAuthErrorCodes(
      const {'user_not_found'},
      (e) => SupabaseUserNotFoundException(
        e.message,
        errorCode: e.code,
        statusCode: e.statusCode,
      ),
    ),
    SupabaseAuthErrorCodes(
      const {'weak_password'},
      (e) => SupabaseWeakPasswordException(
        e.message,
        errorCode: e.code,
        statusCode: e.statusCode,
        reasons: e.weakPasswordReasons,
      ),
    ),
  ]);

  /// The links, asked in order.
  final List<SupabaseAuthErrorTranslator> translators;

  static const _protected = '[PROTECTED]';
  static const _maxMessage = 300;

  /// The error of [response], an answer that is not a success.
  ///
  /// [secrets] are the secret values the request carried (a password, a
  /// code, a token): should the answer repeat one, it is replaced in the
  /// message.
  SupabaseAuthError read(
    HttpResponse response, {
    Iterable<String?> secrets = const [],
  }) {
    final status = response.statusCode.value;
    Object? json;
    try {
      json = jsonDecode(response.bodyText);
    } on FormatException {
      json = null;
    }
    if (json is! Map<String, Object?>) {
      return SupabaseAuthError(
        statusCode: status,
        message: 'Supabase Auth answered $status',
      );
    }
    final code = switch (json) {
      {'error_code': final String code} when code.isNotEmpty => code,
      {'code': final String code} when code.isNotEmpty => code,
      {'error': final String code} when code.isNotEmpty => code,
      _ => null,
    };
    final text = switch (json) {
      {'msg': final String text} when text.isNotEmpty => text,
      {'message': final String text} when text.isNotEmpty => text,
      {'error_description': final String text} when text.isNotEmpty => text,
      {'error': final String text} when text.isNotEmpty => text,
      _ => 'Supabase Auth answered $status',
    };
    return SupabaseAuthError(
      statusCode: status,
      code: code,
      message: protect(text, secrets),
      weakPasswordReasons: switch (json['weak_password']) {
        {'reasons': final List<Object?> reasons} => [
          for (final reason in reasons)
            if (reason is String) reason,
        ],
        _ => const [],
      },
    );
  }

  /// The exception of [error]: the first answer of the chain, else a
  /// [SupabaseAuthenticationException].
  AuthenticationException translate(SupabaseAuthError error) {
    for (final translator in translators) {
      if (translator.translate(error) case final exception?) {
        return exception;
      }
    }
    return SupabaseAuthenticationException(
      error.message,
      errorCode: error.code,
      statusCode: error.statusCode,
    );
  }

  /// [text] on one line, shortened, with each of [secrets] replaced by
  /// `[PROTECTED]`: what may go into an exception or a log.
  static String protect(String text, Iterable<String?> secrets) {
    var out = text;
    // The longest first: a secret inside another leaves no part behind.
    final values = [
      for (final secret in secrets)
        if (secret != null && secret.isNotEmpty) secret,
    ]..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in values) {
      out = out.replaceAll(secret, _protected);
    }
    out = out.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    return out.length > _maxMessage
        ? '${out.substring(0, _maxMessage)}...'
        : out;
  }
}

final class _ServerFailure implements SupabaseAuthErrorTranslator {
  const _ServerFailure();

  @override
  AuthenticationException? translate(SupabaseAuthError error) =>
      (error.statusCode ?? 0) >= 500
      ? SupabaseAuthServiceException(
          error.message,
          errorCode: error.code,
          statusCode: error.statusCode,
        )
      : null;
}
