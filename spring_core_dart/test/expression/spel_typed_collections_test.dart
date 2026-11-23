import 'dart:collection';

import 'package:spring_core_dart/expression.dart';
import 'package:test/test.dart';

void main() {
  final parser = SpelExpressionParser();

  Object? eval(String text, Map<String, Object?> variables) {
    final context = StandardEvaluationContext();
    variables.forEach(context.setVariable);
    return parser.parseExpression(text).getValue(context);
  }

  Matcher failsWith(SpelMessage message) => throwsA(
    isA<SpelEvaluationException>().having(
      (error) => error.messageCode,
      'messageCode',
      message,
    ),
  );

  group('Set.union', () {
    test('of the same type keeps the element type', () {
      final result = eval('#a.union(#b)', {
        'a': <int>{1},
        'b': <int>{2},
      });
      expect(result, isA<Set<int>>());
      expect(result, {1, 2});
    });

    test('with a wider set whose elements fit keeps the element type', () {
      final result = eval('#a.union({9}.toSet())', {
        'a': <int>{1},
      });
      expect(result, isA<Set<int>>());
      expect(result, {1, 9});
    });

    test('with elements that do not fit gives a wider set', () {
      final a = <int>{1};
      final result = eval('#a.union(#o)', {
        'a': a,
        'o': <Object?>{'x', null},
      });
      expect(result, isNot(isA<Set<int>>()));
      expect(result, {1, 'x', null});
      expect(a, {1});
    });

    test('keeps the equality of the receiver', () {
      final key = <int>[1];
      final a = LinkedHashSet<Object>.identity()..add(key);
      final result = eval('#a.union(#o)', {
        'a': a,
        'o': <Object?>{
          <int>[1],
        },
      });
      expect(result, hasLength(2));
    });

    test('a sorted set refuses what it cannot compare', () {
      expect(
        () => eval('#a.union(#o)', {
          'a': SplayTreeSet<int>.of([1]),
          'o': <Object?>{'x'},
        }),
        failsWith(SpelMessage.exceptionDuringMethodInvocation),
      );
    });

    test('an argument that is no set is still method not found', () {
      expect(
        () => eval('#a.union(5)', {
          'a': <int>{1},
        }),
        failsWith(SpelMessage.methodNotFound),
      );
    });
  });

  group('intersection and difference take any set', () {
    test('as Dart declares them', () {
      final variables = {
        'a': <int>{1, 2},
        'o': <Object?>{2, 'x'},
      };
      expect(eval('#a.intersection(#o)', variables), {2});
      expect(eval('#a.difference(#o)', variables), {1});
    });
  });

  group('methods that store', () {
    test('take a wider collection whose elements fit', () {
      final list = <int>[1];
      final set = <int>{1};
      final map = <int, int>{1: 1};
      final variables = <String, Object?>{
        'l': list,
        's': set,
        'm': map,
        'o': <Object?, Object?>{2: 2},
      };
      expect(eval('#l.addAll({2, 3})', variables), isTrue);
      expect(eval('#s.addAll({2, 3})', variables), isTrue);
      eval('#m.putAll(#o)', variables);
      expect(list, [1, 2, 3]);
      expect(set, {1, 2, 3});
      expect(map, {1: 1, 2: 2});
    });

    final refused = <String, Map<String, Object?> Function()>{
      "#l.add('x')": () => {
        'l': <int>[1],
      },
      "#l.add(0, 'x')": () => {
        'l': <int>[1],
      },
      "#l.insert(0, 'x')": () => {
        'l': <int>[1],
      },
      "#l.set(0, 'x')": () => {
        'l': <int>[1],
      },
      "#l.addAll({2, 'x'})": () => {
        'l': <int>[1],
      },
      "#s.add('x')": () => {
        's': <int>{1},
      },
      "#s.addAll({2, 'x'})": () => {
        's': <int>{1},
      },
      "#m.put('x', 1)": () => {
        'm': <int, int>{1: 1},
      },
      "#m.put(1, 'x')": () => {
        'm': <int, int>{1: 1},
      },
      "#m.putIfAbsent('x', 1)": () => {
        'm': <int, int>{1: 1},
      },
      '#m.putAll(#o)': () => {
        'm': <int, int>{1: 1},
        'o': <Object?, Object?>{2: 2, 'x': 3},
      },
    };
    for (final MapEntry(key: text, value: variables) in refused.entries) {
      test('$text is refused and changes nothing', () {
        final values = variables();
        final target = values.values.first;
        final before = '$target';
        expect(
          () => eval(text, values),
          failsWith(SpelMessage.exceptionDuringMethodInvocation),
        );
        expect('$target', before);
      });
    }

    test('the error names the collection and the value', () {
      expect(
        () => eval("#l.add('x')", {
          'l': <int>[1],
        }),
        throwsA(
          isA<SpelEvaluationException>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('List<int>'), contains('String')),
          ),
        ),
      );
    });

    test('a value of a wrong kind for the index is method not found', () {
      expect(
        () => eval("#l.add('x', 1)", {
          'l': <int>[1],
        }),
        failsWith(SpelMessage.methodNotFound),
      );
    });
  });

  group('methods that only read take any value, as in Java', () {
    final variables = {
      'l': <int>[1],
      's': <int>{1},
      'm': <int, int>{1: 1},
    };
    <String, Object?>{
      "#l.contains('x')": false,
      "#l.indexOf('x')": -1,
      "#l.lastIndexOf('x')": -1,
      "#l.remove('x')": false,
      "#s.contains('x')": false,
      "#s.remove('x')": false,
      "#m.get('x')": null,
      "#m.containsKey('x')": false,
      "#m.containsValue('x')": false,
      "#m.getOrDefault('x', 'y')": 'y',
      "#m.remove('x')": null,
    }.forEach((text, expected) {
      test(text, () => expect(eval(text, variables), expected));
    });
  });
}
