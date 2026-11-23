// Jackson's StreamReadConstraints in ObjectMapper: a JSON text nested
// deeper than 1000 levels (J2) or with a number of more than 1000 digits
// (J1) is refused before it is decoded; SecretNames masks the credentials
// of a URL value.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

void main() {
  final mapper = ObjectMapper(introspector: Introspector());

  test('nesting deeper than 1000 is refused (J2)', () {
    final deep = '${'[' * 1001}${']' * 1001}';
    expect(
      () => mapper.readValue<Object?>(deep),
      throwsA(isA<JsonMappingException>()),
    );
    expect(
      () => mapper.readTree('${'{"a":' * 1001}1${'}' * 1001}'),
      throwsA(isA<JsonMappingException>()),
    );
    final fine = '${'[' * 1000}${']' * 1000}';
    expect(mapper.readValue<Object?>(fine), isA<List<Object?>>());
    expect(
      mapper.readValue<Object?>('["${'[' * 5000}"]'),
      ['[' * 5000],
      reason: 'brackets inside a string do not count',
    );
    expect(mapper.readValue<Object?>(r'["\"[[["]'), ['"[[[']);
  });

  test('a number of more than 1000 digits is refused (J1)', () {
    expect(
      () => mapper.readValue<Object?>('1' * 1001),
      throwsA(isA<JsonMappingException>()),
    );
    expect(
      () => mapper.readValue<BigInt>('"${'9' * 100000}"'),
      throwsA(isA<JsonMappingException>()),
    );
    expect(
      mapper.readValue<BigInt>('"${'9' * 1000}"'),
      BigInt.parse('9' * 1000),
    );
    expect(mapper.readValue<Object?>('"${'1' * 5000}"'), '1' * 5000);
  });

  test('the credentials of a URL value are masked (S-03)', () {
    expect(
      SecretNames.maskedUrl('postgres://ada:pw@db:5432/x'),
      'postgres://ada:******@db:5432/x',
    );
    expect(
      SecretNames.maskedUrl('https://x.test/a?token=t&page=2'),
      'https://x.test/a?token=******&page=2',
    );
    expect(SecretNames.maskedUrl('https://x.test/a'), 'https://x.test/a');
    expect(SecretNames.maskedUrl('not a url'), 'not a url');
    expect(SecretNames.maskedUrl('ada:pw'), 'ada:pw');
  });
}
