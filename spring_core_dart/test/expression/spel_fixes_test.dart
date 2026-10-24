import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import '../beans/support.dart';

class _Svc {
  Greeter? greeter;
  String process(Greeter greeter) => greeter.greet();
}

class _Matrix {
  final rows = [
    [1, 2],
    [3, 4],
  ];
}

class _RowAccessor implements IndexAccessor {
  @override
  bool canRead(EvaluationContext context, Object target, Object? index) =>
      target is _Matrix && index is int;

  @override
  Object? read(EvaluationContext context, Object target, Object? index) =>
      (target as _Matrix).rows[index! as int];

  @override
  bool canWrite(EvaluationContext context, Object target, Object? index) =>
      canRead(context, target, index);

  @override
  void write(
    EvaluationContext context,
    Object target,
    Object? index,
    Object? newValue,
  ) =>
      (target as _Matrix).rows[index! as int] = (newValue! as List).cast<int>();
}

void main() {
  final parser = SpelExpressionParser();
  Object? eval(String expression, [Object? root]) =>
      parser.parseExpression(expression).getValue(null, root);

  group('real numbers (the same on the VM and the web)', () {
    test('real literals and the values they flow into', () {
      expect(eval('7.0 / 2'), 3.5);
      expect(eval('7 / 2'), 3);
      expect(eval('7.0 / 2 * 2 / 4'), 1.75);
      expect(eval('(7.0 > 6 ? 7.0 : 1) / 2'), 3.5);
      expect(eval('(7.0 ?: 1) / 2'), 3.5);
      expect(eval('-(7.0) / 2'), -3.5);
      expect(eval('(#x = 7.0) / 2'), 3.5);
      expect(eval("'x' + 7.0"), 'x7.0');
    });

    test('T(Math) functions return doubles like Java', () {
      expect(eval('T(Math).sqrt(16) / 3'), closeTo(1.3333, 0.001));
      expect(eval('T(Math).floor(7.5) / 2'), 3.5);
      expect(eval('T(Math).abs(-7.0) / 2'), 3.5);
      expect(eval('T(Math).abs(-7) / 2'), 3);
      expect(eval('T(Math).max(7.0, 2) / 2'), 3.5);
      expect(eval('T(Double).valueOf("7") / 2'), 3.5);
      expect(eval('T(Math).round(2.5)'), 3);
    });
  });

  group('numeric edge cases', () {
    test('equality with Java double semantics', () {
      expect(eval('T(Double).NaN == T(Double).NaN'), isFalse);
      expect(eval('T(Double).NaN != T(Double).NaN'), isTrue);
      expect(eval('0.0 == -0.0'), isTrue);
      expect(eval('1 == 1.0'), isTrue);
      expect(eval('{1, {2, 3}} == {1, {2, 3}}'), isTrue);
      expect(eval('{a: {1}} == {a: {1}}'), isTrue);
      expect(eval('{1, 2} == {2, 1}'), isFalse);
    });

    test('integer division by zero fails the same way everywhere', () {
      expect(() => eval('1 / 0'), throwsUnsupportedError);
      expect(() => eval('1 % 0'), throwsUnsupportedError);
      expect(eval('1.0 / 0'), double.infinity);
    });

    test("single-character arithmetic: 'd' - 3", () {
      expect(eval("'d' - 3"), 'a');
      expect(() => eval("'ab' - 1"), throwsA(isA<SpelEvaluationException>()));
    });
  });

  group('selection and indexes', () {
    test('selection keeps the element type', () {
      final root = {
        'ints': [1, 2, 3],
        'set': {'a', 'bb'},
      };
      expect(eval('#root[ints].?[#this > 1]', root), isA<List<int>>());
      expect(eval("#root['set'].?[length() > 1]", root), ['bb']);
      expect(eval("#root['set'].?[length() > 1]", root), isA<List<String>>());
      expect(eval('#root[ints].^[#this > 5]', root), isNull);
      expect(eval(r'#root[ints].$[#this > 1]', root), 3);
    });

    test('indexes are evaluated against the root', () {
      final root = {
        'i': 1,
        'items': ['a', 'b'],
      };
      expect(eval("#root['items'][#root['i']]", root), 'b');
      expect(eval('{10, 20, 30}[i]', {'i': 2}), 30);
    });

    test('IndexAccessor', () {
      final context = StandardEvaluationContext(_Matrix())
        ..addIndexAccessor(_RowAccessor());
      expect(parser.parseExpression('#this[1]').getValue(context), [3, 4]);
      parser.parseExpression('#this[0]').setValue(context, null, [9, 9]);
      expect(parser.parseExpression('#this[0][1]').getValue(context), 9);
    });

    test('getValueType', () {
      expect(parser.parseExpression("'abc'.length()").getValueType(), int);
      expect(parser.parseExpression('null').getValueType(), isNull);
      expect(
        parser.parseExpression('a #{1}', ParserContext.template).getValueType(),
        String,
      );
    });
  });

  group('Java types and methods', () {
    test('types and arrays', () {
      expect(eval('T(java.lang.Integer).MAX_VALUE'), 2147483647);
      expect(eval('new Integer(5) + new Long("6")'), 11);
      expect(eval('new Double(1) / 2'), 0.5);
      expect(eval('new Boolean("TRUE")'), isTrue);
      expect(eval('new int[4]'), [0, 0, 0, 0]);
      expect(eval('new char[2]'), ['\u0000', '\u0000']);
      expect(
        eval("T(Character).isDigit('7') and !T(Character).isLetter('7')"),
        isTrue,
      );
      expect(eval("T(Character).toUpperCase('a')"), 'A');
      expect(eval("'a' instanceof T(Character)"), isTrue);
    });

    test('String.format and other String methods', () {
      expect(
        eval(
          "T(String).format('%s-%05d|%.2f|%x|%-3s|%n', 'a', 42, 3.14159, 255, 'b')",
        ),
        'a-00042|3.14|ff|b  |\n',
      );
      expect(eval("'%2\$s %1\$s'.formatted('a', 'b')"), 'b a');
      expect(
        eval(
          "T(String).format('%,d %+d %e %S %b %c %%', 1234567, 5, 12345.678, 'x', null, 65)",
        ),
        '1,234,567 +5 1.234568e+04 X false A %',
      );
      expect(eval("'é'.getBytes()"), [0xC3, 0xA9]);
      expect(eval("'ab'.chars()"), [97, 98]);
      expect(() => eval("T(String).format('%d', 'x')"), throwsFormatException);
    });

    test('List methods', () {
      expect(eval('{3, 1, 2}.removeAll({1})'), isTrue);
      final list = [3, 1, 2];
      parser.parseExpression('sort(null)').getValue(null, list);
      expect(list, [1, 2, 3]);
      expect(eval('{1, 2, 3}.retainAll({2})'), isTrue);
    });
  });

  test('introspected methods and properties accept subtypes', () {
    final values = <String, Object?>{};
    final context = AnnotationConfigApplicationContext([
      BeanModule(
        'test',
        [
          english(),
          BeanDefinition<_Svc>(name: 'svc', create: (_) => _Svc()),
          BeanDefinition<Holder>(
            name: 'holder',
            create: (r) {
              values['method'] = r.value<String>('#{svc.process(@english)}');
              values['property'] = r.value<Object>('#{svc.greeter = @english}');
              return Holder(English());
            },
          ),
        ],
        introspections: [
          BeanIntrospection<_Svc>(
            properties: [
              BeanProperty<_Svc>(
                'greeter',
                type: Greeter,
                get: (s) => s.greeter,
                set: (s, v) => s.greeter = v as Greeter?,
              ),
            ],
            methods: [
              BeanMethod<_Svc>(
                'process',
                invoke: (s, a) => s.process(a[0]! as Greeter),
                parameterTypes: [Greeter],
              ),
            ],
          ),
        ],
      ),
    ])..refresh();
    expect(values['method'], English().greet());
    expect(values['property'], isA<English>());
    expect(context.getBean<_Svc>().greeter, isA<English>());
    context.close();
  });
}
