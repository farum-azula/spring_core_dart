// How the debug tools write a value: a card's row masks the secrets of an
// address and of a map's keys; a starter adds kinds of its own, asked
// before the built-in ones; a caller asks for a shorter text, or for an
// object's own text.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Loaded {
  const _Loaded(this.value);

  final int value;

  @override
  String toString() => 'Loaded($value)';
}

final class _Plain {}

void main() {
  test('an address in a string or a Uri is masked, and the entries of a '
      'map whose key looks secret', () {
    const url = 'postgres://ada:pw@db/shop?sslpassword=s3c&page=2';
    expect(
      DebugValueText.shortOf(url),
      "'postgres://ada:******@db/shop?sslpassword=******&page=2'",
    );
    expect(
      DebugValueText.shortOf(Uri.parse('https://x.test/a?api_key=k&n=1')),
      'https://x.test/a?api_key=******&n=1',
    );
    final row = DebugValueText.row(
      'headers',
      {'Authorization': 'Bearer t0k', 'accept': 'json'},
      'fields',
    );
    final whole = row.more!();
    expect(whole, isNot(contains('t0k')));
    expect(whole, contains("'Authorization': ******"));
    expect(whole, contains("'accept': 'json'"));
    final long = DebugValueText.row('link', '$url&${'x' * 80}', 'fields');
    expect(long.more!(), isNot(contains('pw@')));
  });

  test('a shorter text, an object by its own text', () {
    expect(DebugValueText.shortOf('a' * 50, max: 10), "'aaaaaaaa…");
    expect(DebugValueText.shortOf(const _Loaded(3)), '_Loaded');
    expect(
      DebugValueText.shortOf(const _Loaded(3), objectText: true),
      'Loaded(3)',
    );
    expect(DebugValueText.shortOf(_Plain(), objectText: true), '_Plain');
    expect(
      DebugValueText.shortOf(
        StateError('line one\nline two'),
        objectText: true,
      ),
      'Bad state: line one line two',
    );
  });

  test("a starter's kinds come before the built-in ones while registered", () {
    final kinds = DebugValueKinds([
      DebugValueKind(
        (value) => value is _Loaded,
        (value) => 'loaded ${(value as _Loaded).value}',
      ),
    ]);
    DebugValueText.addKinds(kinds);
    addTearDown(() => DebugValueText.removeKinds(kinds));
    expect(DebugValueText.shortOf(const _Loaded(7)), 'loaded 7');
    DebugValueText.removeKinds(kinds);
    expect(DebugValueText.shortOf(const _Loaded(7)), '_Loaded');
  });
}
