import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

void main() {
  Jwt token(Map<String, Object?> claims) =>
      Jwt('a.b.c', headers: const {'alg': 'HS256'}, claims: claims);

  test('a NumericDate too large for a date is a malformed claim', () {
    for (final value in [1e20, -1e20, 9007199254740992, 8.65e12]) {
      expect(
        () => token({'exp': value}).expiresAt,
        throwsFormatException,
        reason: '$value',
      );
    }
    expect(token({'exp': 8.64e12}).expiresAt, isNotNull);
    expect(token({'exp': 1790000000.5}).expiresAt!.year, 2026);
  });

  test('such a token is refused by the timestamp check, not an error', () {
    for (final claims in [
      {'exp': 1e20},
      {'nbf': -1e20},
      {'exp': 9007199254740992},
    ]) {
      final result = JwtTimestampValidator().validate(token(claims));
      expect(result.hasErrors, isTrue, reason: '$claims');
    }
  });
}
