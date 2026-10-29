// In a web page the SecretTemplate refuses to keep secrets: a browser has
// no secure storage. Runs with `flutter test --platform chrome`; skipped on the VM.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

void main() {
  test('every call throws an UnsupportedError that says why', () {
    final secrets = SecretTemplate(InMemorySecretStore());
    final refused = throwsA(
      isA<UnsupportedError>().having(
        (e) => e.message,
        'message',
        contains('no secure storage'),
      ),
    );

    expect(() => secrets.write('pin', 'x'), refused);
    expect(() => secrets.read<String>('pin'), refused);
    expect(() => secrets.delete('pin'), refused);
    expect(secrets.keys, refused);
    expect(secrets.deleteAll, refused);
  });
}
