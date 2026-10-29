/// The claims of a DPoP proof (RFC 9449 §4.2): which request the proof is
/// for, when it was made, and a one-time id.
///
/// With DPoP an access token is bound to a key only the app holds. Each
/// request then carries, in its `DPoP` header, a short JWT signed with
/// that key: the proof. Its claims tie it to one request, so a proof
/// caught on the way cannot be used for another request, or twice. The
/// app writes them with [toJson]; the resource server reads them with
/// [DPoPProofClaims.fromJson], strictly, after checking the signature.
///
/// ```dart
/// // The claims of a proof for a call to an API with a DPoP token.
/// final claims = DPoPProofClaims(
///   jti: randomId(),
///   htm: 'GET',
///   htu: Uri.parse('https://api.example.com/orders'),
///   iat: DateTime.now(),
///   ath: sha256Base64Url(accessToken),
/// );
/// final payload = claims.toJson();
/// ```
///
/// Spring (Java): no type of its own; Spring Security reads these claims
/// from the proof's `Jwt` in its DPoP validators.
final class DPoPProofClaims {
  /// The claims of a proof for a [htm] request to [htu] made at [iat].
  ///
  /// The query and fragment of [htu] are dropped, as RFC 9449 §4.2 wants.
  /// Throws an [ArgumentError] when [jti] or [htm] is empty, or [htu] is
  /// not an absolute `http` or `https` URL.
  DPoPProofClaims({
    required this.jti,
    required this.htm,
    required Uri htu,
    required DateTime iat,
    this.ath,
    this.nonce,
  }) : htu = _target(htu),
       iat = DateTime.fromMillisecondsSinceEpoch(
         iat.millisecondsSinceEpoch ~/ 1000 * 1000,
         isUtc: true,
       ) {
    if (jti.isEmpty) {
      throw ArgumentError.value(jti, 'jti', 'must not be empty');
    }
    if (htm.isEmpty) {
      throw ArgumentError.value(htm, 'htm', 'must not be empty');
    }
  }

  /// Reads the claims of a proof, strictly: `jti`, `htm` and `htu` must be
  /// non-empty strings, `iat` a number of seconds, `ath` and `nonce`
  /// strings when present. Nothing is converted: a number where a string
  /// belongs is refused. Other claims are ignored, as RFC 9449 allows.
  ///
  /// Throws a [FormatException] for a missing or mistyped claim, or an
  /// `htu` that is not an absolute `http` or `https` URL.
  factory DPoPProofClaims.fromJson(Map<String, Object?> claims) {
    String text(String name) => switch (claims[name]) {
      final String value when value.isNotEmpty => value,
      _ => throw FormatException('The DPoP proof has no valid $name claim'),
    };
    String? optional(String name) => switch (claims[name]) {
      null when !claims.containsKey(name) => null,
      final String value => value,
      _ => throw FormatException('The DPoP proof has no valid $name claim'),
    };
    final iat = switch (claims['iat']) {
      final num seconds when seconds.isFinite && seconds.abs() < 1e11 =>
        DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).floor(),
          isUtc: true,
        ),
      _ => throw const FormatException('The DPoP proof has no valid iat claim'),
    };
    final Uri htu;
    try {
      htu = Uri.parse(text('htu'));
    } on FormatException {
      throw const FormatException('The DPoP proof has no valid htu claim');
    }
    try {
      return DPoPProofClaims(
        jti: text('jti'),
        htm: text('htm'),
        htu: htu,
        iat: iat,
        ath: optional('ath'),
        nonce: optional('nonce'),
      );
    } on ArgumentError catch (e) {
      throw FormatException('The DPoP proof has no valid ${e.name} claim');
    }
  }

  static Uri _target(Uri htu) {
    if (!htu.isScheme('http') && !htu.isScheme('https') || htu.host.isEmpty) {
      throw ArgumentError.value(
        htu,
        'htu',
        'must be an absolute http or https URL',
      );
    }
    return Uri(
      scheme: htu.scheme,
      userInfo: htu.userInfo,
      host: htu.host,
      port: htu.hasPort ? htu.port : null,
      path: htu.path,
    );
  }

  /// The proof's one-time id, unique per request; the server refuses an
  /// id it has seen before (a replayed proof).
  final String jti;

  /// The HTTP method of the request the proof is for, such as `GET`.
  final String htm;

  /// The URL of the request the proof is for, without query and
  /// fragment.
  final Uri htu;

  /// When the proof was made, in UTC, to the second; the server accepts
  /// it only for a short time around its own clock.
  final DateTime iat;

  /// On calls with an access token: the base64url SHA-256 of the token,
  /// which ties the proof to it; `null` on token requests.
  final String? ath;

  /// The nonce the server asked for in a `DPoP-Nonce` header, or `null`.
  final String? nonce;

  /// The claims as the JSON object of the proof's payload; `ath` and
  /// `nonce` only when set, `iat` in seconds.
  Map<String, Object?> toJson() => {
    'jti': jti,
    'htm': htm,
    'htu': htu.toString(),
    'iat': iat.millisecondsSinceEpoch ~/ 1000,
    if (ath != null) 'ath': ath,
    if (nonce != null) 'nonce': nonce,
  };

  /// A description for logs: method, URL and time; `jti` and `ath` are
  /// left out.
  @override
  String toString() => 'DPoPProofClaims [htm=$htm, htu=$htu, iat=$iat]';
}
