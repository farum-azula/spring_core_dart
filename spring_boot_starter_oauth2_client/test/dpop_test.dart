// The shared DPoP types: RFC 7638 thumbprints and the claims of a DPoP
// proof, with the examples of RFC 7638 §3.1 and RFC 9449 as vectors, and
// the strict reading of proof claims (no coercion, nothing missing).
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:test/test.dart';

// RFC 7638 §3.1.
const _rfc7638Key = {
  'kty': 'RSA',
  'n':
      '0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aP'
      'FFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl9'
      '3lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdA'
      'ZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3'
      'XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw',
  'e': 'AQAB',
  'alg': 'RS256',
  'kid': '2011-04-29',
};

// RFC 9449 §4.1 (the key of the example proofs).
const _rfc9449Key = {
  'kty': 'EC',
  'x': 'l8tFrhx-34tV3hRICRDY9zCkDlpBhF42UQUfWVAWBFs',
  'y': '9VE4jf_Ok_o64zbTTlcuNJajHmt6v9TDVrU0CdvGRDA',
  'crv': 'P-256',
};

void main() {
  group('JwkThumbprint', () {
    test('RFC 7638 §3.1 (RSA)', () {
      expect(
        JwkThumbprint.of(_rfc7638Key),
        'NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs',
      );
    });

    test('RFC 9449 (EC): the jkt of the example tokens', () {
      expect(
        JwkThumbprint.of(_rfc9449Key),
        '0ZcOCORZNYy-DWpqq30jZyJGHTN0d2HglBV3uiguA4I',
      );
    });

    test('optional and private members do not change it', () {
      expect(
        JwkThumbprint.of({..._rfc9449Key, 'kid': 'k', 'use': 'sig', 'd': 'x'}),
        JwkThumbprint.of(_rfc9449Key),
      );
    });

    test('every required member counts', () {
      final base = JwkThumbprint.of(_rfc9449Key);
      for (final name in ['x', 'y', 'crv']) {
        expect(
          JwkThumbprint.of({..._rfc9449Key, name: 'AAAA'}),
          isNot(base),
          reason: name,
        );
      }
    });

    test('other key types, missing or mistyped members are refused', () {
      for (final jwk in <Map<String, Object?>>[
        {'kty': 'oct', 'k': 'AAAA'},
        {'kty': 'OKP', 'crv': 'Ed25519', 'x': 'AAAA'},
        {..._rfc9449Key, 'kty': 'ec'},
        {'kty': 'EC', 'crv': 'P-256', 'x': 'AAAA'},
        {..._rfc9449Key, 'x': 1},
        {'kty': 'RSA', 'n': 'AAAA'},
        const {},
      ]) {
        expect(
          () => JwkThumbprint.of(jwk),
          throwsFormatException,
          reason: '$jwk',
        );
      }
    });
  });

  group('DPoPProofClaims', () {
    test('RFC 9449 §4.1: the proof of a token request', () {
      final claims = DPoPProofClaims.fromJson(const {
        'jti': '-BwC3ESc6acc2lTc',
        'htm': 'POST',
        'htu': 'https://server.example.com/token',
        'iat': 1562262616,
      });
      expect(claims.jti, '-BwC3ESc6acc2lTc');
      expect(claims.htm, 'POST');
      expect(claims.htu, Uri.parse('https://server.example.com/token'));
      expect(
        claims.iat,
        DateTime.fromMillisecondsSinceEpoch(1562262616000, isUtc: true),
      );
      expect(claims.ath, isNull);
      expect(claims.nonce, isNull);
    });

    test('RFC 9449 §7.1: the proof of an API call, ath = SHA-256(token)', () {
      const json = {
        'jti': 'e1j3V_bKic8-LAEB',
        'htm': 'GET',
        'htu': 'https://resource.example.org/protectedresource',
        'iat': 1562262618,
        'ath': 'fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo',
      };
      final claims = DPoPProofClaims.fromJson(json);
      // The access token of RFC 9449 §7.1.
      expect(
        claims.ath,
        sha256Base64Url('Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU'),
      );
      expect(claims.toJson(), json);
    });

    test('toJson writes what the constructor got, iat in seconds', () {
      final claims = DPoPProofClaims(
        jti: 'id',
        htm: 'GET',
        htu: Uri.parse('https://api.example.com/orders?page=2#top'),
        iat: DateTime.fromMillisecondsSinceEpoch(1700000000999, isUtc: true),
        nonce: 'n-1',
      );
      expect(claims.toJson(), {
        'jti': 'id',
        'htm': 'GET',
        'htu': 'https://api.example.com/orders',
        'iat': 1700000000,
        'nonce': 'n-1',
      });
      expect(
        DPoPProofClaims.fromJson(claims.toJson()).toJson(),
        claims.toJson(),
      );
    });

    test('query and fragment of htu are dropped (RFC 9449 §4.3)', () {
      final claims = DPoPProofClaims.fromJson(const {
        'jti': 'a',
        'htm': 'GET',
        'htu': 'https://api.example.com/a?b=c#d',
        'iat': 1,
      });
      expect(claims.htu.toString(), 'https://api.example.com/a');
    });

    test('strict: missing, empty, null or mistyped claims are refused', () {
      const valid = <String, Object?>{
        'jti': 'a',
        'htm': 'GET',
        'htu': 'https://api.example.com/a',
        'iat': 1562262618,
      };
      expect(DPoPProofClaims.fromJson(valid).jti, 'a');
      final bad = <String, Map<String, Object?>>{
        'no jti': {...valid}..remove('jti'),
        'empty jti': {...valid, 'jti': ''},
        'numeric jti': {...valid, 'jti': 7},
        'no htm': {...valid}..remove('htm'),
        'list htm': {
          ...valid,
          'htm': ['GET'],
        },
        'no htu': {...valid}..remove('htu'),
        'relative htu': {...valid, 'htu': '/a'},
        'ftp htu': {...valid, 'htu': 'ftp://example.com/a'},
        'no host htu': {...valid, 'htu': 'https:///a'},
        'unparsable htu': {...valid, 'htu': 'https://[::1/a'},
        'no iat': {...valid}..remove('iat'),
        'string iat': {...valid, 'iat': '1562262618'},
        'infinite iat': {...valid, 'iat': double.infinity},
        'huge iat': {...valid, 'iat': 1e300},
        'numeric ath': {...valid, 'ath': 1},
        'null ath': {...valid, 'ath': null},
        'numeric nonce': {...valid, 'nonce': 1},
      };
      for (final MapEntry(key: name, value: json) in bad.entries) {
        expect(
          () => DPoPProofClaims.fromJson(json),
          throwsFormatException,
          reason: name,
        );
      }
    });

    test('toString shows neither jti nor ath', () {
      final claims = DPoPProofClaims(
        jti: 'secret-jti',
        htm: 'GET',
        htu: Uri.parse('https://api.example.com/'),
        iat: DateTime.utc(2026),
        ath: 'secret-ath',
      );
      expect('$claims', isNot(contains('secret')));
    });
  });

  test('TokenType.dpop is written DPoP, as in the Authorization header', () {
    expect(TokenType.dpop.value, 'DPoP');
    expect(TokenType.bearer.value, 'Bearer');
  });
}
