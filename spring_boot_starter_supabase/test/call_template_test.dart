@Tags(['supabase'])
library;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

enum Kind { small, large }

void main() {
  final environment = StandardEnvironment()
    ..propertySources.addFirst(
      const MapPropertySource('test', {'app.folder': 'shared files'}),
    );
  final templates = CallTemplates(environment: environment);

  ProxyMethod method(List<String> parameters) => ProxyMethod(
    'get',
    returnType: const ClassType<String>(),
    parameters: [
      for (final name in parameters)
        BeanParameter(name, type: const ClassType<Object>()),
    ],
  );

  String expand(
    String text,
    Map<String, Object?> arguments, {
    TemplateEncoder encoder = const PathSegmentEncoder(),
  }) {
    final m = method(arguments.keys.toList());
    return templates
        .parse(text, method: m, encoder: encoder)
        .expand(m, arguments.values.toList());
  }

  test('fixed text, a property, a parameter and an expression', () {
    expect(
      expand(r'${app.folder}/{userId}/#{#kind.name}.png', {
        'userId': 'u 1',
        'kind': Kind.large,
      }),
      'shared%20files/u%201/large.png',
    );
  });

  test('a constant template says so', () {
    final m = method(const []);
    final template = templates.parse(
      'a/b.png',
      method: m,
      encoder: const PathSegmentEncoder(),
    );
    expect(template.isConstant, isTrue);
    expect(template.expand(m, const []), 'a/b.png');
  });

  test('an enum goes in by its name, a number as written', () {
    expect(
      expand('{kind}/{year}', {'kind': Kind.small, 'year': 2026}),
      'small/2026',
    );
  });

  test('the authentication of the caller is there, as in @PreAuthorize', () {
    final value = SecurityContextHolder.runWithContext(() {
      SecurityContextHolder.getContext().authentication =
          TestingAuthenticationToken('ada', null);
      return expand('#{authentication.name}/avatar.png', const {});
    });
    expect(value, 'ada/avatar.png');
  });

  test('nobody signed in: an expression on the user is refused', () {
    expect(
      () => SecurityContextHolder.runWithContext(
        () => expand('#{authentication.name}/avatar.png', const {}),
      ),
      throwsArgumentError,
    );
  });

  group('a value is one segment of a path', () {
    for (final value in ['../admin', '..', '.', 'a/b', r'a\b', '', 'a\nb']) {
      test('"$value" is refused', () {
        expect(() => expand('{id}/x', {'id': value}), throwsArgumentError);
        expect(
          () => expand('#{#id}/x', {'id': value}),
          throwsArgumentError,
        );
      });
    }

    test('null is refused', () {
      expect(() => expand('{id}/x', {'id': null}), throwsArgumentError);
    });

    test('what looks like an escape is data', () {
      expect(expand('{id}', {'id': '%2e%2e'}), '%252e%252e');
      expect(
        expand(
          '{id}',
          {'id': '%2e%2e'},
          encoder: const PathSegmentEncoder(encode: false),
        ),
        '%2e%2e',
      );
    });
  });

  test('fixed text with a ".." segment is refused when read', () {
    expect(() => expand('../x', const {}), throwsArgumentError);
  });

  test('a name takes anything but nothing and control characters', () {
    expect(
      expand('room:{id}', {'id': 'a/b c'}, encoder: const NameEncoder()),
      'room:a/b c',
    );
    expect(
      () => expand('room:{id}', {'id': ''}, encoder: const NameEncoder()),
      throwsArgumentError,
    );
  });

  group('what is wrong with a text is said when it is read', () {
    for (final (text, says) in [
      ('{other}/x', '{other} is not a parameter'),
      ('{id/x', 'never closed'),
      ('#{#id/x', 'never closed'),
      ('#{1 +}/x', 'is not an expression'),
      (r'${missing.key}/x', 'missing.key'),
    ]) {
      test(text, () {
        expect(
          () => templates.parse(
            text,
            method: method(['id']),
            encoder: const PathSegmentEncoder(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains(says),
            ),
          ),
        );
      });
    }
  });

  test('braces inside an expression belong to it', () {
    expect(expand("#{ {'a','b'}[1] }/x", const {}), 'b/x');
    expect(expand("#{'}'.length()}/x", const {}), '1/x');
  });
}
