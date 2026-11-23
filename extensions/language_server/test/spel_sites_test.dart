// The annotation arguments the framework evaluates as SpEL, and the members
// of real Dart types read in expressions.
import 'dart:io';

import 'package:dart_spring_language_server/src/completion.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

const _models = '''
class Person {
  final String name = '';
  String get email => '';
}

class Base {
  final String id = '';
  String describe() => id;
}

class Order extends Base {
  final String owner = '';
  final Person customer = Person();
  final List<Person> people = const [];
  static const limit = 3;
}

abstract class Shape {
  double get area;
}

class Circle implements Shape {
  @override
  double get area => 1;
  double get radius => 1;
}

class Box<T> {
  Box(this.value);
  final T value;
}

class Open extends Remote {
  final String here = '';
}

class const Point(final int x, final int y);
''';

String _service(String annotation, String signature) =>
    """
import 'models.dart';

class Orders {
  final String tenant = '';

  $annotation
  $signature
}
""";

void main() {
  late EditorFixture fixture;

  setUp(() {
    fixture = EditorFixture.create()..open('lib/models.dart', _models);
  });
  tearDown(() => fixture.dispose());

  List<String> problems(String text) {
    final path = fixture.open('lib/orders.dart', text);
    return [for (final p in fixture.workspace.problems(path)) p.message];
  }

  List<(String, String)> tokens(String text) {
    final path = fixture.open('lib/orders.dart', text);
    final lines = text.split('\n');
    return [
      for (final token in fixture.workspace.semanticTokens(path))
        (
          lines[token.line].substring(
            token.column,
            token.column + token.length,
          ),
          token.type.legendName,
        ),
    ];
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

  // The line of `lib/models.dart` a definition at [marker] leads to.
  String? definitionLine(String text, String marker) {
    final path = fixture.open('lib/orders.dart', text);
    final found = fixture.workspace.definition(path, at(text, marker));
    if (found.isEmpty) {
      return null;
    }
    expect(found.single.path, endsWith('models.dart'));
    return _models.split('\n')[found.single.startLine].trim();
  }

  group('the arguments evaluated as SpEL', () {
    for (final annotation in [
      "@SignedUrl('#{authentication.name}/a.png', expiresIn: Duration(minutes: 5))",
      "@Upload('#{authentication.name}/a.png')",
      "@Download('#{authentication.name}/a.png')",
      "@PublicUrl('#{authentication.name}/a.png')",
      "@StorageObject('#{authentication.name}/a.json')",
      "@DeleteObject('#{authentication.name}/a.json')",
      "@PostgresChanges(table: 't', filter: 'id=eq.#{authentication.name}')",
      "@RateLimiter('10/1m', key: '#{authentication.name}')",
    ]) {
      test('$annotation is highlighted and clean', () {
        final text = _service(annotation, 'Future<Uri> link();');
        expect(
          tokens(text),
          containsAll([
            ('#{', 'keyword'),
            ('authentication', 'property'),
            ('name', 'property'),
          ]),
        );
        expect(problems(text), isEmpty);
      });
    }

    test('the text around the expression is left a string', () {
      final found = tokens(
        _service("@SignedUrl('#{authentication.name}/a.png')", 'void a();'),
      );
      expect(found.where((t) => t.$1.contains('a.png')), isEmpty);
    });

    test('a template reads the parameters', () {
      final text = _service(
        "@Download('#{#order.owner}/{kind}.png')",
        'Future<Uri> a(Order order, String kind);',
      );
      expect(problems(text), isEmpty);
      expect(definitionLine(text, '#order.ow|ner'), contains('owner'));
    });

    test('a template reports an unknown variable and name', () {
      expect(
        problems(
          _service("@Download('#{#ordr}/a')", 'Future<Uri> a(Order order);'),
        ),
        contains(contains("Unknown variable '#ordr'")),
      );
      expect(
        problems(_service("@Download('#{authenticatoin.name}')", 'void a();')),
        contains(contains("Did you mean 'authentication'?")),
      );
    });

    test('a template has no return value, target or element', () {
      for (final name in ['returnObject', 'filterObject', 'this']) {
        expect(
          problems(_service("@Download('#{$name}')", 'void a();')),
          contains(contains("Unknown name '$name'")),
        );
      }
    });

    test("the realtime channel may use each method's parameters", () {
      const text = '''
@RealtimeChannel('room:#{#id}', presenceKey: '#{authentication.name}')
abstract interface class Rooms {
  Stream<int> a(String id);
}
''';
      expect(problems(text), isEmpty);
      expect(tokens(text), contains(('authentication', 'property')));
    });

    test('a rate limit key reads the request, not the security functions', () {
      for (final valid in [
        "#{request.headers['X-Api-Key']}",
        '#{headers.host}',
        'tenant-#{principal.name}',
        '#{address}',
        '#{path}',
        '#{method}',
      ]) {
        expect(
          problems(
            _service("@RateLimiter('1/1m', key: \"$valid\")", 'void a();'),
          ),
          isEmpty,
          reason: valid,
        );
      }
      expect(
        problems(
          _service("@RateLimiter('1/1m', key: '#{hasRole(1)}')", 'void a();'),
        ),
        contains(contains("Unknown name 'hasRole'")),
      );
      expect(
        problems(
          _service("@RateLimiter('1/1m', key: '#{#id}')", 'void a(int id);'),
        ),
        contains(contains("Unknown variable '#id'")),
      );
    });

    test('a plain rate limit key is not an expression', () {
      expect(
        problems(_service("@RateLimiter('1/1m', key: 'ip')", 'void a();')),
        isEmpty,
      );
    });

    test('completion in a template', () {
      const text = """
class A {
  @SignedUrl('#{authentication.}/a')
  void a();
  @RateLimiter('1/1m', key: '#{re}')
  void b();
}
""";
      expect(labels(text, '#{authentication.|'), contains('name'));
      expect(labels(text, '#{re|'), contains('request'));
    });

    test('a hover explains a name of the root', () {
      final text = _service(
        "@SignedUrl('#{authentication.name}')",
        'void a();',
      );
      final path = fixture.open('lib/orders.dart', text);
      expect(
        fixture.workspace.hover(path, at(text, '#{authent|ication')),
        contains('Authentication'),
      );
    });

    test('a composed annotation, by super(...) and by super.path', () {
      const text = """
class Mine extends SignedUrl {
  const Mine() : super('#{authenticatoin.name}/a');
}

class Forwarded extends SignedUrl {
  const Forwarded(super.path);
}

class A {
  @Forwarded('#{authenticatoin.name}/b')
  void a();
}
""";
      expect(
        problems(text)
            .where((m) => m.contains("Did you mean 'authentication'")),
        hasLength(2),
      );
    });

    test('PrincipalView and RouteSecurity.preAuthorize', () {
      const text = """
final view = PrincipalView(expression: "hasRole('ADMIN')", child: x);
final bad = PrincipalView(expression: "hasRoel('ADMIN')", child: x);
final route = RouteSecurity.preAuthorize('isAuthenticated()');
""";
      expect(
        tokens(text),
        containsAll([('hasRole', 'method'), ('isAuthenticated', 'method')]),
      );
      expect(problems(text), [contains("Did you mean 'hasRole'?")]);
    });

    test('@ConditionalOnExpression, with and without #{}', () {
      const text = r"""
@ConditionalOnExpression(r"${app.cache:true} and '${app.mode:eu}' == 'eu'")
class A {}
@ConditionalOnExpression("#{1 > 0}")
class B {}
@ConditionalOnExpression("1 >")
class C {}
""";
      final found = tokens(text);
      expect(found, containsAll([('and', 'operator'), ('==', 'operator')]));
      expect(found, isNot(contains(("'${r'${app.mode:eu}'}'", 'string'))));
      expect(problems(text), [startsWith('SpEL:')]);
    });

    test('a string of another argument stays plain', () {
      final text = _service(
        "@Upload('a.png', contentType: 'image/png')",
        'void a();',
      );
      expect(tokens(text).where((t) => t.$1.contains('image')), isEmpty);
    });
  });

  group('members of real types', () {
    for (final (annotation, signature, marker, line) in [
      (
        '''@PreAuthorize("hasRole('ADMIN') or #order.owner == authentication.name")''',
        'Future<String> cancel(Order order) async => "";',
        '#order.ow|ner',
        'final String owner',
      ),
      (
        '@PreAuthorize("#order.customer.name != null")',
        'void a(Order order) {}',
        'customer.na|me',
        'final String name',
      ),
      (
        '@PreAuthorize("#order?.customer?.email != null")',
        'void a(Order? order) {}',
        '?.ema|il',
        'String get email',
      ),
      (
        '@PreAuthorize("#p0.owner != null")',
        'void a(Order order) {}',
        '#p0.ow|ner',
        'final String owner',
      ),
      (
        '@PreAuthorize("#order.id != null")',
        'void a(Order order) {}',
        '#order.i|d',
        'final String id',
      ),
      (
        '@PreAuthorize("#order.describe().length() > 0")',
        'void a(Order order) {}',
        'descr|ibe',
        'String describe() => id;',
      ),
      (
        '@PostAuthorize("returnObject.owner != null")',
        'Future<Order?> a() async => null;',
        'returnObject.ow|ner',
        'final String owner',
      ),
      (
        '@PostFilter("filterObject.owner != null")',
        'Future<List<Order>> a() async => [];',
        'filterObject.ow|ner',
        'final String owner',
      ),
      (
        '@PreFilter("filterObject.owner != null")',
        'void a(List<Order> orders) {}',
        'filterObject.ow|ner',
        'final String owner',
      ),
      (
        '@PreFilter("filterObject.name != null", filterTarget: "people")',
        'void a(List<Order> orders, Set<Person> people) {}',
        'filterObject.na|me',
        'final String name',
      ),
      (
        '@PreAuthorize("#orders[0].owner != null")',
        'void a(List<Order> orders) {}',
        '[0].ow|ner',
        'final String owner',
      ),
      (
        '@PreAuthorize("#orders.?[owner != null].size() > 0")',
        'void a(List<Order> orders) {}',
        '?[ow|ner',
        'final String owner',
      ),
      (
        '@PreAuthorize("#orders.?[#this.owner != null].size() > 0")',
        'void a(List<Order> orders) {}',
        '#this.ow|ner',
        'final String owner',
      ),
      (
        '@PreAuthorize("#box.value.owner != null")',
        'void a(Box<Order> box) {}',
        'value.ow|ner',
        'final String owner',
      ),
      (
        '@PreAuthorize("#point.x > 0")',
        'void a(Point point) {}',
        '#point.|x',
        'class const Point(final int x, final int y);',
      ),
      (
        "@Cacheable(key: '#order.owner')",
        'String a(Order order) => "";',
        '#order.ow|ner',
        'final String owner',
      ),
      (
        "@CachePut(key: '#result.owner')",
        'Future<Order> a() async => Order();',
        '#result.ow|ner',
        'final String owner',
      ),
    ]) {
      test('$annotation goes to the member', () {
        final text = _service(annotation, signature);
        expect(definitionLine(text, marker), contains(line));
        expect(problems(text), isEmpty);
      });
    }

    test('this and #root.this are the bean', () {
      for (final expression in ['this.tenant', '#root.this.tenant']) {
        final text = _service(
          '@PreAuthorize("$expression != null")',
          'void a() {}',
        );
        final path = fixture.open('lib/orders.dart', text);
        final found = fixture.workspace.definition(
          path,
          at(text, '.tena|nt'),
        );
        expect(found.single.path, path);
        expect(text.split('\n')[found.single.startLine], contains('tenant'));
      }
    });

    test('a bean found in the source', () {
      const text = """
import 'models.dart';

@Service()
class Audit {
  final String level = '';
}

class Reader {
  @Value('#{@audit.level}')
  String? level;
  @Value('#{@audit.levle}')
  String? wrong;
}
""";
      final path = fixture.open('lib/orders.dart', text);
      expect(
        fixture.workspace
            .definition(path, at(text, '@audit.lev|el'))
            .single
            .path,
        path,
      );
      expect(
        [for (final p in fixture.workspace.problems(path)) p.message],
        contains(contains("Did you mean 'level'?")),
      );
    });

    test('a type through a relative export and a prefix', () {
      fixture.open('lib/barrel.dart', "export 'models.dart' show Order;\n");
      const text = """
import 'barrel.dart' as m;

class A {
  @PreAuthorize("#o.owner != null")
  void a(m.Order o) {}
}
""";
      expect(definitionLine(text, '#o.ow|ner'), contains('final String owner'));
    });

    test('a class of the same name that is not imported is not used', () {
      fixture.open('lib/other.dart', 'class Stranger { int a = 0; }\n');
      const text = '''
class A {
  @PreAuthorize("#s.b != null")
  void a(Stranger s) {}
}
''';
      expect(problems(text), isEmpty);
      expect(
        fixture.workspace.definition(
          fixture.app('lib/orders.dart'),
          at(text, '#s.|b'),
        ),
        isEmpty,
      );
    });

    test('the hover shows the type and where it comes from', () {
      final text = _service(
        '@PreAuthorize("#order.id != null")',
        'void a(Order order) {}',
      );
      final path = fixture.open('lib/orders.dart', text);
      final hover = fixture.workspace.hover(path, at(text, '#order.i|d'))!;
      expect(hover, allOf(contains('Order.id'), contains('String id')));
      expect(hover, contains('from `Base`'));
    });

    test('completion of members, inherited too, without static ones', () {
      final text = _service(
        '@PreAuthorize("#order.")',
        'void a(Order order) {}',
      );
      expect(
        labels(text, '#order.|'),
        allOf(
          containsAll(['owner', 'customer', 'id', 'describe']),
          isNot(contains('limit')),
        ),
      );
      final chained = _service(
        '@PreAuthorize("#order.customer.em")',
        'void a(Order order) {}',
      );
      expect(labels(chained, 'customer.em|'), contains('email'));
    });

    test('completion after returnObject and in a cache key', () {
      expect(
        labels(
          _service(
            '@PostAuthorize("returnObject.")',
            'Future<Order> a() async => Order();',
          ),
          'returnObject.|',
        ),
        contains('owner'),
      );
      expect(
        labels(
          _service(
            "@Cacheable(key: '#order.')",
            'String a(Order order) => "";',
          ),
          '#order.|',
        ),
        contains('owner'),
      );
    });

    test('an unknown member of a known type, with did you mean', () {
      final found = problems(
        _service(
          '@PreAuthorize("#order.ownr != null")',
          'void a(Order order) {}',
        ),
      );
      expect(found, [contains("Unknown member 'ownr' of Order")]);
      expect(found.single, contains("Did you mean 'owner'?"));
    });

    test('an unknown member in a chain', () {
      expect(
        problems(
          _service(
            '@PreAuthorize("#order.customer.nme != null")',
            'void a(Order order) {}',
          ),
        ),
        [contains("Unknown member 'nme' of Person")],
      );
    });

    for (final (why, expression, signature) in [
      ('dynamic', '#d.anything', 'void a(dynamic d) {}'),
      ('Object', '#d.anything', 'void a(Object d) {}'),
      ('no type', '#d.anything', 'void a(d) {}'),
      ('a type parameter', '#d.anything', 'void a<T>(T d) {}'),
      ('an unresolved type', '#d.anything', 'void a(Unknown d) {}'),
      ('a Map', '#d.anything', 'void a(Map<String, Order> d) {}'),
      ('a String', '#d.length()', 'void a(String d) {}'),
      ('a List', '#d.size()', 'void a(List<Order> d) {}'),
      ('a missing supertype', '#d.anything', 'void a(Open d) {}'),
      ('an abstract class', '#d.radius', 'void a(Shape d) {}'),
      ('a subclass member', '#d.radius', 'void a(Circle d) {}'),
      ('Object members', '#d.hashCode', 'void a(Order d) {}'),
      ('a static member', '#d.limit', 'void a(Order d) {}'),
      ('a projection', '#d.![owner].size()', 'void a(List<Order> d) {}'),
      (
        'a method argument',
        '#d.?[describe(owner) != null].size()',
        'void a(List<Order> d) {}',
      ),
      ('an inline map', '{owner: 1}.size()', 'void a(Order d) {}'),
      ('a type reference', 'T(Math).max(1, 2)', 'void a(Order d) {}'),
    ]) {
      test('nothing reported for $why', () {
        expect(
          problems(_service('@PreAuthorize("$expression != null")', signature)),
          isEmpty,
        );
      });
    }

    test('a cache annotation outside a method names no parameter', () {
      const text = '''
final operations = [const Cacheable('books', key: '#isbn')];

@Cacheable('books', key: '#isbn')
class Books {}
''';
      expect(problems(text), isEmpty);
    });

    test('a bean name two packages use is not checked against either', () {
      fixture.open(
        'lib/one.dart',
        '@Service()\nclass Shop { bool a() => true; }\n',
      );
      final other = '${fixture.root.path}/starter/lib/shop.dart';
      File(other)
        ..createSync(recursive: true)
        ..writeAsStringSync('@Service()\nclass Shop { bool b() => true; }\n');
      fixture.workspace
        ..setOverlay(other, '@Service()\nclass Shop { bool b() => true; }\n')
        ..refresh(force: true);
      expect(
        problems(_service('@PreAuthorize("@shop.b()")', 'void a() {}')),
        isEmpty,
      );
    });

    test('a query expression reads the parameter type', () {
      const text = """
import 'models.dart';

@Repository()
abstract interface class Orders extends CrudRepository<Order, int> {
  @Query('select * from orders where owner = :#{#order.owner}')
  Future<List<Order>> a(Order order);
}
""";
      final path = fixture.open('lib/orders.dart', text);
      final found = fixture.workspace.definition(
        path,
        at(text, '#order.ow|ner'),
      );
      expect(found.single.path, endsWith('models.dart'));
    });
  });
}
