// SecretTemplate: objects as JSON through the ObjectMapper, a namespace
// that keeps the app's keys away from the login's, and errors
// that never show a secret. The SecretStore's keys() and deleteAll() too.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

final class PinSettings {
  const PinSettings({required this.hash, required this.attempts});

  final String hash;
  final int attempts;
}

final class _PinSerializer extends JsonSerializer<PinSettings> {
  const _PinSerializer();

  @override
  Object? serialize(PinSettings value, ObjectMapper mapper) => {
    'hash': value.hash,
    'attempts': value.attempts,
  };
}

final class _PinDeserializer extends JsonDeserializer<PinSettings> {
  const _PinDeserializer();

  @override
  PinSettings deserialize(Object json, ObjectMapper mapper) {
    final map = json as Map<String, Object?>;
    return PinSettings(
      hash: map['hash']! as String,
      attempts: map['attempts']! as int,
    );
  }
}

void main() {
  late InMemorySecretStore store;
  late SecretTemplate secrets;

  setUp(() {
    store = InMemorySecretStore();
    secrets = SecretTemplate(
      store,
      objectMapper: ObjectMapper(
        serializers: const [_PinSerializer()],
        deserializers: const [_PinDeserializer()],
      ),
    );
  });

  test('writes an object as JSON under the namespace and reads it', () async {
    await secrets.write('pin', const PinSettings(hash: 'h1', attempts: 2));

    expect(await store.read('app.pin'), '{"hash":"h1","attempts":2}');
    final pin = await secrets.read<PinSettings>('pin');
    expect(pin?.hash, 'h1');
    expect(pin?.attempts, 2);
  });

  test('plain values and missing keys', () async {
    await secrets.write('api-key', 'k-123');
    expect(await secrets.read<String>('api-key'), 'k-123');
    expect(await secrets.read<String>('missing'), isNull);
  });

  test('delete, keys and deleteAll stay inside the namespace', () async {
    await store.write('oauth2.login', '{"user":"ada"}');
    await store.write('other.key', '"x"');
    await secrets.write('pin', const PinSettings(hash: 'h', attempts: 0));
    await secrets.write('api-key', 'k');

    expect(await secrets.keys(), {'pin', 'api-key'});

    await secrets.delete('pin');
    expect(await secrets.keys(), {'api-key'});

    await secrets.deleteAll();
    expect(await secrets.keys(), isEmpty);
    expect(await store.keys(), {'oauth2.login', 'other.key'});
  });

  test('two namespaces never see each other', () async {
    final other = SecretTemplate(store, namespace: 'vault');
    await secrets.write('pin', 'a');
    await other.write('pin', 'b');

    expect(await secrets.read<String>('pin'), 'a');
    expect(await other.read<String>('pin'), 'b');
    expect(await other.keys(), {'pin'});
  });

  test("the login's namespace and bad names are refused", () {
    expect(
      () => SecretTemplate(store, namespace: 'oauth2'),
      throwsArgumentError,
    );
    expect(() => SecretTemplate(store, namespace: ''), throwsArgumentError);
    expect(() => SecretTemplate(store, namespace: 'a.b'), throwsArgumentError);
    expect(() => secrets.write('', 'x'), throwsArgumentError);
  });

  test('errors come in the Future, never thrown by the call', () async {
    // Each call returns before failing, so `.catchError` and
    // `try { await ... }` see every error alike.
    final empty = secrets.write('', 'x');
    final deleted = secrets.delete('');
    final read = secrets.read<String>('');
    final unwritable = secrets.write('pin', Object());
    await expectLater(empty, throwsArgumentError);
    await expectLater(deleted, throwsArgumentError);
    await expectLater(read, throwsArgumentError);
    await expectLater(unwritable, throwsA(isA<JsonMappingException>()));
  });

  test('a value that does not fit is an error without the secret', () async {
    await store.write('app.pin', '{"hash":"s3cr3t","attempts":"many"}');

    await expectLater(
      secrets.read<int>('pin'),
      throwsA(
        isA<JsonMappingException>()
            .having((e) => '$e', 'text', contains('"pin"'))
            .having((e) => '$e', 'text', isNot(contains('s3cr3t')))
            .having((e) => e.cause, 'cause', isNull),
      ),
    );
  });

  group('InMemorySecretStore', () {
    test('keys and deleteAll', () async {
      await store.write('a', '1');
      await store.write('b', '2');
      expect(await store.keys(), {'a', 'b'});

      await store.deleteAll();
      expect(await store.keys(), isEmpty);
      expect(await store.read('a'), isNull);
    });
  });
}
