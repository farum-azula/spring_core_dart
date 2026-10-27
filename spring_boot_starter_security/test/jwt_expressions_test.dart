// What method security expressions can read of a JWT principal
// (`principal.subject`, `principal.claims['scope']`, ...) and of a
// JwtAuthenticationToken (`tokenAttributes`, `token`), through the
// customizer the starter registers.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

final _jwt = Jwt(
  'secret.token.value',
  headers: const {'alg': 'RS256', 'kid': 'k1'},
  claims: const {
    'sub': 'ada',
    'iss': 'https://issuer.example',
    'aud': ['api', 'web'],
    'jti': 'id-1',
    'exp': 1700000000,
    'iat': 1699990000,
    'nbf': 1699990010,
    'tenant': 'acme',
  },
);

Object? _evaluate(String expression, Object root) {
  final context = StandardEvaluationContext(root);
  const JwtExpressionCustomizer().customize(context);
  return SpelExpressionParser().parseExpression(expression).getValue(context);
}

void main() {
  group('a Jwt', () {
    test('subject, issuer, id and audience', () {
      expect(_evaluate('subject', _jwt), 'ada');
      expect(_evaluate('issuer', _jwt), 'https://issuer.example');
      expect(_evaluate('id', _jwt), 'id-1');
      expect(_evaluate('audience', _jwt), ['api', 'web']);
    });

    test('claims and headers are maps', () {
      expect(_evaluate("claims['tenant']", _jwt), 'acme');
      expect(_evaluate("headers['kid']", _jwt), 'k1');
      expect(_evaluate("claims['missing']", _jwt), isNull);
    });

    test('times are UTC instants', () {
      expect(
        _evaluate('expiresAt', _jwt),
        DateTime.utc(2023, 11, 14, 22, 13, 20),
      );
      expect(
        _evaluate('issuedAt', _jwt),
        DateTime.utc(2023, 11, 14, 19, 26, 40),
      );
      expect(
        _evaluate('notBefore', _jwt),
        DateTime.utc(2023, 11, 14, 19, 26, 50),
      );
    });

    test('a comparison works on the claims', () {
      expect(
        _evaluate("subject == 'ada' and claims['tenant'] == 'acme'", _jwt),
        isTrue,
      );
      expect(_evaluate("subject == 'root'", _jwt), isFalse);
    });

    test('the token value is not a property', () {
      expect(() => _evaluate('tokenValue', _jwt), throwsA(anything));
    });
  });

  group('a JwtAuthenticationToken', () {
    final token = JwtAuthenticationToken(_jwt, const []);

    test('tokenAttributes are the claims', () {
      expect(_evaluate("tokenAttributes['tenant']", token), 'acme');
    });

    test('token is the Jwt', () {
      expect(_evaluate('token.subject', token), 'ada');
      expect(_evaluate('token', token), same(_jwt));
    });
  });
}
