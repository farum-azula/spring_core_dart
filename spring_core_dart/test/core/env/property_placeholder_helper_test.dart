import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/env/property_placeholder_helper.dart';
import 'package:test/test.dart';

void main() {
  final props = {
    'name': 'NEON',
    'greeting': r'Hello ${name}',
    'inner': 'name',
    'empty': '',
    'a': r'${b}',
    'b': r'${a}',
    'self': r'${self}',
    'deep': r'${greeting}!',
    'with:colon': 'colon',
  };
  String? resolve(String key) => props[key];
  final helper = PropertyPlaceholderHelper();
  String replace(String text) => helper.replacePlaceholders(text, resolve);

  test('simple, multiple and adjacent placeholders', () {
    expect(replace(r'${name}'), 'NEON');
    expect(replace(r'x ${name} y ${name}'), 'x NEON y NEON');
    expect(replace(r'${name}${name}'), 'NEONNEON');
    expect(replace('no placeholders'), 'no placeholders');
    expect(replace(r'${empty}'), '');
  });

  test('recursive values', () {
    expect(replace(r'${greeting}'), 'Hello NEON');
    expect(replace(r'${deep}'), 'Hello NEON!');
  });

  test('defaults, nested defaults and placeholders in keys', () {
    expect(replace(r'${missing:fallback}'), 'fallback');
    expect(replace(r'${missing:}'), '');
    expect(replace(r'${missing:${name}}'), 'NEON');
    expect(replace(r'${missing:${other:deep default}}'), 'deep default');
    expect(replace(r'${${inner}}'), 'NEON');
    expect(replace(r'${name:unused}'), 'NEON');
    expect(replace(r'${missing:a:b}'), 'a:b');
  });

  test('escapes keep prefix and separator literal', () {
    expect(replace(r'\${name}'), r'${name}');
    expect(replace(r'cost \${x} and ${name}'), r'cost ${x} and NEON');
    expect(replace(r'${with\:colon}'), 'colon');
    expect(replace(r'${missing\:key:dflt}'), 'dflt');
  });

  test('unbalanced text is kept', () {
    expect(replace(r'${name'), r'${name');
    expect(replace(r'a } b'), 'a } b');
  });

  test('braces inside values are honored', () {
    expect(replace(r'${missing:{json}}'), '{json}');
  });

  test('unresolvable placeholder throws with context', () {
    expect(
      () => replace(r'x ${nope}'),
      throwsA(
        isA<PlaceholderResolutionException>()
            .having((e) => e.placeholder, 'placeholder', 'nope')
            .having((e) => e.toString(), 'text', contains("'nope'")),
      ),
    );
  });

  test('nested unresolvable reports the chain', () {
    final e = _catch(
      () => helper.replacePlaceholders(
        r'${outer}',
        (key) => key == 'outer' ? r'${inner.missing}' : null,
      ),
    );
    expect(e.placeholder, 'inner.missing');
    expect(e.message, contains('<--'));
  });

  test('cycles are detected', () {
    expect(
      () => replace(r'${a}'),
      throwsA(
        isA<PlaceholderResolutionException>().having(
          (e) => e.reason,
          'reason',
          contains('Circular'),
        ),
      ),
    );
    expect(
      () => replace(r'${self}'),
      throwsA(isA<PlaceholderResolutionException>()),
    );
  });

  test('ignoreUnresolvablePlaceholders keeps them', () {
    final lenient = PropertyPlaceholderHelper(
      ignoreUnresolvablePlaceholders: true,
    );
    expect(
      lenient.replacePlaceholders(r'${nope} ${name} ${${inner}x}', resolve),
      r'${nope} NEON ${namex}',
    );
  });

  test('custom syntax, no separator, no escape', () {
    final custom = PropertyPlaceholderHelper(
      prefix: '@{',
      suffix: '}',
      valueSeparator: null,
      escapeCharacter: null,
    );
    expect(custom.replacePlaceholders('@{name}', resolve), 'NEON');
    expect(custom.replacePlaceholders('@{with:colon}', resolve), 'colon');
    expect(custom.replacePlaceholders(r'\@{name}', resolve), r'\NEON');

    final brackets = PropertyPlaceholderHelper(prefix: '%[', suffix: ']');
    expect(
      brackets.replacePlaceholders('%[name] %[x:[y]]', resolve),
      'NEON [y]',
    );

    final plain = PropertyPlaceholderHelper(prefix: '<<', suffix: '>>');
    expect(plain.replacePlaceholders('<<name>>', resolve), 'NEON');
  });
}

PlaceholderResolutionException _catch(void Function() body) {
  try {
    body();
  } on PlaceholderResolutionException catch (e) {
    return e;
  }
  fail('expected PlaceholderResolutionException');
}
