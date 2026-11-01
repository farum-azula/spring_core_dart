// SpelOperations are what the interpreter runs for an operator and what
// generated code calls instead of interpreting: each gives what the
// expression gives.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// The outcome of [body]: type and value, or the error.
String outcome(Object? Function() body) {
  try {
    final value = body();
    return '${value.runtimeType}|$value';
  } on SpelEvaluationException catch (error) {
    return 'spel|${error.messageCode.name}|${error.simpleMessage}';
  } on Object catch (error) {
    return 'dart|${error.runtimeType}|$error';
  }
}

String interpreted(String expression, Map<String, Object?> variables) =>
    outcome(() {
      final context = StandardEvaluationContext();
      variables.forEach(context.setVariable);
      return SpelExpressionParser()
          .parseExpression(expression)
          .getValue(context);
    });

const numbers = <num>[0, 1, -7, 3, 100, 2.5, -2.5, 0.0, 1e10, 2147483648];

void main() {
  group('numbers give what the operator gives', () {
    final operations = <String, num Function(num, num)>{
      '+': (l, r) => SpelOperations.numeric(Operation.add, l, r),
      '-': (l, r) => SpelOperations.numeric(Operation.subtract, l, r),
      '*': (l, r) => SpelOperations.numeric(Operation.multiply, l, r),
      '/': SpelOperations.divide,
      '%': SpelOperations.modulus,
      '^': SpelOperations.power,
    };
    for (final MapEntry(key: symbol, value: operation) in operations.entries) {
      test('#a $symbol #b', () {
        for (final l in numbers) {
          for (final r in numbers) {
            expect(
              outcome(() => operation(l, r)),
              interpreted('#a $symbol #b', {'a': l, 'b': r}),
              reason: '$l $symbol $r',
            );
          }
        }
      });
    }

    test('ints and reals have their own results', () {
      expect(SpelOperations.divideInts(7, 2), 3);
      expect(SpelOperations.divideInts(-7, 2), -3);
      expect(SpelOperations.modulusInts(-7, 3), -1);
      expect(SpelOperations.powerInts(2, -1), 0);
      expect(SpelOperations.powerInts(2, 100), greaterThan(2147483647));
      expect(SpelOperations.modulusReals(7.5, 2), 1.5);
      expect(SpelOperations.powerReals(2, 0.5), closeTo(1.41421, 1e-5));
    });

    test('an integer division by zero is an UnsupportedError', () {
      expect(() => SpelOperations.divideInts(1, 0), throwsUnsupportedError);
      expect(() => SpelOperations.modulusInts(1, 0), throwsUnsupportedError);
      expect(() => SpelOperations.divide(1, 0), throwsUnsupportedError);
      // `0.0` is an `int` on the web: only the flag makes it a real divisor.
      expect(
        SpelOperations.divide(1, 0.0, rightReal: true),
        double.infinity,
      );
    });

    test('a real operand that is an int at run time divides as a real', () {
      // 7.0 is an `int` on the web: the flag says it is real.
      expect(SpelOperations.divide(7, 2, leftReal: true), 3.5);
      expect(SpelOperations.divide(7, 2, rightReal: true), 3.5);
      expect(SpelOperations.modulus(7, 2, leftReal: true), 1.0);
      expect(SpelOperations.power(2, 3, rightReal: true), 8.0);
      expect(SpelOperations.doubleToString(7), '7.0');
      expect(SpelOperations.doubleToString(2.5), '2.5');
    });
  });

  group('text', () {
    test('concat converts the other side', () {
      for (final (l, r) in <(Object?, Object?)>[
        ('a', 'b'),
        ('a', 1),
        (1, 'a'),
        ('a', null),
        (null, 'a'),
        ('a', 1.5),
        ('a', true),
        ('a', [1, 2]),
        ([1, 2], 'a'),
      ]) {
        expect(
          outcome(() => SpelOperations.concat(l, r)),
          interpreted('#a + #b', {'a': l, 'b': r}),
          reason: '$l + $r',
        );
      }
    });

    test('a real number that is an int at run time prints as a double', () {
      expect(SpelOperations.concat('n=', 7, rightReal: true), 'n=7.0');
      expect(SpelOperations.concat(7, '=n', leftReal: true), '7.0=n');
    });

    test('a string beyond the limit fails like the interpreter', () {
      final long = 'x' * SpelLimits.maxConcatenatedStringLength;
      expect(
        outcome(() => SpelOperations.concat(long, 'y')),
        interpreted('#a + #b', {'a': long, 'b': 'y'}),
      );
      expect(
        () => SpelOperations.join(long, 'y'),
        throwsA(
          isA<SpelEvaluationException>().having(
            (e) => e.messageCode,
            'messageCode',
            SpelMessage.maxConcatenatedStringLengthExceeded,
          ),
        ),
      );
    });
  });

  group('logic', () {
    test('equals is the == of expressions', () {
      final values = <Object?>[
        1,
        1.0,
        2,
        'a',
        'b',
        null,
        true,
        false,
        [1, 2],
        [1, 2],
        [2, 1],
        {1, 2},
        {'k': 1},
        {'k': 1},
        const Duration(seconds: 1),
        DateTime.utc(2020),
        double.nan,
      ];
      for (final l in values) {
        for (final r in values) {
          expect(
            outcome(() => SpelOperations.equals(l, r)),
            interpreted('#a == #b', {'a': l, 'b': r}),
            reason: '$l == $r',
          );
        }
      }
    });

    test('compare is the order of expressions', () {
      final values = <Object?>[
        1,
        2.5,
        'a',
        'b',
        null,
        true,
        false,
        DateTime.utc(2020),
        [1],
        double.nan,
      ];
      for (final l in values) {
        for (final r in values) {
          expect(
            outcome(() => SpelOperations.compare(l, r) < 0),
            interpreted('#a < #b', {'a': l, 'b': r}),
            reason: '$l < $r',
          );
        }
      }
    });

    test('toBool converts like a condition', () {
      for (final value in <Object?>[
        true,
        false,
        'true',
        'false',
        'x',
        null,
        1,
      ]) {
        expect(
          outcome(() => SpelOperations.toBool(value)),
          interpreted('!!#a', {'a': value}),
          reason: '$value',
        );
      }
    });
  });

  group('indexing', () {
    test('listElement and stringElement fail like the interpreter', () {
      final list = ['a', 'b'];
      for (final index in [0, 1, 2, -1]) {
        expect(
          outcome(() => SpelOperations.listElement(list, index)),
          interpreted('#a[#i]', {'a': list, 'i': index}),
          reason: 'list[$index]',
        );
        expect(
          outcome(() => SpelOperations.stringElement('ab', index)),
          interpreted('#a[#i]', {'a': 'ab', 'i': index}),
          reason: "'ab'[$index]",
        );
      }
    });
  });
}
