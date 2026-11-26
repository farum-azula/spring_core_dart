import 'package:spring_boot_dart/spring_boot_dart.dart' show SecretNames;
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_web_dart/spring_web_dart.dart'
    show HttpHeaders, HttpSecrets;

/// What the network recorder masks before anything reaches the journal:
/// the headers that carry a credential, the credentials of an address,
/// and the secrets of a recorded body. The rules are the family's:
///
/// - a header by `HttpSecrets.isSensitiveHeader` (`Authorization`,
///   `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `DPoP`, names with
///   `session`, names that look secret by `SecretNames`), and the
///   request's own `sensitiveHeaders` (a Feign client's
///   `sensitive-headers`);
/// - an address's user-info password, and each query parameter by
///   `HttpSecrets.isSensitiveParameter` (`code`, `state`, `token`,
///   `apikey`, `signature`...): the request's, every address in the
///   value of `Location`, `Content-Location` and `Link`, and every
///   address in a recorded error's text ([text]);
/// - a WebSocket subprotocol that carries a credential ([protocols]);
/// - a body by the first [NetworkBodyMasker] that takes its type: the
///   values of JSON keys that look secret (`password`, `access_token`),
///   the secret parameters of a form.
final class NetworkMasking {
  /// The masking with [bodyMaskers] asked in order; the built-in ones
  /// after an application's.
  const NetworkMasking({this.bodyMaskers = defaultBodyMaskers});

  /// What stands for a masked value.
  static const masked = SecretNames.masked;

  /// The built-in body maskers: forms, then JSON.
  static const defaultBodyMaskers = <NetworkBodyMasker>[
    FormBodyMasker(),
    JsonBodyMasker(),
  ];

  /// The maskers of bodies, the first that supports a body masks it.
  final List<NetworkBodyMasker> bodyMaskers;

  /// [headers] as recorded: each header that carries a credential, by the
  /// family's rule or by [sensitive] (lower-case names), masked.
  List<NetworkHeader> headers(
    HttpHeaders? headers, {
    Set<String> sensitive = const {},
  }) {
    if (headers == null || headers.isEmpty) {
      return const [];
    }
    final recorded = <NetworkHeader>[];
    headers.forEach((name, values) {
      final lower = name.toLowerCase();
      final secret = _sensitiveHeader(name) || sensitive.contains(lower);
      final addresses = _addressHeaders.contains(lower);
      for (final value in values) {
        recorded.add(
          secret
              ? NetworkHeader(name, masked, masked: true)
              : NetworkHeader(name, addresses ? text(value) : value),
        );
      }
    });
    return recorded;
  }

  // The headers whose values are addresses, which may carry a credential
  // (a redirect's `?code=`).
  static const _addressHeaders = {'location', 'content-location', 'link'};

  /// [text] with every address in it masked as [url] masks one: an
  /// error's text (`HttpException: ..., uri = https://...?token=...`), a
  /// header that holds addresses.
  String text(String text) {
    if (!text.contains('://')) {
      return text;
    }
    return text.replaceAllMapped(_address, (match) {
      final found = match[0]!;
      final parsed = Uri.tryParse(found);
      return parsed == null || !parsed.hasAuthority ? found : '${url(parsed)}';
    });
  }

  static final _address = RegExp(
    r'''[A-Za-z][A-Za-z0-9+.\-]*://[^\s'"<>()\[\]{},;]+''',
  );

  /// The WebSocket subprotocols [protocols] as recorded: one that carries
  /// a credential is [masked]. That is one whose name looks secret by
  /// `SecretNames` and is longer than a name (a token carried as a
  /// subprotocol, `base64url.bearer.authorization.k8s.io.<token>`), one
  /// longer than [protocolLength], and the one after a name of a secret
  /// (`access_token`, then the token).
  List<String> protocols(List<String> protocols) {
    if (protocols.isEmpty) {
      return protocols;
    }
    final recorded = <String>[];
    var afterSecret = false;
    for (final protocol in protocols) {
      final secretName = SecretNames.looksSecret(protocol);
      final carries =
          afterSecret ||
          protocol.length > protocolLength ||
          (secretName && protocol.contains('.'));
      recorded.add(carries ? masked : protocol);
      afterSecret = secretName && !carries;
    }
    return recorded;
  }

  /// The longest subprotocol recorded as it is: a registered name is
  /// short (`graphql-transport-ws`, `v12.stomp`), a token is not.
  static const protocolLength = 32;

