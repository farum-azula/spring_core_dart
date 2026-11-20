// SecretNames: the one rule for names whose values are masked, shared by
// the data starter's statement logging and the generated toString() of
// @ToString.
import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  group('SecretNames.looksSecret', () {
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
      'dbPwd',
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
      'signingKey',
      'encryptionKey',
      'userpasswd',
      'passphrase',
      'sslkeypassword',
      'credential',
      'dbcredentials',
      'pass_word',
      'key',
      'ssh.key',
      'tokens_per_page',
    ]) {
      test(
        '$name is secret',
        () => expect(SecretNames.looksSecret(name), isTrue),
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
      'pin',
      'pw',
      '',
    ]) {
      test(
        '$name is not',
        () => expect(SecretNames.looksSecret(name), isFalse),
      );
    }
  });

  test('the mask is six stars', () => expect(SecretNames.masked, '******'));
}
