import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/src/log_values.dart';
import 'package:test/test.dart';

void main() {
  group('LogValues.looksSecret', () {
    for (final name in [
      'password',
      'passwordHash',
      'password_hash',
      'apiKey',
      'api_key',
      'apikey',
      'refreshToken',
      'refresh-token',
      'clientSecret',
      'CLIENT_SECRET',
      'pwd',
      'credentials',
    ]) {
      test(
        '$name is secret',
        () => expect(LogValues.looksSecret(name), isTrue),
      );
    }
    for (final name in ['monkey', 'tokenizer', 'title', 'keyboard', 'year']) {
      test('$name is not', () => expect(LogValues.looksSecret(name), isFalse));
    }
  });

  test('secret values are masked, others formatted', () {
    expect(
      LogValues.map({'title': 'Dune', 'password_hash': 'x', 'year': null}),
      '{title: "Dune", password_hash: ******, year: null}',
    );
    expect(
      LogValues.arguments(['login', 'password'], ['ada', 'hunter2', 3]),
      'login: "ada", password: ******, ?3: 3',
    );
  });

  test('line breaks and control characters cannot forge log lines', () {
    expect(
      LogValues.value('title', 'a\nINFO forged\u001b[2J'),
      '"a<EOL>INFO forged?[2J"',
    );
  });

  test('criteria arguments are named after their properties', () {
    final criteria = Criteria(
      [
        const OrPart([
          Part(['title'], PartType.simpleProperty),
          Part(['token'], PartType.simpleProperty),
          Part(['year'], PartType.between),
        ]),
      ],
      ['Dune', 'abc', 1960, 1970],
    );
    expect(
      LogValues.criteria(criteria),
      'title: "Dune", token: ******, year: 1960, year: 1970',
    );
  });
}
