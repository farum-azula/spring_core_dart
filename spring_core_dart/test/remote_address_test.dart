// RemoteAddress and RemoteAddressPolicy: every address of the
// configuration read one way (https, http, github:) and checked one way
// (insecure ones stop the start unless spring.remote.allow-insecure).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

RemoteAddress _at(String text) =>
    const RemoteAddresses().parse(text, property: 'p');

void main() {
  test('https, http and github: addresses', () {
    expect(
      _at('https://x.example/a.yml').uri.toString(),
      'https://x.example/a.yml',
    );
    expect(_at('https://x.example/a.yml').secure, isTrue);
    expect(_at('http://x.example/a.yml').secure, isFalse);
    expect(
      _at('github:farum-azula/themes/themes/code.yml@code-v1').uri.toString(),
      'https://raw.githubusercontent.com/farum-azula/themes/code-v1/themes/code.yml',
    );
    expect(
      _at('github:o/r/f.yml').uri.toString(),
      'https://raw.githubusercontent.com/o/r/HEAD/f.yml',
    );
  });

  test('anything else names the property', () {
    for (final text in [
      'ftp://x/a',
      'file:///a',
      'a.yml',
      'github:o/r',
      'https://',
    ]) {
      expect(
        () => const RemoteAddresses().parse(
          text,
          property: 'spring.flutter.theme.source',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'spring.flutter.theme.source',
          ),
        ),
        reason: text,
      );
    }
    expect(const RemoteAddresses().isAddress('github:o/r/f'), isTrue);
    expect(const RemoteAddresses().isAddress('assets/a.png'), isFalse);
  });

  test('insecure addresses stop the start by default, naming them', () {
    final insecure = const RemoteAddresses().parse(
      'http://themes.lan/a.yml',
      property: 'spring.flutter.theme.source',
    );
    expect(const RemoteAddressPolicy().check([_at('https://x/a')]), isEmpty);
    expect(
      () => const RemoteAddressPolicy().check([_at('https://x/a'), insecure]),
      throwsA(
        isA<InsecureConnectionException>()
            .having((e) => e.addresses, 'addresses', [insecure])
            .having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('not secure'),
                contains(
                  'http://themes.lan/a.yml (spring.flutter.theme.source)',
                ),
                contains('spring.remote.allow-insecure'),
              ),
            ),
      ),
    );
  });

  test('allowed: they are used, and a warning lists them', () {
    final records = <SpringLogRecord>[];
    final stop = SpringLog.listen(records.add);
    addTearDown(stop);
    final insecure = _at('http://themes.lan/a.yml');
    expect(
      const RemoteAddressPolicy(allowInsecure: true).check([insecure]),
      [insecure],
    );
    expect(
      records.map((r) => '${r.level.name} ${r.message}'),
      contains(
        allOf(
          startsWith('warning'),
          contains('spring.remote.allow-insecure'),
          contains('http://themes.lan/a.yml (p)'),
        ),
      ),
    );
  });

  test('the property', () {
    final environment = StandardEnvironment()
      ..propertySources.addFirst(
        const MapPropertySource('t', {'spring.remote.allow-insecure': 'true'}),
      );
    expect(RemoteAddressPolicy.of(environment).allowInsecure, isTrue);
    expect(
      RemoteAddressPolicy.of(StandardEnvironment()).allowInsecure,
      isFalse,
    );
  });

  test("the application's resolvers come first, in their order", () {
    const addresses = RemoteAddresses([
      _Cdn('cdn.b.example', 2),
      _Cdn('cdn.a.example', 1),
    ]);
    expect(
      addresses.parse('cdn:themes/ocean.yml', property: 'p').uri.toString(),
      'https://cdn.a.example/themes/ocean.yml',
    );
    expect(addresses.isAddress('cdn:x'), isTrue);
    expect(const RemoteAddresses().isAddress('cdn:x'), isFalse);
    expect(
      addresses.parse('github:o/r/f@v1', property: 'p').uri.host,
      'raw.githubusercontent.com',
    );
  });
}

final class _Cdn implements RemoteAddressResolver, Ordered {
  const _Cdn(this.host, this.order);

  final String host;

  @override
  final int order;

  @override
  bool supports(String text) => text.startsWith('cdn:');

  @override
  Uri resolve(String text, {required String property}) =>
      Uri.https(host, '/${text.substring('cdn:'.length)}');
}
