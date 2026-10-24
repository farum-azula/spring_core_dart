// Runs on the VM and on node (`dart test -p node`): on the web an
// integral double is an `int` at run time, so these check that SpEL keeps
// track of real numbers (Java doubles) itself.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class _Price {
  double amount = 2;
  int count = 2;

  String label(String prefix) => '$prefix$count';
}

final _priceIntrospection = BeanIntrospection<_Price>(
  properties: [
    BeanProperty<_Price>(
      'amount',
      type: double,
      get: (p) => p.amount,
      set: (p, v) => p.amount = v! as double,
    ),
    BeanProperty<_Price>(
      'count',
      type: int,
      get: (p) => p.count,
      set: (p, v) => p.count = v! as int,
    ),
  ],
  methods: [
    BeanMethod<_Price>(
      'label',
      invoke: (p, a) => p.label(a[0]! as String),
      parameterTypes: [String],
    ),
  ],
);

void main() {
  final parser = SpelExpressionParser();
  Object? eval(String text, [Object? root]) =>
      parser.parseExpression(text).getValue(StandardEvaluationContext(root));

  setUpAll(() => BeanIntrospector.shared.register(_priceIntrospection));

  group('real numbers keep their kind (also on the web)', () {
    test('through selection', () {
      expect(eval('{2.0, 3.0}.?[#this > 1][0] / 4'), 0.5);
      expect(eval('{2.0, 3.0}.^[#this > 1] / 4'), 0.5);
      expect(eval(r'{2.0, 4.0}.$[#this > 1] / 8'), 0.5);
      expect(eval('{2.0, 3.0}.?[#this / 4 == 0.5]'), [2.0]);
      expect(eval("{a: 2.0}.?[true]['a'] / 4"), 0.5);
      // Integers stay integers.
      expect(eval('{2, 3}.?[#this > 1][0] / 4'), 0);
    });

    test('through projection', () {
      expect(eval('{2.0, 3.0}.![#this / 4]'), [0.5, 0.75]);
      expect(eval('{2.0}.![#this][0] / 4'), 0.5);
      expect(eval('{2, 3}.![#this * 1.0][0] / 4'), 0.5);
      expect(eval('{2, 3}.![#this][0] / 4'), 0);
    });

    test('through property access', () {
      expect(eval('{a: 2.0}.a / 4'), 0.5);
      expect(eval('{a: 2}.a / 4'), 0);
      expect(eval('amount / 4', _Price()), 0.5);
      expect(eval('count / 4', _Price()), 0);
      expect(eval("amount + ''", _Price()), '2.0');
    });

    test('new Double(2) and toString()', () {
      expect(eval('new Double(2) / 4'), 0.5);
      expect(eval('new Float(2) / 4'), 0.5);
      expect(eval('new java.lang.Double(2) / 4'), 0.5);
      expect(eval('new Integer(2) / 4'), 0);
      expect(eval('2.0.toString()'), '2.0');
      expect(eval('(1.0 + 1).toString()'), '2.0');
      expect(eval('2.toString()'), '2');
      expect(eval('{2.0}[0].toString()'), '2.0');
      expect(eval("'x' + 2.0"), 'x2.0');
    });

    test('literals out of the 64-bit range are rejected (EL1035E)', () {
      for (final text in ['99999999999999999999', '9223372036854775808']) {
        expect(
          () => parser.parseExpression(text),
          throwsA(
            isA<SpelParseException>().having(
              (e) => e.messageCode,
              'messageCode',
              SpelMessage.notAnInteger,
            ),
          ),
          reason: text,
        );
      }
      expect(
        () => parser.parseExpression('0x1FFFFFFFFFFFFFFFF'),
        throwsA(isA<SpelParseException>()),
      );
    });
  });

  group('Java equality of collections', () {
    test('{2.0} == {2} is false, like List.equals in Java', () {
      expect(eval('{2.0} == {2}'), isFalse);
      expect(eval('{2.0} != {2}'), isTrue);
      expect(eval('{2} == {2}'), isTrue);
      expect(eval('{2.0} == {2.0}'), isTrue);
      expect(eval('{a: 2.0} == {a: 2}'), isFalse);
      expect(eval('{a: 2.0} == {a: 2.0}'), isTrue);
      expect(eval('{{1}, {2.5}} == {{1}, {2.5}}'), isTrue);
      // Numbers themselves still compare by value (OpEQ).
      expect(eval('2.0 == 2'), isTrue);
    });
  });

  group('Java types', () {
    test('T(Objects)', () {
      expect(eval('T(Objects).isNull(null)'), isTrue);
      expect(eval('T(java.util.Objects).nonNull(1)'), isTrue);
      expect(eval("T(Objects).toString(null, 'none')"), 'none');
      expect(eval('T(Objects).toString(null)'), 'null');
      expect(eval("T(Objects).requireNonNullElse(null, 'x')"), 'x');
      expect(eval("T(Objects).equals('a', 'a')"), isTrue);
      expect(eval('T(Objects).hashCode(null)'), 0);
      expect(eval('T(Objects).hash(1, 2)'), Object.hashAll([1, 2]));
      expect(
        () => eval("T(Objects).requireNonNull(null, 'needed')"),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('T(System)', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      expect(
        eval('T(System).currentTimeMillis()'),
        greaterThanOrEqualTo(before),
      );
      expect(eval('T(java.lang.System).nanoTime()'), isA<int>());
      expect(eval("T(System).getProperty('user.name', 'dflt')"), 'dflt');
      expect(eval("T(System).getenv()"), isA<Map<String, String>>());
      expect(
        eval("T(System).getenv('SPRING_DART_SURELY_UNSET_VARIABLE')"),
        isNull,
      );
      expect(eval('T(System).lineSeparator()'), '\n');
    });

    test('StringBuilder', () {
      expect(
        eval("new StringBuilder('ab').append('c').append(1).toString()"),
        'abc1',
      );
      expect(eval('new java.lang.StringBuilder().length()'), 0);
      expect(eval('new StringBuilder(16).isEmpty()'), isTrue);
      expect(eval("new StringBuilder('abc').reverse().toString()"), 'cba');
      expect(eval("new StringBuilder('ac').insert(1, 'b').toString()"), 'abc');
      expect(eval("new StringBuilder('abc').deleteCharAt(1) + ''"), 'ac');
      expect(eval("new StringBuilder('abcd').delete(1, 3).toString()"), 'ad');
      expect(
        eval("new StringBuilder('abcd').replace(1, 3, 'X').toString()"),
        'aXd',
      );
      expect(eval("new StringBuilder('abc').charAt(2)"), 'c');
      expect(eval("new StringBuffer('x') instanceof T(StringBuilder)"), isTrue);
    });
  });

  test('a failed element write names the element type', () {
    final root = {
      'numbers': <int>[1, 2],
      'scores': <String, int>{'a': 1},
    };
    for (final text in ["numbers[0] = 'x'", "scores['a'] = 'x'"]) {
      expect(
        () => eval(text, root),
        throwsA(
          isA<SpelEvaluationException>()
              .having(
                (e) => e.messageCode,
                'messageCode',
                SpelMessage.typeConversionError,
              )
              .having((e) => e.inserts.last, 'target type', 'int'),
        ),
        reason: text,
      );
    }
  });

  group('@Introspected objects are read by default', () {
    test('StandardEvaluationContext', () {
      final price = _Price();
      expect(eval('count', price), 2);
      expect(eval("label('#')", price), '#2');
      parser
          .parseExpression('count')
          .setValue(StandardEvaluationContext(price), null, '7');
      expect(price.count, 7);
    });

    test('a user accessor still comes first', () {
      final context = StandardEvaluationContext(_Price())
        ..addPropertyAccessor(
          FunctionPropertyAccessor<_Price>(getters: {'count': (_) => 42}),
        );
      expect(parser.parseExpression('count').getValue(context), 42);
    });

    test('SimpleEvaluationContext', () {
      final readOnly = SimpleEvaluationContext.forReadOnlyDataBinding()
          .withRootObject(_Price())
          .build();
      expect(parser.parseExpression('count').getValue(readOnly), 2);
      expect(
        () => parser.parseExpression("label('#')").getValue(readOnly),
        throwsA(isA<SpelEvaluationException>()),
      );
      final withMethods = SimpleEvaluationContext.forReadWriteDataBinding()
          .withInstanceMethods()
          .withRootObject(_Price())
          .build();
      expect(parser.parseExpression("label('#')").getValue(withMethods), '#2');
    });
  });
}