  /// [url] with its user-info password and its secret query parameters
  /// masked.
  Uri url(Uri url) {
    var changed = false;
    var userInfo = url.userInfo;
    final colon = userInfo.indexOf(':');
    if (colon >= 0) {
      userInfo = '${userInfo.substring(0, colon)}:$masked';
      changed = true;
    }
    String? query;
    if (url.hasQuery) {
      final parts = <String>[];
      for (final part in url.query.split('&')) {
        final equals = part.indexOf('=');
        final name = equals < 0 ? part : part.substring(0, equals);
        if (equals >= 0 && HttpSecrets.isSensitiveParameter(_decoded(name))) {
          parts.add('$name=$masked');
          changed = true;
        } else {
          parts.add(part);
        }
      }
      query = parts.join('&');
    }
    return changed ? url.replace(userInfo: userInfo, query: query) : url;
  }

  /// [text], a body of [contentType], with its secrets masked by the first
  /// masker that supports it; as it is when none does.
  String body(String text, String? contentType) {
    for (final masker in bodyMaskers) {
      if (masker.supports(text, contentType)) {
        return masker.mask(text);
      }
    }
    return text;
  }

  // The family's rule asked once per header name: requests repeat them.
  static final _headerRule = <String, bool>{};

  static bool _sensitiveHeader(String name) {
    if (_headerRule.length > 512) {
      _headerRule.clear();
    }
    return _headerRule[name] ??= HttpSecrets.isSensitiveHeader(name);
  }

  static String _decoded(String name) {
    try {
      return Uri.decodeQueryComponent(name);
    } on FormatException {
      return name;
    }
  }
}

/// Masks the secrets of a recorded body of a kind: one of a chain in
/// [NetworkMasking.bodyMaskers], the first that [supports] a body masks
/// it. The text may be cut at the body limit: a masker reads what it can.
///
/// ```dart
/// // A body of the app's own format: `secret=...` lines.
/// final class LinesBodyMasker implements NetworkBodyMasker {
///   const LinesBodyMasker();
///
///   @override
///   bool supports(String text, String? contentType) =>
///       contentType == 'text/x-neon-lines';
///
///   @override
///   String mask(String text) => text.replaceAllMapped(
///     RegExp(r'^(secret=).*$', multiLine: true),
///     (m) => '${m[1]}${NetworkMasking.masked}',
///   );
/// }
/// ```
abstract interface class NetworkBodyMasker {
  /// Whether it masks [text] of [contentType].
  bool supports(String text, String? contentType);

  /// [text] with its secrets masked.
  String mask(String text);
}

/// Masks the parameters of an `application/x-www-form-urlencoded` body by
/// `HttpSecrets.isSensitiveParameter`: an OAuth token request's
/// `client_secret`, `code_verifier`, `refresh_token`, `password`.
final class FormBodyMasker implements NetworkBodyMasker {
  /// The masker.
  const FormBodyMasker();

  @override
  bool supports(String text, String? contentType) =>
      contentType?.toLowerCase().contains('x-www-form-urlencoded') ?? false;

  @override
  String mask(String text) => [
    for (final part in text.split('&'))
      switch (part.indexOf('=')) {
        final equals
            when equals > 0 &&
                HttpSecrets.isSensitiveParameter(
                  NetworkMasking._decoded(part.substring(0, equals)),
                ) =>
          '${part.substring(0, equals)}=${NetworkMasking.masked}',
        _ => part,
      },
  ].join('&');
}

/// Masks the values of the JSON keys whose names look secret by
/// `SecretNames.looksSecret` (`password`, `access_token`, `apiKey`): a
/// string, a number or a literal, in a body cut short too.
final class JsonBodyMasker implements NetworkBodyMasker {
  /// The masker.
  const JsonBodyMasker();

  static final _member = RegExp(
    r'"((?:[^"\\]|\\.)*)"(\s*:\s*)("(?:[^"\\]|\\.)*"?|[-\w.+]+)',
  );

  @override
  bool supports(String text, String? contentType) {
    if (contentType?.toLowerCase().contains('json') ?? false) {
      return true;
    }
    final start = text.trimLeft();
    return start.startsWith('{') || start.startsWith('[');
  }

  // The rule asked once per key name: a body repeats its keys.
  static final _secret = <String, bool>{};

  static bool _looksSecret(String name) {
    if (_secret.length > 1024) {
      _secret.clear();
    }
    return _secret[name] ??= SecretNames.looksSecret(name);
  }

  @override
  String mask(String text) => text.replaceAllMapped(
    _member,
    (match) => _looksSecret(match[1]!)
        ? '"${match[1]}"${match[2]}"${NetworkMasking.masked}"'
        : match[0]!,
  );
}
