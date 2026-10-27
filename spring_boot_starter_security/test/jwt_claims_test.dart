// The Jwt value and its claim validators on their own: how claims of other
// types read as text, lists and times, that the token never shows in
// toString, the error text of a failed check, and which validators the
// default sets run.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

Jwt _jwt(Map<String, Object?> claims) =>
    Jwt('secret.token.value', headers: const {'alg': 'RS256'}, claims: claims);

void main() {
  group('Jwt claims', () {
    test('jti is the id; absent means null', () {
      expect(_jwt({'jti': 'abc-1'}).id, 'abc-1');
      expect(_jwt({}).id, isNull);
    });

    test('a claim that is not text reads as its text', () {
      final jwt = _jwt({'n': 42, 'b': true, 'f': 1.5});
      expect(jwt.getClaimAsString('n'), '42');
      expect(jwt.getClaimAsString('b'), 'true');
      expect(jwt.getClaimAsString('f'), '1.5');
      expect(jwt.getClaimAsString('missing'), isNull);
    });

    test('a number as subject or issuer reads as text', () {
      final jwt = _jwt({'sub': 1234, 'iss': 7});
      expect(jwt.subject, '1234');
      expect(jwt.issuer, '7');
    });

    test('a list claim: every element as text; a single value is one', () {
      final jwt = _jwt({
        'list': ['a', 1, true],
        'one': 'a',
        'number': 5,
        'map': {'k': 'v'},
      });
      expect(jwt.getClaimAsStringList('list'), ['a', '1', 'true']);
      expect(jwt.getClaimAsStringList('one'), ['a']);
      expect(jwt.getClaimAsStringList('number'), ['5']);
      expect(jwt.getClaimAsStringList('map'), ['{k: v}']);
      expect(jwt.getClaimAsStringList('missing'), isNull);
    });

    test('aud is a list: from a string, a list, or empty without it', () {
      expect(_jwt({'aud': 'api'}).audience, ['api']);
      expect(
        _jwt({
          'aud': ['a', 'b'],
        }).audience,
        ['a', 'b'],
      );
      expect(_jwt({}).audience, isEmpty);
    });

    test('times are UTC instants from seconds, fractions rounded', () {
      final jwt = _jwt({'exp': 1700000000, 'nbf': 1700000000.5, 'iat': 0});
      expect(jwt.expiresAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(jwt.notBefore, DateTime.utc(2023, 11, 14, 22, 13, 20, 500));
      expect(jwt.issuedAt, DateTime.utc(1970));
      expect(jwt.issuedAt!.isUtc, isTrue);
      expect(_jwt({}).expiresAt, isNull);
    });

    test('a time that is not a finite number throws', () {
      for (final value in ['soon', double.nan, double.infinity, true]) {
        expect(
          () => _jwt({'exp': value}).expiresAt,
          throwsFormatException,
          reason: '$value',
        );
      }
      expect(_jwt({'exp': null}).expiresAt, isNull);
    });

    test('headers and claims cannot be changed afterwards', () {
      final claims = <String, Object?>{'sub': 'ada'};
      final jwt = _jwt(claims);
      claims['sub'] = 'root';
      expect(jwt.subject, 'ada');
      expect(() => jwt.claims['sub'] = 'root', throwsUnsupportedError);
      expect(() => jwt.headers['alg'] = 'none', throwsUnsupportedError);
    });

    test('hasClaim sees a claim whose value is null', () {
      final jwt = _jwt({'x': null});
      expect(jwt.hasClaim('x'), isTrue);
      expect(jwt.hasClaim('y'), isFalse);
    });

    test('toString never shows the token', () {
      final text = _jwt({
        'sub': 'ada',
        'iss': 'https://issuer.example',
        'exp': 1700000000,
      }).toString();
      expect(text, isNot(contains('secret.token.value')));
      expect(text, contains('[PROTECTED]'));
      expect(text, contains('subject=ada'));
      expect(text, contains('issuer=https://issuer.example'));
      expect(text, contains('2023-11-14 22:13:20.000Z'));
    });
  });

  group('OAuth2Error', () {
    test('toString names the code and the description', () {
      expect(
        const OAuth2Error('invalid_token', 'Jwt expired').toString(),
        '[invalid_token] Jwt expired',
      );
    });

    test('toString without a description ends after the code', () {
      expect(const OAuth2Error('invalid_token').toString(), '[invalid_token] ');
    });

    test('keeps the uri it was given', () {
      const error = OAuth2Error('e', 'd', 'https://x.example');
      expect(error.uri, 'https://x.example');
      expect(error.errorCode, 'e');
      expect(error.description, 'd');
    });
  });

  group('JwtClaimValidator', () {
    test('passes when the condition holds for the claim', () {
      final validator = JwtClaimValidator(
        'azp',
        (value) => value == 'web-client',
      );
      expect(
        validator.validate(_jwt({'azp': 'web-client'})).hasErrors,
        isFalse,
      );
    });

    test('fails with invalid_token naming the claim', () {
      final validator = JwtClaimValidator(
        'azp',
        (value) => value == 'web-client',
      );
      final result = validator.validate(_jwt({'azp': 'other'}));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.errorCode, 'invalid_token');
      expect(result.errors.single.description, 'The azp claim is not valid');
      expect(
        result.errors.single.uri,
        'https://tools.ietf.org/html/rfc6750#section-3.1',
      );
    });

    test('the condition sees null for an absent claim', () {
      Object? seen = 'untouched';
      final validator = JwtClaimValidator('azp', (value) {
        seen = value;
        return value != null;
      });
      expect(validator.validate(_jwt({})).hasErrors, isTrue);
      expect(seen, isNull);
    });

    test('is a decoder validator: a failing claim rejects the token', () {
      final delegating = DelegatingOAuth2TokenValidator<Jwt>([
        JwtClaimValidator('a', (v) => v == 1),
        JwtClaimValidator('b', (v) => v == 2),
      ]);
      final result = delegating.validate(_jwt({'a': 0, 'b': 0}));
      expect(result.errors.map((e) => e.description), [
        'The a claim is not valid',
        'The b claim is not valid',
      ]);
      expect(delegating.validate(_jwt({'a': 1, 'b': 2})).hasErrors, isFalse);
    });
  });

  group('JwtValidators', () {
    final soon = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;

    test('createDefault checks the times only', () {
      final validator = JwtValidators.createDefault();
      expect(
        validator.validate(_jwt({'exp': soon, 'iss': 'anyone'})).hasErrors,
        isFalse,
      );
      expect(validator.validate(_jwt({'exp': 1})).hasErrors, isTrue);
    });

    test('createDefaultWithIssuer accepts the issuer', () {
      final validator = JwtValidators.createDefaultWithIssuer(
        'https://i.example',
      );
      expect(
        validator
            .validate(_jwt({'exp': soon, 'iss': 'https://i.example'}))
            .hasErrors,
        isFalse,
      );
    });

    test('createDefaultWithIssuer refuses another or no issuer', () {
      final validator = JwtValidators.createDefaultWithIssuer(
        'https://i.example',
      );
      for (final iss in ['https://evil.example', 'https://i.example/', null]) {
        final result = validator.validate(_jwt({'exp': soon, 'iss': iss}));
        expect(result.errors.map((e) => e.description), [
          'The iss claim is not valid',
        ], reason: '$iss');
      }
    });

    test('createDefaultWithIssuer still checks the times', () {
      final validator = JwtValidators.createDefaultWithIssuer(
        'https://i.example',
      );
      final result = validator.validate(
        _jwt({'exp': 1, 'iss': 'https://evil.example'}),
      );
      expect(result.errors, hasLength(2));
      expect(result.errors.first.description, startsWith('Jwt expired at'));
    });
  });
}
