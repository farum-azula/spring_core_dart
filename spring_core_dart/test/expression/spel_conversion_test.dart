// Runs on the VM and the web (`dart test -p node`): the real-number cases
// matter where an integral double is an int at run time.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Point {
  Point(this.x);
  final double x;
}

Object? eval(String expression, [EvaluationContext? context]) =>
    SpelExpressionParser()
        .parseExpression(expression)
        .getValue(context ?? StandardEvaluationContext());

void main() {
  group('arguments are converted to the parameter types', () {
    test('registered functions (#half(3) with a double parameter)', () {
      final context = StandardEvaluationContext()
        ..registerFunction('half', (double value) => value / 2)
        ..registerFunction('twice', (int value) => value * 2)
        ..registerFunction('shout', (String text) => text.toUpperCase())
        ..registerFunction('negate', (bool value) => !value)
        ..registerFunction(
          'join',
          VarargsFunction(
            (String head, List<Object?> rest) => '$head:${rest.join(',')}',
            fixedArity: 1,
          ),
        );
      expect(eval('#half(3)', context), 1.5);
      expect(eval("#twice('21')", context), 42);
      expect(eval('#twice(2.0)', context), 4);
      expect(eval('#shout(12)', context), '12');
      expect(eval("#negate('true')", context), isFalse);
      expect(eval('#join(1, 2, 3)', context), '1:2,3');
    });

    test('String built-ins', () {
      expect(eval("'abc'.substring('1')"), 'bc');
      expect(eval("'abc'.substring(1, '2')"), 'b');
      expect(eval("'abc'.charAt(1.0)"), 'b');
      expect(eval("'ab'.repeat('2')"), 'abab');
    });

    test('List and Map built-ins', () {
      expect(eval("{1, 2, 3}.get('1')"), 2);
      expect(eval('{1, 2, 3}.subList(1.0, 2.0)'), [2]);
    });

    test('T() static methods', () {
      expect(eval("T(Math).max('1', 2)"), 2);
      expect(eval("T(Math).abs('-3')"), 3);
      expect(eval("T(Math).sqrt('4')"), 2.0);
    });

    test('constructors', () {
      final context = StandardEvaluationContext()
        ..typeLocator = (StandardTypeLocator()
          ..registerType(
            SpelType.of<Point>('Point', constructors: {'': Point.new}),
          ));
      expect((eval('new Point(2)', context)! as Point).x, 2.0);
      expect((eval("new Point('1.5')", context)! as Point).x, 1.5);
    });

    test('an argument that cannot be converted is a method not found', () {
      expect(
        () => eval("'abc'.substring('x')"),
        throwsA(
          isA<SpelEvaluationException>().having(
            (e) => e.messageCode,
            'messageCode',
            SpelMessage.methodNotFound,
          ),
        ),
      );
    });
  });

  test('booleans are comparable: false < true', () {
    expect(eval('true > false'), isTrue);
    expect(eval('false < true'), isTrue);
    expect(eval('true >= true'), isTrue);
    expect(eval('true < false'), isFalse);
    expect(eval('false <= false'), isTrue);
  });

  test('1 instanceof T(Long) is true (Dart has one int type)', () {
    expect(eval('1 instanceof T(Long)'), isTrue);
    expect(eval('1 instanceof T(Integer)'), isTrue);
  });

  test('T(Math).rint rounds ties to even, like Java', () {
    expect(eval('T(Math).rint(2.5)'), 2.0);
    expect(eval('T(Math).rint(3.5)'), 4.0);
    expect(eval('T(Math).rint(-2.5)'), -2.0);
    expect(eval('T(Math).rint(-3.5)'), -4.0);
    expect(eval('T(Math).rint(1.4)'), 1.0);
    expect(eval('T(Math).rint(1.6)'), 2.0);
    expect(eval('T(Math).rint(0.5)'), 0.0);
    expect((eval('T(Math).rint(-0.4)')! as double).isNegative, isTrue);
    expect(eval('T(Math).rint(1e300)'), 1e300);
    // A real result: divides as a double.
    expect(eval('T(Math).rint(2.5) / 4'), 0.5);
  });

  group('real literals inside inline collections stay real', () {
    test('lists', () {
      expect(eval('{1.0, 2.0}[0] / 2'), 0.5);
      expect(eval('{1, 2.0}[1] / 4'), 0.5);
      expect(eval('{1, 2}[1] / 4'), 0);
    });

    test('maps', () {
      expect(eval("{a: 3.0, b: 3}['a'] / 2"), 1.5);
      expect(eval("{a: 3.0, b: 3}['b'] / 2"), 1);
      expect(eval('{a: 3.0}[a] / 2'), 1.5);
    });

    test('arrays', () {
      expect(eval('new double[]{1, 2}[1] / 4'), 0.5);
      expect(eval('new Object[]{1.0, 2}[0] / 2'), 0.5);
      expect(eval('new int[]{4, 2}[0] / 8'), 0);
    });
  });
}
