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
      // One word that contains a secret word.
      'sslpassword',
      'sslPassword',
      'dbpassword',
      'DBPASSWORD',
      'apitoken',
      'accesstoken',
      'clientsecret',
      'privatekey',
      'privateKey',
      'private-key',
      'private_key',
      'secretkey',
      'accesskey',
      'userpasswd',
      'passphrase',
      'sslkeypassword',
      'credential',
      'dbcredentials',
      'pass_word',
      'key',
      'ssh.key',
    ]) {
      test(
        '$name is secret',
        () => expect(LogValues.looksSecret(name), isTrue),
      );
    }
    for (final name in [
      'monkey',
      'tokenizer',
      'tokenizerName',
      'tokenise',
      'tokenization',
      'secretary',
      'secretaryName',
      'title',
      'keyboard',
      'keyword',
      'keywords',
      'turkey',
      'donkey',
      'hockey',
      'passenger',
      'passage',
      'compass',
      'year',
      'name',
      'sslmode',
      'currentSchema',
      'application_name',
      '',
    ]) {
      test('$name is not', () => expect(LogValues.looksSecret(name), isFalse));
    }
  });

  test(
    'a URL masks the query parameters whose names contain a secret word',
    () {
      final url = Uri.parse(
        'postgresql://u:p@h/db?sslpassword=a&apiToken=b&sslmode=require'
        '&keyword=c&tokenizer=d',
      );
      expect(
        ConnectionSettings.maskUrl(url),
        'postgresql://u@h/db?sslpassword=******&apiToken=******'
        '&sslmode=require&keyword=c&tokenizer=d',
      );
    },
  );

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
          Part('title'),
          Part('token'),
          Part('year', PartType.between),
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
