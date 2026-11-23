// The expressions of the method security annotations: highlighting,
// completion, hovers, going to a parameter, and the checks.
import 'package:dart_spring_language_server/src/completion.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

String _source(String annotation, {String parameters = 'Order order'}) =>
    '''
import 'package:spring_security_core/spring_security_core.dart';

class Order {}

@Service()
class Orders {
  $annotation
  void cancel($parameters) {}
}
''';

void main() {
  late EditorFixture fixture;

  setUp(() => fixture = EditorFixture.create());
  tearDown(() => fixture.dispose());

  List<String> messages(String annotation, {String? parameters}) {
    final path = fixture.open(
      'lib/orders.dart',
      parameters == null
          ? _source(annotation)
          : _source(annotation, parameters: parameters),
    );
    return [for (final p in fixture.workspace.problems(path)) p.message];
  }

  List<String> labels(String text, String marker) {
    final path = fixture.open('lib/orders.dart', text);
    return [
      for (final item
          in fixture.workspace.completion(path, at(text, marker))?.items ??
              const <Completion>[])
        item.label,
    ];
  }

  group('the checks', () {
    for (final valid in [
      '''@PreAuthorize("hasRole('ADMIN')")''',
      '''@PreAuthorize("hasRole('ADMIN') or #order != null")''',
      '''@PreAuthorize("isAuthenticated() and principal.username == 'a'")''',
      '''@PreAuthorize("hasPermission(#p0, 'cancel')")''',
      '''@PreAuthorize("permitAll")''',
      '''@PreAuthorize("{'a', 'b'}.?[#this == 'a'].size() > 0")''',
      '''@PreAuthorize("authentication.authorities.![authority].size() > 0")''',
      '''@PreAuthorize("T(Math).max(1, 2) > 1")''',
      '''@PostAuthorize("returnObject == null")''',
      '''@PostFilter("filterObject.owner == principal.username")''',
    ]) {
      test('accepts $valid', () => expect(messages(valid), isEmpty));
    }

    for (final (annotation, message) in [
      ('''@PreAuthorize("hasRole('ADMIN'")''', 'SpEL:'),
      ('''@PreAuthorize("hasRoel('ADMIN')")''', "Did you mean 'hasRole'?"),
      ('@PreAuthorize("isAuthenticated")', "'isAuthenticated' is a method"),
      ('@PreAuthorize("principal()")', "'principal' is not a method"),
      ('@PreAuthorize("#ordr != null")', "Unknown variable '#ordr'"),
      ('@PreAuthorize("returnObject == null")', 'has no value'),
      ('@PostAuthorize("filterObject == null")', 'has no value'),
    ]) {
      test('reports $annotation', () {
        expect(messages(annotation), contains(contains(message)));
      });
    }

    test('reads the expression of a composed annotation', () {
      const text = '''
class AdminOnly extends PreAuthorize {
  const AdminOnly() : super("hasRoel('ADMIN')");
}
''';
      final path = fixture.open('lib/admin.dart', text);
      expect(
        [for (final p in fixture.workspace.problems(path)) p.message],
        contains(contains("Did you mean 'hasRole'?")),
      );
    });
  });

  group('completion', () {
    test('offers the functions, and what the annotation can read', () {
      const text = '''
@PreAuthorize("has")
void a() {}
@PostAuthorize("x")
void b() {}
''';
      expect(
        labels(text, '@PreAuthorize("has|'),
        allOf(contains('hasRole'), isNot(contains('returnObject'))),
      );
      expect(labels(text, '@PostAuthorize("x|'), contains('returnObject'));
    });

    test('offers the parameters after #', () {
      const text = '''
class Orders {
  @PreAuthorize("#")
  void a(Order order) {}
}
''';
      expect(labels(text, '"#|'), containsAll(['order', 'p0', 'root']));
    });

    test('offers the members of the user', () {
      const text = '''
@PreAuthorize("principal.")
void a() {}
@PreAuthorize("authentication.principal.")
void b() {}
@PreAuthorize("authentication.")
void c() {}
''';
      expect(labels(text, '"principal.|'), contains('username'));
      expect(labels(text, 'authentication.principal.|'), contains('username'));
      expect(labels(text, '"authentication.|'), contains('authorities'));
    });

    test('offers nothing inside a role name', () {
      const text = '''
@PreAuthorize("hasRole('AD')")
void a() {}
''';
      expect(labels(text, "'AD|"), isEmpty);
    });
  });

  test('a hover explains a function', () {
    final text = _source('''@PreAuthorize("hasRole('ADMIN')")''');
    final path = fixture.open('lib/orders.dart', text);
    expect(
      fixture.workspace.hover(path, at(text, 'hasR|ole')),
      contains('ROLE_'),
    );
  });

  test('a variable goes to its parameter', () {
    final text = _source('@PreAuthorize("#order != null")');
    final path = fixture.open('lib/orders.dart', text);
    expect(
      fixture.workspace.definition(path, at(text, '#ord|er')),
      hasLength(1),
    );
  });

  test('the expression is highlighted', () {
    final text = _source('''@PreAuthorize("hasRole('ADMIN')")''');
    final path = fixture.open('lib/orders.dart', text);
    final lines = text.split('\n');
    expect(
      [
        for (final token in fixture.workspace.semanticTokens(path))
          (
            lines[token.line].substring(
              token.column,
              token.column + token.length,
            ),
            token.type.legendName,
          ),
      ],
      containsAll([('hasRole', 'method'), ("'ADMIN'", 'string')]),
    );
  });
}
