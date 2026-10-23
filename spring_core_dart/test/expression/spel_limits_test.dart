import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final parser = SpelExpressionParser();

Object? eval(String expression, [Object? root, EvaluationContext? context]) =>
    parser.parseExpression(expression).getValue(context, root);

Matcher spelError(SpelMessage code) => throwsA(
  isA<SpelEvaluationException>().having(
    (e) => e.messageCode,
    'messageCode',
    code,
  ),
);

Matcher parseError(SpelMessage code) => throwsA(
  isA<SpelParseException>().having((e) => e.messageCode, 'messageCode', code),
);

class Box {
  Object? value;
}

void main() {
  group('limits', () {
    test('integer power saturates like Java', () {
      expect(eval('2 ^ 10'), 1024);
      expect(eval('3 ^ 0'), 1);
      expect(eval('(-2) ^ 3'), -8);
      // (long) Math.pow(2, -1) is 0 in Java.
      expect(eval('2 ^ -1'), 0);
      expect(eval('2.0 ^ -1'), 0.5);
      expect(eval('1 ^ 2000000000'), 1);
      // Saturates at Long.MAX_VALUE / MIN_VALUE instead of wrapping.
      expect(eval('2 ^ 1000000000'), eval('T(Long).MAX_VALUE'));
      expect(eval('(-2) ^ 1000000001'), eval('T(Long).MIN_VALUE'));
      expect(eval('T(Long).MAX_VALUE > 0 and T(Long).MIN_VALUE < 0'), isTrue);
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

    test('patterns with nested quantifiers are rejected', () {
      expect(eval("'aaa' matches 'a+'"), isTrue);
      expect(eval("'abab' matches '(ab)+'"), isTrue);
      expect(eval("'abab' matches '(a|b)+'"), isTrue);
      expect(eval(r"'a1' matches '^[a-z]+\d*$'"), isTrue);
      // The shape of catastrophic backtracking: Dart's RegExp cannot be
      // interrupted, so these are refused up front.
      for (final flawed in [
        '(a+)+',
        '(a*)*',
        '(a+)*',
        '(a|aa)+',
        r'(\w+\s?)*',
        '(a{1,})+',
      ]) {
        expect(
          () => eval("'aaaaaaaaaaaaaaaaaaaaaaaaaaaaab' matches '$flawed'"),
          spelError(SpelMessage.flawedPattern),
          reason: flawed,
        );
      }
      expect(
        () => eval("'a' matches '(a+)+'"),
        throwsA(
          isA<SpelEvaluationException>().having(
            (e) => e.simpleMessage,
            'simpleMessage',
            "EL1073E: Failed to efficiently evaluate pattern '(a+)+': consider "
                'redesigning it',
          ),
        ),
      );
    });

    test('expression length', () {
      expect(
        SpelParserConfiguration.withDefaults().maximumExpressionLength,
        10000,
      );
      final longest = "'${'a' * 9998}'"; // 10 000 characters
      expect(parser.parseExpression(longest).getValue(), hasLength(9998));
      expect(
        () => parser.parseExpression('${longest}1'),
        parseError(SpelMessage.maxExpressionLengthExceeded),
      );
      final small = SpelExpressionParser(
        SpelParserConfiguration.builder().maximumExpressionLength(5).build(),
      );
      expect(small.parseExpression('1 + 1').getValue(), 2);
      expect(
        () => small.parseExpression('1 + 10'),
        throwsA(
          isA<SpelParseException>().having(
            (e) => e.message,
            'message',
            'Expression [1 + 10] @0: EL1079E: SpEL expression is too long, '
                "exceeding the threshold of '5' characters",
          ),
        ),
      );
    });

    test('nesting depth', () {
      expect(SpelParserConfiguration.withDefaults().maximumNestingDepth, 1000);
      final shallow = SpelExpressionParser(
        SpelParserConfiguration.builder().maximumNestingDepth(3).build(),
      );
      expect(shallow.parseExpression('(1)').getValue(), 1);
      expect(
        () => shallow.parseExpression('((((((1))))))'),
        parseError(SpelMessage.maxExpressionNestingDepthExceeded),
      );
      expect(
        () => shallow.parseExpression('{{{{{{1}}}}}}'),
        parseError(SpelMessage.maxExpressionNestingDepthExceeded),
      );
      expect(
        () => parser.parseExpression('${'(' * 1001}1${')' * 1001}'),
        throwsA(
          isA<SpelParseException>().having(
            (e) => e.simpleMessage,
            'simpleMessage',
            'EL1087E: SpEL expression nesting depth exceeds the threshold of '
                '1,000',
          ),
        ),
      );
    });

    test('operations per evaluation', () {
      expect(SpelParserConfiguration.withDefaults().maximumOperations, 10000);
      final limited = SpelExpressionParser(
        SpelParserConfiguration.builder().maximumOperations(100).build(),
      );
      final context = StandardEvaluationContext()
        ..setVariable('few', [1, 2, 3])
        ..setVariable('many', List.generate(1000, (i) => i));
      final small = limited.parseExpression('#few.![#this * 2]');
      expect(small.getValue(context), [2, 4, 6]);
      // The count starts afresh with every evaluation.
      expect(small.getValue(context), [2, 4, 6]);
      expect(
        () => limited.parseExpression('#many.![#this * 2]').getValue(context),
        throwsA(
          isA<SpelEvaluationException>()
              .having(
                (e) => e.messageCode,
                'messageCode',
                SpelMessage.maxOperationsExceeded,
              )
              .having(
                (e) => e.simpleMessage,
                'simpleMessage',
                'EL1085E: SpEL expression evaluation exceeded the threshold '
                    "of '100' operations",
              ),
        ),
      );
      // Selected elements count, tested ones do not.
      expect(
        () => limited.parseExpression('#many.?[#this >= 0]').getValue(context),
        spelError(SpelMessage.maxOperationsExceeded),
      );
      expect(
        limited.parseExpression('#many.?[#this > 998]').getValue(context),
        [999],
      );
    });

    test('parser configuration', () {
      final defaults = SpelParserConfiguration.withDefaults();
      expect(defaults.autoGrowNullReferences, isFalse);
      expect(defaults.autoGrowCollections, isFalse);
      expect(defaults.maximumAutoGrowSize, 256);
      expect(SpelExpressionParser().configuration, same(defaults));
      final configuration = SpelParserConfiguration.builder()
          .autoGrowCollections()
          .maximumAutoGrowSize(8)
          .maximumOperations(50)
          .build();
      expect(configuration.autoGrowCollections, isTrue);
      expect(configuration.maximumAutoGrowSize, 8);
      expect(configuration.maximumOperations, 50);
      expect(
        configuration.toString(),
        'SpelParserConfiguration(autoGrowNullReferences: false, '
        'autoGrowCollections: true, maximumAutoGrowSize: 8, '
        'maximumExpressionLength: 10000, maximumOperations: 50, '
        'maximumNestingDepth: 1000)',
      );
      final builder = SpelParserConfiguration.builder();
      expect(() => builder.maximumOperations(0), throwsArgumentError);
      expect(() => builder.maximumExpressionLength(-1), throwsArgumentError);
      expect(() => builder.maximumNestingDepth(0), throwsArgumentError);
      expect(() => builder.maximumAutoGrowSize(-1), throwsArgumentError);
      expect(builder.maximumAutoGrowSize(0).build().maximumAutoGrowSize, 0);
    });

    test('auto-grow collections', () {
      final growing = SpelExpressionParser(
        SpelParserConfiguration.builder()
            .autoGrowCollections()
            .maximumAutoGrowSize(4)
            .build(),
      );
      final root = {
        'list': <int?>[1],
        'ints': <int>[1],
      };
      growing.parseExpression('list[2]').setValue(null, root, 3);
      expect(root['list'], [1, null, 3]);
      expect(growing.parseExpression('list[3]').getValue(null, root), isNull);
      expect(root['list'], hasLength(4));
      expect(
        () => growing.parseExpression('list[4]').getValue(null, root),
        spelError(SpelMessage.unableToGrowCollection),
      );
      expect(
        () => growing.parseExpression('ints[2]').getValue(null, root),
        spelError(SpelMessage.unableToGrowCollectionUnknownElementType),
      );
      expect(
        () => parser.parseExpression('list[9]').getValue(null, root),
        throwsA(isA<SpelEvaluationException>()),
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
        spelError(SpelMessage.incorrectNumberOfArgumentsToFunction),
      );
      expect(
        () => eval('#boom()', null, context),
        spelError(SpelMessage.exceptionDuringFunctionCall),
      );
    });

    test('constructors: not callable vs throwing (unwrapped)', () {
      final context = StandardEvaluationContext()
        ..typeLocator = (StandardTypeLocator()
          ..registerType(
            SpelType.of<Box>(
              'Box',
              constructors: {'': () => throw StateError('no boxes')},
            ),
          ));
      // Like Spring, the constructor's own exception propagates as is.
      expect(() => eval('new Box()', null, context), throwsStateError);
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
