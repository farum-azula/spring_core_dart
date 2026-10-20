import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final parser = SpelExpressionParser();

Object? eval(String expression, [Object? root, EvaluationContext? context]) =>
    parser.parseExpression(expression).getValue(context, root);

Matcher spelError(SpelMessage code) =>
    throwsA(isA<SpelEvaluationException>().having((e) => e.code, 'code', code));

class Box {
  Object? value;
}

void main() {
  group('limits', () {
    test('power uses exponentiation by squaring', () {
      expect(eval('2 ^ 10'), 1024);
      expect(eval('3 ^ 0'), 1);
      expect(eval('(-2) ^ 3'), -8);
      expect(eval('2 ^ -1'), 0.5);
      // Finishes instantly (wraps around like Java's long arithmetic).
      expect(eval('1 ^ 2000000000'), 1);
      expect(eval('2 ^ 1000000000'), isA<int>());
    });

    test('string repetition', () {
      expect(eval("'ab' * 3"), 'ababab');
      expect(eval("'a' * 256"), hasLength(SpelLimits.maxRepeatedTextSize));
      expect(
        () => eval("'ab' * 129"),
        spelError(SpelMessage.maxRepeatedTextSizeExceeded),
      );
      expect(
        () => eval("'ab' * -1"),
        spelError(SpelMessage.negativeRepeatedTextCount),
      );
    });

    test('string concatenation', () {
      final big = 'x' * SpelLimits.maxConcatenatedStringLength;
      final context = StandardEvaluationContext()..setVariable('big', big);
      expect(eval("#big + ''", null, context), hasLength(big.length));
      expect(
        () => eval("#big + 'y'", null, context),
        spelError(SpelMessage.maxConcatenatedStringLengthExceeded),
      );
    });

    test('regular expression length', () {
      final context = StandardEvaluationContext()
        ..setVariable('ok', 'a' * SpelLimits.maxRegexLength)
        ..setVariable('long', 'a' * (SpelLimits.maxRegexLength + 1));
      expect(eval("'a' matches #ok", null, context), isFalse);
      expect(
        () => eval("'a' matches #long", null, context),
        spelError(SpelMessage.maxRegexLengthExceeded),
      );
    });
  });

  group('error codes', () {
    test('functions: not callable vs throwing', () {
      final context = StandardEvaluationContext()
        ..registerFunction('twice', (int n) => n * 2)
        ..registerFunction('boom', () => throw StateError('boom'));
      expect(eval('#twice(2)', null, context), 4);
      expect(
        () => eval('#twice(1, 2)', null, context),
        spelError(SpelMessage.functionNotFound),
      );
      expect(
        () => eval('#boom()', null, context),
        spelError(SpelMessage.exceptionDuringFunctionCall),
      );
    });

    test('constructors: not callable vs throwing', () {
      final context = StandardEvaluationContext()
        ..typeLocator = (StandardTypeLocator()
          ..registerType(
            SpelType.of<Box>(
              'Box',
              constructors: {'': () => throw StateError('no boxes')},
            ),
          ));
      expect(
        () => eval('new Box()', null, context),
        spelError(SpelMessage.constructorInvocationProblem),
      );
      expect(
        () => eval('new Box(1)', null, context),
        spelError(SpelMessage.constructorNotFound),
      );
    });

    test('property writes that throw', () {
      final context = StandardEvaluationContext()
        ..addPropertyAccessor(
          FunctionPropertyAccessor<Box>(
            getters: {'value': (b) => b.value},
            setters: {'value': (b, v) => throw StateError('read-only')},
          ),
        );
      expect(
        () => parser.parseExpression('value').setValue(context, Box(), 1),
        spelError(SpelMessage.exceptionDuringPropertyWrite),
      );
    });

    test('typed and unmodifiable collections', () {
      final root = {
        'numbers': <int>[1, 2],
        'scores': <String, int>{'a': 1},
        'fixed': List<int>.unmodifiable([1]),
      };
      eval('numbers[0] = 5', root);
      expect(root['numbers'], [5, 2]);
      expect(
        () => eval("numbers[0] = 'x'", root),
        spelError(SpelMessage.typeConversionError),
      );
      expect(
        () => eval("scores['a'] = 'x'", root),
        spelError(SpelMessage.typeConversionError),
      );
      expect(
        () => eval('fixed[0] = 2', root),
        spelError(SpelMessage.notAssignable),
      );
    });

    test('between needs comparable bounds', () {
      expect(eval('3 between {1, 5}'), isTrue);
      expect(
        () => eval("3 between {'a', 5}"),
        spelError(SpelMessage.notComparable),
      );
    });
  });

  group('context customization', () {
    test('accessors and resolvers go before the defaults', () {
      final accessor = FunctionPropertyAccessor<Box>(getters: {});
      final resolver = FunctionMethodResolver<Box>({});
      final context = StandardEvaluationContext()
        ..addPropertyAccessor(accessor)
        ..addMethodResolver(resolver);
      expect(context.propertyAccessors.first, same(accessor));
      expect(context.methodResolvers.first, same(resolver));

      // Without defaults the new ones are appended.
      context.propertyAccessors.clear();
      context.methodResolvers.clear();
      context
        ..addPropertyAccessor(accessor)
        ..addMethodResolver(resolver);
      expect(context.propertyAccessors, [accessor]);
      expect(context.methodResolvers, [resolver]);
    });

    test('simple context asks custom resolvers before built-ins', () {
      final resolver = FunctionMethodResolver<String>({
        'toUpperCase': (s, args) => 'custom',
      });
      final context = SimpleEvaluationContext.forReadOnlyDataBinding()
          .withInstanceMethods()
          .withMethodResolvers([resolver])
          .build();
      expect(context.methodResolvers.first, same(resolver));
      expect(context.methodResolvers.last, isA<BuiltinMethodResolver>());
      expect(eval("'a'.toUpperCase()", null, context), 'custom');
    });
  });
}
