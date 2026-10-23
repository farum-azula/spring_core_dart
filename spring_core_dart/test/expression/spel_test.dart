import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Inventor {
  Inventor(this.name, this.birthYear, {this.inventions = const []});
  String name;
  int birthYear;
  List<String> inventions;
  Inventor? mentor;
}

final parser = SpelExpressionParser();

Object? eval(String expression, [Object? root, EvaluationContext? context]) =>
    parser.parseExpression(expression).getValue(context, root);

StandardEvaluationContext inventorContext([Object? root]) =>
    StandardEvaluationContext(root)
      ..addPropertyAccessor(
        FunctionPropertyAccessor<Inventor>(
          getters: {
            'name': (i) => i.name,
            'birthYear': (i) => i.birthYear,
            'inventions': (i) => i.inventions,
            'mentor': (i) => i.mentor,
          },
          setters: {
            'name': (i, v) => i.name = v! as String,
            'birthYear': (i, v) => i.birthYear = v! as int,
          },
        ),
      )
      ..addMethodResolver(
        FunctionMethodResolver<Inventor>({
          'greet': (i, args) => 'Hi ${args.first}, I am ${i.name}',
          'fail': (i, args) => throw StateError('broken'),
        }),
      );

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

void main() {
  group('literals', () {
    test('numbers, strings, booleans, null', () {
      expect(eval('42'), 42);
      expect(eval('42L'), 42);
      expect(eval('0x7F'), 127);
      expect(eval('0xFFL'), 255);
      expect(eval('3.14'), 3.14);
      expect(eval('1e3'), 1000.0);
      expect(eval('2.5E-1'), 0.25);
      expect(eval('1.5f'), 1.5);
      expect(eval('2d'), 2.0);
      expect(eval("'It''s'"), "It's");
      expect(eval('"say ""hi"""'), 'say "hi"');
      expect(eval('TRUE'), isTrue);
      expect(eval('false'), isFalse);
      expect(eval('null'), isNull);
      expect(eval('NULL'), isNull);
    });

    test('inline lists and maps', () {
      expect(eval('{1, 2, 3}'), [1, 2, 3]);
      expect(eval('{}'), isEmpty);
      expect(eval('{{1, 2}, {3}}'), [
        [1, 2],
        [3],
      ]);
      expect(eval("{name: 'Nikola', 'dob': 1856, 3: 'x'}"), {
        'name': 'Nikola',
        'dob': 1856,
        3: 'x',
      });
      expect(eval('{:}'), <Object?, Object?>{});
      expect(eval('{a: {b: 1}}'), {
        'a': {'b': 1},
      });
    });
  });

  group('operators', () {
    test('integer arithmetic like Spring', () {
      expect(eval('1 + 2 * 3'), 7);
      expect(eval('(1 + 2) * 3'), 9);
      expect(eval('7 / 2'), 3);
      expect(eval('7.0 / 2'), 3.5);
      expect(eval('7 div 2'), 3);
      expect(eval('-7 % 3'), -1);
      expect(eval('7 mod 3'), 1);
      expect(eval('7.5 % 2'), 1.5);
      expect(eval('2 ^ 10'), 1024);
      expect(eval('2 ^ -1'), 0, reason: '(long) Math.pow(2, -1) in Java');
      expect(eval('2.0 ^ 2'), 4.0);
      expect(eval('-5 + +3'), -2);
      expect(eval('10 - 2 - 3'), 5);
      expect(eval('1 / 0.0'), double.infinity);
      // Like Java's ArithmeticException, Dart's error propagates as is.
      expect(() => eval('1 / 0'), throwsA(isA<UnsupportedError>()));
      expect(() => eval('1 % 0'), throwsA(isA<UnsupportedError>()));
    });

    test('strings', () {
      expect(eval("'a' + 'b'"), 'ab');
      expect(eval("'n=' + 1"), 'n=1');
      expect(eval("1 + 'x'"), '1x');
      expect(eval("'a' + null"), 'anull');
      expect(eval("'ab' * 3"), 'ababab');
      expect(
        () => eval('true + 1'),
        spelError(SpelMessage.operatorNotSupportedBetweenTypes),
      );
      expect(
        () => eval("-'x'"),
        spelError(SpelMessage.operatorNotSupportedBetweenTypes),
      );
    });

    test('relational and equality', () {
      expect(eval('2 == 2.0'), isTrue);
      expect(eval('2 eq 3'), isFalse);
      expect(eval('2 != 3'), isTrue);
      expect(eval('2 ne 2'), isFalse);
      expect(eval('1 < 2'), isTrue);
      expect(eval('2 lt 1'), isFalse);
      expect(eval('2 <= 2'), isTrue);
      expect(eval('2 le 1'), isFalse);
      expect(eval('3 > 2'), isTrue);
      expect(eval('3 gt 4'), isFalse);
      expect(eval('3 >= 3'), isTrue);
      expect(eval('3 ge 4'), isFalse);
      expect(eval("'abc' < 'abd'"), isTrue);
      expect(eval('null < 1'), isTrue);
      expect(eval('1 > null'), isTrue);
      expect(eval('null == null'), isTrue);
      expect(eval("'a' == 'a'"), isTrue);
      expect(eval("'a' == 1"), isFalse);
      expect(() => eval("'a' < 1"), spelError(SpelMessage.notComparable));
    });

    test('logical operators short-circuit', () {
      expect(eval('true and false'), isFalse);
      expect(eval('true && true'), isTrue);
      expect(eval('false or true'), isTrue);
      expect(eval('false || false'), isFalse);
      expect(eval('!true'), isFalse);
      expect(eval('not false'), isTrue);
      expect(eval('false and nothing.here'), isFalse);
      expect(eval('true or nothing.here'), isTrue);
      expect(eval("'true' and true"), isTrue, reason: 'converted');
      expect(
        () => eval('1 and true'),
        spelError(SpelMessage.typeConversionError),
      );
      expect(
        () => eval('null or true'),
        spelError(SpelMessage.typeConversionError),
      );
    });

    test('ternary, Elvis, matches, between, instanceof', () {
      expect(eval("1 > 2 ? 'a' : 'b'"), 'b');
      expect(eval("true ? 1 : 2"), 1);
      expect(eval("null ?: 'Unknown'"), 'Unknown');
      expect(eval("'' ?: 'empty'"), 'empty');
      expect(eval("'x' ?: 'y'"), 'x');
      expect(eval("'5.00' matches '^-?\\d+(\\.\\d{2})?\$'"), isTrue);
      expect(eval("'abc' matches 'b'"), isFalse, reason: 'full match');
      expect(
        () => eval("'a' matches '('"),
        spelError(SpelMessage.invalidPattern),
      );
      expect(
        () => eval("1 matches 'a'"),
        spelError(SpelMessage.invalidFirstOperandForMatchesOperator),
      );
      expect(eval('3 between {1, 5}'), isTrue);
      expect(eval("'d' between {'a', 'c'}"), isFalse);
      expect(
        () => eval('3 between {1}'),
        spelError(SpelMessage.betweenRightOperandMustBeTwoElementList),
      );
      expect(eval("'xyz' instanceof T(String)"), isTrue);
      expect(eval('1 instanceof T(String)'), isFalse);
      expect(eval('1 instanceof T(num)'), isTrue);
      expect(
        () => eval("1 instanceof 'x'"),
        spelError(SpelMessage.instanceofOperatorNeedsClassOperand),
      );
      expect(
        () => eval('1 ? 2 : 3'),
        spelError(SpelMessage.typeConversionError),
      );
    });

    test('operator overloading', () {
      final context = StandardEvaluationContext()
        ..operatorOverloader = _ListConcat();
      expect(eval('{1} + {2}', null, context), [1, 2]);
      expect(
        () => eval('{1} - {2}', null, context),
        spelError(SpelMessage.operatorNotSupportedBetweenTypes),
      );
    });
  });

  group('properties, indexing, navigation', () {
    final tesla = Inventor(
      'Nikola Tesla',
      1856,
      inventions: ['induction motor', 'AC'],
    )..mentor = Inventor('Edison', 1847);

    test('property chains and methods on the root', () {
      final context = inventorContext(tesla);
      expect(eval('name', null, context), 'Nikola Tesla');
      expect(eval('name.length', null, context), 12);
      expect(eval('mentor.name.toUpperCase()', null, context), 'EDISON');
      expect(eval('inventions[1]', null, context), 'AC');
      expect(eval("greet('Ada')", null, context), 'Hi Ada, I am Nikola Tesla');
      expect(eval('#root.birthYear + 1', null, context), 1857);
      expect(eval('#this.name.substring(0, 6)', null, context), 'Nikola');
    });

    test('safe navigation short-circuits the chain, like Spring 6.2', () {
      final orphan = Inventor('Alone', 1900);
      final context = inventorContext(orphan);
      expect(eval('mentor?.name', null, context), isNull);
      expect(eval('mentor?.name?.length', null, context), isNull);
      // A null before `?.` ends the whole chain: `.length`, `.greet()` and
      // the index are not evaluated.
      expect(eval('mentor?.name.length', null, context), isNull);
      expect(eval('mentor?.name.length()', null, context), isNull);
      expect(eval('mentor?.greet(1).length', null, context), isNull);
      expect(eval('mentor?.inventions[0].length', null, context), isNull);
      expect(eval('mentor?.greet(1)', null, context), isNull);
      expect(eval('mentor?.[0]', null, context), isNull);
      expect(eval('mentor?.?[true]', null, context), isNull);
      expect(eval('mentor?.![#this]', null, context), isNull);
      expect(eval('mentor?.^[true].name', null, context), isNull);
      expect(eval(r'mentor?.$[true].name', null, context), isNull);
      // Only a null *before* `?.` short-circuits: a null result of `?.`
      // does not protect the next step.
      final root = {
        'a': {'b': null},
      };
      expect(eval('a?.b', root), isNull);
      expect(
        () => eval('a?.b.c', root),
        spelError(SpelMessage.propertyOrFieldNotReadableOnNull),
      );
      // Non-null chains are unaffected, and so are assignments.
      orphan.mentor = Inventor('Mentor', 1850, inventions: ['bulb']);
      expect(eval('mentor?.name.length', null, context), 6);
      expect(eval('mentor?.inventions[0].length', null, context), 4);
      expect(eval('mentor?.inventions.![#this.length]', null, context), [4]);
      parser.parseExpression('mentor?.name').setValue(context, null, 'Mia');
      expect(orphan.mentor!.name, 'Mia');
      orphan.mentor = null;
      // Assignment through a short-circuited chain is a no-op.
      parser.parseExpression('mentor?.name').setValue(context, null, 'x');
      parser.parseExpression('mentor?.name.length').setValue(context, null, 1);
      expect(
        () => eval('mentor.name', null, context),
        spelError(SpelMessage.propertyOrFieldNotReadableOnNull),
      );
      expect(
        () => eval('mentor.greet(1)', null, context),
        spelError(SpelMessage.methodCallOnNullObjectNotAllowed),
      );
      expect(
        () => eval('mentor[0]', null, context),
        spelError(SpelMessage.cannotIndexIntoNullValue),
      );
    });

    test('maps, lists, strings and iterables', () {
      final root = {
        'list': [10, 20, 30],
        'map': {'a': 1, 'b c': 2},
        'text': 'hello',
        'set': {7, 8},
      };
      expect(eval('list[0]', root), 10);
      expect(eval("list['2']", root), 30);
      expect(eval('list[1.0]', root), 20);
      expect(eval("map['b c']", root), 2);
      expect(eval('map.a', root), 1);
      expect(
        eval('map[missing]', root),
        isNull,
        reason: 'missing variable → null key',
      );
      expect(eval('text[1]', root), 'e');
      expect(eval('set[1]', root), 8);
      expect(eval('list.size()', root), 3);
      expect(eval('map.keys', root), ['a', 'b c']);
      expect(
        () => eval('list[5]', root),
        spelError(SpelMessage.collectionIndexOutOfBounds),
      );
      expect(
        () => eval('text[9]', root),
        spelError(SpelMessage.stringIndexOutOfBounds),
      );
      expect(
        () => eval('set[9]', root),
        spelError(SpelMessage.collectionIndexOutOfBounds),
      );
      expect(
        () => eval('list[-1]', root),
        spelError(SpelMessage.collectionIndexOutOfBounds),
      );
      expect(
        () => eval("list['x']", root),
        spelError(SpelMessage.typeConversionError),
      );
      expect(
        () => eval('list[1.5]', root),
        spelError(SpelMessage.typeConversionError),
      );
      expect(
        () => eval('5[0]'),
        spelError(SpelMessage.indexingNotSupportedForType),
      );
      expect(
        () => eval('nope', root),
        spelError(SpelMessage.propertyOrFieldNotReadable),
      );
      expect(
        () => eval('list.nope()', root),
        spelError(SpelMessage.methodNotFound),
      );
    });

    test('string index on plain objects reads properties', () {
      final context = inventorContext(tesla);
      expect(eval("['name']", null, context), 'Nikola Tesla');
    });

    test('accessor failures are wrapped, method exceptions are not', () {
      final context = inventorContext(tesla)
        ..addPropertyAccessor(
          FunctionPropertyAccessor<Inventor>(
            getters: {'bad': (_) => throw StateError('x')},
          ),
        );
      expect(
        () => eval('bad', null, context),
        spelError(SpelMessage.exceptionDuringPropertyRead),
      );
      // Like Spring, an exception thrown by the method itself propagates.
      expect(() => eval('fail()', null, context), throwsStateError);
    });
  });

  group('selection and projection', () {
    final root = {
      'numbers': [1, 2, 3, 4, 5],
      'members': {'a': 1, 'b': 2, 'c': 3},
      'set': {1, 2, 3},
    };

    test('lists and sets', () {
      expect(eval('numbers.?[#this > 2]', root), [3, 4, 5]);
      expect(eval('numbers.^[#this > 2]', root), 3);
      expect(eval(r'numbers.$[#this > 2]', root), 5);
      expect(eval('numbers.^[#this > 9]', root), isNull);
      expect(eval('numbers.![#this * 10]', root), [10, 20, 30, 40, 50]);
      expect(eval('set.?[#this != 2]', root), {1, 3});
      expect(eval('{1,2,3,4}.?[#this > 2]'), [3, 4]);
    });

    test('maps select entries and project values', () {
      expect(eval('members.?[value > 1]', root), {'b': 2, 'c': 3});
      expect(eval('members.^[value > 1]', root), {'b': 2});
      expect(eval(r'members.$[value > 1]', root), {'c': 3});
      // Like Spring, no match is null (not an empty map).
      expect(eval(r'members.$[value > 9]', root), isNull);
      expect(eval('members.^[value > 9]', root), isNull);
      expect(eval('members.![key + value]', root), ['a1', 'b2', 'c3']);
    });

    test('safe variants and errors', () {
      final context = StandardEvaluationContext({
        'none': null,
        'list': [1, 2],
      });
      expect(eval('none?.?[#this > 1]', null, context), isNull);
      expect(eval('none?.![#this]', null, context), isNull);
      expect(eval('none?.^[#this > 1]', null, context), isNull);
      expect(eval(r'none?.$[#this > 1]', null, context), isNull);
      expect(eval('list?.?[#this > 1]', null, context), [2]);
      expect(
        () => eval('none.?[true]', null, context),
        spelError(SpelMessage.invalidTypeForSelection),
      );
      expect(
        () => eval('.?[true]', null),
        spelError(SpelMessage.invalidTypeForSelection),
      );
      expect(
        () => eval('.![1]', null),
        spelError(SpelMessage.projectionNotSupportedOnType),
      );
      expect(
        () => eval("'x'.?[true]"),
        spelError(SpelMessage.invalidTypeForSelection),
      );
      expect(
        () => eval("'x'.![1]"),
        spelError(SpelMessage.projectionNotSupportedOnType),
      );
      expect(
        () => eval('{1}.?[#this]'),
        spelError(SpelMessage.resultOfSelectionCriteriaIsNotBoolean),
      );
    });
  });

  group('variables, functions, types, beans', () {
    test('variables and functions', () {
      final context = StandardEvaluationContext()
        ..setVariable('name', 'Ada')
        ..setVariables({'n': 2})
        ..registerFunction(
          'reverse',
          (String s) => s.split('').reversed.join(),
        );
      expect(eval("#reverse('abc')", null, context), 'cba');
      expect(eval('#name + #n', null, context), 'Ada2');
      expect(eval('#missing', null, context), isNull);
      expect(
        () => eval('#nope()', null, context),
        spelError(SpelMessage.functionNotDefined),
      );
      expect(
        () => eval('#name()', null, context),
        spelError(SpelMessage.functionReferenceCannotBeInvoked),
      );
      expect(
        () => eval('#reverse(1)', null, context),
        spelError(SpelMessage.exceptionDuringFunctionCall),
      );
      expect(
        () => eval("#reverse('a', 'b')", null, context),
        spelError(SpelMessage.incorrectNumberOfArgumentsToFunction),
      );
    });

    test('type references, statics and constructors', () {
      expect(eval('T(Math).max(1, 2)'), 2);
      expect(eval('T(Math).PI'), closeTo(3.14159, 1e-5));
      expect(eval("T(int).parse('42')"), 42);
      expect(eval('T(Duration).ofSeconds(2)'), const Duration(seconds: 2));
      expect(eval('new DateTime(2026, 10, 20).year'), 2026);
      expect(eval("new String('x')"), 'x');
      expect(eval('new List()'), isEmpty);
      expect(eval('T(int).MAX_VALUE > 0'), isTrue);
      expect(() => eval('T(Missing)'), spelError(SpelMessage.typeNotFound));
      expect(
        () => eval('T(Math).nope()'),
        spelError(SpelMessage.methodNotFound),
      );
      expect(
        () => eval('T(Math).NOPE'),
        spelError(SpelMessage.propertyOrFieldNotReadable),
      );
      expect(
        () => eval('new Math()'),
        spelError(SpelMessage.constructorNotFound),
      );
      expect(
        () => eval("new DateTime('x')"),
        spelError(SpelMessage.constructorNotFound),
      );
      final locator = StandardTypeLocator()
        ..registerType(
          SpelType.of<Inventor>('Inventor', constructors: {'': Inventor.new}),
        );
      final context = inventorContext()..typeLocator = locator;
      expect(eval("new Inventor('Ada', 1815).name", null, context), 'Ada');
      expect(locator.typeNames, contains('Inventor'));
      expect(SpelType.of<int>('int').toString(), 'T(int)');
      expect(eval('T(Math).random() < 1'), isTrue);
      expect(
        eval('T(Math).sqrt(16) + T(Math).abs(-1) + T(Math).min(1, 2)'),
        6.0,
      );
      expect(
        eval(
          'T(Math).pow(2, 3) + T(Math).round(1.4) + T(Math).floor(1.9) + T(Math).ceil(1.1)',
        ),
        12,
      );
    });

    test('bean references', () {
      final context = StandardEvaluationContext()
        ..beanResolver = _MapBeanResolver();
      expect(eval('@greeter', null, context), 'bean:greeter');
      expect(eval("@'dotted.name'", null, context), 'bean:dotted.name');
      expect(eval('&factory', null, context), 'bean:&factory');
      expect(
        () => eval('@missing', null, context),
        spelError(SpelMessage.exceptionDuringBeanResolution),
      );
      expect(() => eval('@broken', null, context), throwsStateError);
      expect(
        () => eval('@greeter'),
        spelError(SpelMessage.noBeanResolverRegistered),
      );
    });
  });

  group('assignment', () {
    test('properties, variables, maps, lists', () {
      final ada = Inventor('Ada', 1815);
      final context = inventorContext(ada);
      expect(eval("name = 'Ada Lovelace'", null, context), 'Ada Lovelace');
      expect(ada.name, 'Ada Lovelace');
      expect(eval('#x = 5', null, context), 5);
      expect(context.lookupVariable('x'), 5);
      final data = {
        'map': <String, Object?>{},
        'list': [1, 2],
      };
      eval("map['k'] = 1", data);
      eval('map.j = 2', data);
      eval('list[0] = 9', data);
      expect(data, {
        'map': {'k': 1, 'j': 2},
        'list': [9, 2],
      });
      expect(
        () => eval('list[5] = 1', data),
        spelError(SpelMessage.collectionIndexOutOfBounds),
      );
      expect(
        () => eval("'abc'[0] = 'x'"),
        spelError(SpelMessage.indexingNotSupportedForType),
      );
      expect(
        () => eval("{1}.toSet()[0] = 1"),
        spelError(SpelMessage.indexingNotSupportedForType),
      );
      expect(() => eval('1 = 2'), spelError(SpelMessage.setvalueNotSupported));
      expect(() => eval('#this = 1'), spelError(SpelMessage.notAssignable));
      expect(
        () => eval('mentor = null', null, context),
        spelError(SpelMessage.propertyOrFieldNotWritable),
      );
    });

    test('increment and decrement', () {
      final context = StandardEvaluationContext()..setVariable('n', 1);
      expect(eval('#n++', null, context), 1);
      expect(context.lookupVariable('n'), 2);
      expect(eval('++#n', null, context), 3);
      expect(eval('#n--', null, context), 3);
      expect(eval('--#n', null, context), 1);
      final data = {
        'counts': [1, 2],
      };
      expect(eval('counts[0]++', data), 1);
      expect(data['counts'], [2, 2]);
      expect(() => eval('1++'), spelError(SpelMessage.notAssignable));
      context.setVariable('s', 'x');
      expect(
        () => eval('#s++', null, context),
        spelError(SpelMessage.operandNotIncrementable),
      );
      expect(
        () => eval('#s--', null, context),
        spelError(SpelMessage.operandNotDecrementable),
      );
    });

    test('Expression.setValue and isWritable', () {
      final ada = Inventor('Ada', 1815);
      final context = inventorContext(ada);
      parser.parseExpression('birthYear').setValue(context, null, 1816);
      expect(ada.birthYear, 1816);
      expect(parser.parseExpression('name').isWritable(context), isTrue);
      expect(parser.parseExpression('mentor').isWritable(context), isFalse);
      expect(parser.parseExpression('1 + 1').isWritable(context), isFalse);
      expect(
        parser.parseExpression('mentor.name').isWritable(context),
        isFalse,
      );
      final other = Inventor('Grace', 1906);
      parser
          .parseExpression('name')
          .setValue(inventorContext(), other, 'Grace Hopper');
      expect(other.name, 'Grace Hopper');
      expect(
        () =>
            parser.parseExpression('mentor.name').setValue(context, null, 'x'),
        spelError(SpelMessage.propertyOrFieldNotWritableOnNull),
      );
      expect(parser.parseExpression('mentor?.name').getValue(context), isNull);
      expect(
        parser.parseExpression('mentor?.name').isWritable(context),
        isFalse,
      );
    });
  });

  group('typed values and conversion', () {
    test('getValueAs converts with the type converter', () {
      expect(parser.parseExpression("'42'").getValueAs<int>(), 42);
      expect(parser.parseExpression('42').getValueAs<String>(), '42');
      expect(parser.parseExpression("'1,2'").getValueAs<List<int>>(), [1, 2]);
      expect(parser.parseExpression('null').getValueAs<int?>(), isNull);
      expect(
        () => parser.parseExpression('null').getValueAs<int>(),
        spelError(SpelMessage.typeConversionError),
      );
      expect(
        () => parser.parseExpression("'x'").getValueAs<int>(),
        throwsA(isA<SpelEvaluationException>()),
      );
      expect(parser.parseExpression('1').getValueAs<num>(), 1);
    });
  });

  group('templates', () {
    test('literal text and expressions', () {
      final context = StandardEvaluationContext({'name': 'NEON', 'n': 3});
      String template(String text) =>
          parser
                  .parseExpression(text, ParserContext.template)
                  .getValue(context)!
              as String;
      expect(template('Hello #{name}! #{n * 2} items'), 'Hello NEON! 6 items');
      expect(template('#{{1,2}.size()} braces'), '2 braces');
      expect(template("#{'}' + '{'}"), '}{');
      expect(template('no expressions'), 'no expressions');
      expect(template('#{null}x'), 'x');
      expect(parser.parseExpression('', ParserContext.template).getValue(), '');
      expect(
        parser
            .parseExpression('#{n}', ParserContext.template)
            .getValue(context),
        3,
        reason: 'a single expression keeps its type',
      );
      final custom = parser.parseExpression(
        '[[n]]!',
        const TemplateParserContext('[[', ']]'),
      );
      expect(custom.getValue(context), '3!');
      expect(custom.getValueAs<String>(context), '3!');
      expect(custom.isWritable(context), isFalse);
      expect(
        () => custom.setValue(context, null, 1),
        spelError(SpelMessage.notAssignable),
      );
      final literal = parser.parseExpression('plain', ParserContext.template);
      expect(literal, isA<LiteralExpression>());
      expect(literal.getValueAs<String>(), 'plain');
      expect(literal.isWritable(), isFalse);
      expect(
        () => literal.setValue(null, null, 1),
        spelError(SpelMessage.notAssignable),
      );
      expect(literal.toString(), 'plain');
      expect(custom.toString(), '[[n]]!');
    });

    test('template errors are plain ParseExceptions, like Spring', () {
      Matcher templateError(String message) => throwsA(
        isA<ParseException>()
            .having((e) => e is SpelParseException, 'SpEL', isFalse)
            .having((e) => e.simpleMessage, 'simpleMessage', message),
      );
      expect(
        () => parser.parseExpression('#{}', ParserContext.template),
        templateError(
          "No expression defined within delimiter '#{}' at "
          'character 0',
        ),
      );
      expect(
        () => parser.parseExpression('#{1 + 2', ParserContext.template),
        templateError(
          "No ending suffix '}' for expression starting at "
          'character 0: #{1 + 2',
        ),
      );
      expect(
        () => parser.parseExpression('#{a)}', ParserContext.template),
        templateError(
          "Found closing ')' at position 3 without an opening "
          "'('",
        ),
      );
      expect(
        () => parser.parseExpression('#{(a]}', ParserContext.template),
        templateError(
          "Found closing ']' at position 4 but most recent "
          "opening is '(' at position 2",
        ),
      );
      expect(
        () => parser.parseExpression("#{'x}", ParserContext.template),
        templateError(
          'Found non terminating string literal starting at position 2',
        ),
      );
    });
  });

  group('restricted contexts', () {
    test('SimpleEvaluationContext read-only', () {
      final ada = Inventor('Ada', 1815);
      final accessor = FunctionPropertyAccessor<Inventor>(
        getters: {'name': (i) => i.name},
        setters: {'name': (i, v) => i.name = v! as String},
      );
      final context = SimpleEvaluationContext.forPropertyAccessors([accessor])
          .withRootObject(ada)
          .withAssignmentDisabled()
          .build();
      expect(eval('name', null, context), 'Ada');
      expect(
        () => eval("name = 'x'", null, context),
        spelError(SpelMessage.notAssignable),
      );
      expect(
        () => eval('name.length()', null, context),
        spelError(SpelMessage.methodNotFound),
      );
      expect(
        () => eval('T(int)', null, context),
        spelError(SpelMessage.typeNotFound),
      );
      expect(
        () => eval('new List()', null, context),
        spelError(SpelMessage.constructorNotFound),
      );
      expect(
        () => eval('@bean', null, context),
        spelError(SpelMessage.noBeanResolverRegistered),
      );
      expect(
        () => parser.parseExpression('name').setValue(context, null, 'x'),
        spelError(SpelMessage.notAssignable),
      );
      expect(parser.parseExpression('name').isWritable(context), isFalse);
      expect(
        () => eval('#n++', null, context),
        spelError(SpelMessage.notAssignable),
      );
    });

    test('SimpleEvaluationContext read-write with methods', () {
      final data = <String, Object?>{'n': 1};
      final readWrite = SimpleEvaluationContext.forReadWriteDataBinding()
          .withInstanceMethods()
          .withMethodResolvers([
            FunctionMethodResolver<Map<String, Object?>>({
              'twice': (m, _) => (m['n']! as int) * 2,
            }),
          ])
          .withConversionService(DefaultConversionService())
          .withRootObject(data)
          .build();
      eval('n = 5', null, readWrite);
      expect(data['n'], 5);
      expect(eval("'abc'.toUpperCase()", null, readWrite), 'ABC');
      expect(eval('twice()', null, readWrite), 10);
      readWrite.setVariable('v', 1);
      expect(eval('#v', null, readWrite), 1);
      expect(readWrite.typeComparator, isA<StandardTypeComparator>());
      final readOnly = SimpleEvaluationContext.forReadOnlyDataBinding()
          .withTypeConverter(StandardTypeConverter())
          .build();
      expect(readOnly.isAssignmentEnabled, isFalse);
      expect(readOnly.constructorResolvers, isEmpty);
    });
  });

  group('parse errors', () {
    test('positions and messages', () {
      final cases = {
        '': SpelMessage.ood,
        '1 +': SpelMessage.rightOperandProblem,
        '* 2': SpelMessage.leftOperandProblem,
        '(1': SpelMessage.ood,
        '1 2': SpelMessage.moreInput,
        "'abc": SpelMessage.nonTerminatingQuotedString,
        '"abc': SpelMessage.nonTerminatingDoubleQuotedString,
        '0x': SpelMessage.notAnInteger,
        '1.5L': SpelMessage.realCannotBeLong,
        'a | b': SpelMessage.missingCharacter,
        'a ~ b': SpelMessage.unsupportedCharacter,
        r'a \ b': SpelMessage.unexpectedEscapeChar,
        'a.': SpelMessage.ood,
        'a.1': SpelMessage.unexpectedDataAfterDot,
        '#': SpelMessage.ood,
        '@': SpelMessage.invalidBeanReference,
        '{1, 2': SpelMessage.ood,
        '{a: 1, b}': SpelMessage.notExpectedToken,
        'true ? 1': SpelMessage.ood,
        ')': SpelMessage.ood,
        '99999999999999999999': SpelMessage.notAnInteger,
        '99999999999999999999L': SpelMessage.notALong,
        'T(1)': SpelMessage.notExpectedToken,
        'new Foo': SpelMessage.missingConstructorArgs,
        'list.?[]': SpelMessage.missingSelectionExpression,
      };
      cases.forEach(
        (text, code) => expect(
          () => parser.parseExpression(text),
          parseError(code),
          reason: text,
        ),
      );
      // Like Spring: `*` has no left operand.
      final error = _catch(() => parser.parseExpression('1 + * 2'));
      expect(error.messageCode, SpelMessage.leftOperandProblem);
      expect(error.position, 4);
      expect(error.simpleMessage, 'EL1070E: Problem parsing left operand');
      expect(
        error.message,
        'Expression [1 + * 2] @4: EL1070E: Problem parsing left operand',
      );
      expect(
        _catch(() => parser.parseExpression('a ~ b')).simpleMessage,
        "EL1082E: Unsupported character '~' (126) encountered in expression",
      );
    });

    test('textual operators are identifiers after a dot', () {
      expect(() => eval('div'), throwsA(isA<SpelParseException>()));
      expect(
        eval('m.and', {
          'm': {'and': 2},
        }),
        2,
      );
    });

    test('evaluation error messages', () {
      final error = _catchEval(() => eval('nothing.here'));
      expect(
        error.simpleMessage,
        "EL1007E: Property or field 'nothing' cannot be found on null",
      );
      expect(error.inserts, ['nothing']);
      expect(error.message, startsWith('Expression [nothing.here] @0: '));
      final missing = _catchEval(() => eval('nope', <String, Object?>{}));
      expect(
        missing.simpleMessage,
        allOf(
          startsWith(
            "EL1008E: Property or field 'nope' cannot be found on object of "
            "type '",
          ),
          endsWith("' - maybe not public or not valid?"),
        ),
      );
      final wrapped = _catchEval(() => eval("'x'.substring('a')"));
      expect(wrapped.toString(), contains('caused by'));
    });

    test('AST and expression rendering', () {
      expect(parser.parseExpression("a.b[0] + 'x'").toString(), "a.b[0] + 'x'");
      final ast = (parser.parseExpression(
        "#a = ({k: 2}.size() > 1 ? -x : y ?: ++#z)",
      ) as SpelExpression).ast;
      expect(ast.toString(), isNotEmpty);
      for (final text in [
        'a.?[x]',
        'a.^[x]',
        r'a.$[x]',
        'a.![x]',
        '@b',
        '&f',
        'T(int)',
        "new String('x')",
        '#f(1)',
        'a?.[1]',
        '{a: 1}',
        '!a',
        'a--',
        '--a',
        'a and b',
      ]) {
        expect(
          (parser.parseExpression(text) as SpelExpression).ast.toString(),
          isNotEmpty,
          reason: text,
        );
      }
    });
  });

  group('built-ins', () {
    test('strings', () {
      expect(eval("'Hello World'.concat('!')"), 'Hello World!');
      expect(eval("'abc'.length()"), 3);
      expect(eval("'abc'.size()"), 3);
      expect(eval("' a '.trim() + ' a '.strip()"), 'aa');
      expect(eval("'abc'.toUpperCase().toLowerCase()"), 'abc');
      expect(eval("'abcdef'.substring(2)"), 'cdef');
      expect(eval("'abcdef'.substring(2, 4)"), 'cd');
      expect(
        eval(
          "'abc'.startsWith('a') and 'abc'.endsWith('c') and 'abc'.contains('b')",
        ),
        isTrue,
      );
      expect(eval("'abcb'.indexOf('b') + 'abcb'.lastIndexOf('b')"), 4);
      expect(eval("'abc'.charAt(1)"), 'b');
      expect(eval("'a,b'.split(',')"), ['a', 'b']);
      expect(
        eval("'aXa'.replace('a', 'b') + 'x'.replaceAll('x', 'y')"),
        'bXby',
      );
      expect(eval("'ab'.repeat(2)"), 'abab');
      expect(eval("'7'.padLeft(3, '0') + '7'.padRight(2)"), '0077 ');
      expect(eval("'ABC'.equalsIgnoreCase('abc')"), isTrue);
      expect(eval("'123'.matches('\\d+')"), isTrue);
      expect(
        eval("'  '.isBlank() and ''.isEmpty() and 'x'.isNotEmpty()"),
        isTrue,
      );
      expect(eval("'A'.codeUnitAt(0)"), 65);
      expect(eval("' x'.trimLeft() + 'y '.trimRight()"), 'xy');
      expect(eval("'abc'.length + ''.isEmpty.toString()"), '3true');
      expect(eval("'x'.isNotEmpty and 'x'.empty == false"), isTrue);
      expect(eval("'x'.equals('x') and 'x'.hashCode() != 0"), isTrue);
      expect(eval("'a'.compareTo('b')"), -1);
      expect(eval("'x'.toString()"), 'x');
    });

    test('lists, iterables, maps', () {
      final root = {
        'list': [3, 1, 2],
        'map': <String, Object?>{'a': 1},
        'set': {1, 2},
      };
      expect(eval('list.get(0) + list.elementAt(1)', root), 4);
      expect(eval('list.indexOf(2) + list.lastIndexOf(3)', root), 2);
      expect(eval('list.sublist(1)', root), [1, 2]);
      expect(eval('list.subList(0, 1)', root), [3]);
      expect(eval('list.add(4)', root), isTrue);
      expect(eval('list.reversed()', root), [4, 2, 1, 3]);
      expect(eval("list.join('-')", root), '3-1-2-4');
      expect(
        eval(
          'list.contains(1) and list.isNotEmpty() and !list.isEmpty()',
          root,
        ),
        isTrue,
      );
      expect(eval('list.first() + list.last()', root), 7);
      expect(
        eval('list.first + list.last + list.length + list.size', root),
        15,
      );
      expect(
        eval('list.isEmpty or list.empty or !list.isNotEmpty', root),
        isFalse,
      );
      expect(eval('set.toList()', root), [1, 2]);
      expect(eval('list.toSet().size()', root), 4);
      expect(eval('set.first + set.last + set.length() + set.size()', root), 7);
      expect(eval("map.get('a') + map.getOrDefault('z', 5)", root), 6);
      expect(
        eval("map.containsKey('a') and map.containsValue(1)", root),
        isTrue,
      );
      expect(eval("map.put('b', 2)", root), isNull);
      expect(
        eval('map.size() + map.length() + map.size + map.length', root),
        8,
      );
      expect(
        eval(
          'map.isEmpty() or !map.isNotEmpty() or map.isEmpty or map.empty',
          root,
        ),
        isFalse,
      );
      expect(eval('map.isNotEmpty', root), isTrue);
      expect(
        eval(
          'map.keySet().size() + map.keys().size() + map.values().size()',
          root,
        ),
        6,
      );
      expect(eval('map.values', root), [1, 2]);
      expect(eval('map.keySet', root), ['a', 'b']);
      expect(eval('map.entrySet.size()', root), 2);
      expect(eval("map.entries.![key]", root), ['a', 'b']);
    });

    test('numbers, dates, durations, enums', () {
      // Unary minus binds looser than the method call: -(1.5.abs()).
      expect(eval('-1.5.abs() + 1.4.round() + 1.9.floor() + 1.1.ceil()'), 2.5);
      expect(
        eval('7.9.toInt() + 2.toDouble() + 3.7.intValue() + 1.doubleValue()'),
        13.0,
      );
      expect(eval('3.14159.toStringAsFixed(2)'), '3.14');
      expect(eval('15.clamp(0, 10) + 7.remainder(4)'), 13);
      expect(
        eval(
          '(-2).isNegative and !1.5.isNaN and 1.isFinite and !1.isInfinite and (-3).sign == -1',
        ),
        isTrue,
      );
      final root = {
        'date': DateTime.utc(2026, 10, 20, 9, 30, 15, 250),
        'other': DateTime.utc(2027),
        'duration': const Duration(hours: 49, milliseconds: 1500),
        'mode': SpelMessage.typeNotFound,
      };
      expect(eval('date.year + date.month + date.day', root), 2056);
      expect(
        eval('date.hour + date.minute + date.second + date.millisecond', root),
        304,
      );
      expect(eval('date.weekday + (date.isUtc ? 1 : 0)', root), 3);
      expect(eval('date.millisecondsSinceEpoch > 0', root), isTrue);
      expect(
        eval('date.isBefore(other) and other.isAfter(date)', root),
        isTrue,
      );
      expect(eval('date.add(duration).isAfter(date)', root), isTrue);
      expect(eval('date.subtract(duration).isBefore(date)', root), isTrue);
      expect(eval('other.difference(date).inDays', root), 72);
      expect(eval('date.toIso8601String()', root), '2026-10-20T09:30:15.250Z');
      expect(
        eval('date.toUtc().isUtc and !date.toLocal().isUtc', root),
        isTrue,
      );
      expect(
        eval('duration.inDays + duration.inHours + duration.inMinutes', root),
        2 + 49 + 2940,
      );
      expect(
        eval(
          'duration.inSeconds + duration.inMilliseconds + duration.inMicroseconds',
          root,
        ),
        176401 + 176401500 + 176401500000,
      );
      expect(
        eval('duration.isNegative or duration.abs().inHours != 49', root),
        isFalse,
      );
      expect(
        eval(
          'duration.toMillis() + duration.toSeconds() + duration.getSeconds()',
          root,
        ),
        176401500 + 2 * 176401,
      );
      expect(
        eval("mode.name + ':' + mode.index", root),
        'typeNotFound:${SpelMessage.typeNotFound.index}',
      );
    }, skip: false);
  });

  group('Spring parity', () {
    test('SimpleEvaluationContext forbids variable assignment (EL1080E)', () {
      final context = SimpleEvaluationContext.forReadWriteDataBinding().build()
        ..setVariable('v', 1);
      for (final expression in ['#v = 5', '#v++', '#v--', '++#v']) {
        expect(
          () => eval(expression, null, context),
          throwsA(
            isA<SpelEvaluationException>()
                .having(
                  (e) => e.messageCode,
                  'messageCode',
                  SpelMessage.variableAssignmentNotSupported,
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains("Assignment to variable '#v' is not supported"),
                ),
          ),
        );
      }
      expect(
        () => parser.parseExpression('#v').setValue(context, null, 2),
        spelError(SpelMessage.variableAssignmentNotSupported),
      );
      expect(eval('#v', null, context), 1);
      final standard = StandardEvaluationContext()..setVariable('v', 1);
      expect(eval('#v = 5', null, standard), 5);
      expect(eval('#v++', null, standard), 5);
      expect(standard.lookupVariable('v'), 6);
      expect(standard.assignVariable('w', () => 7), 7);
      expect(standard.lookupVariable('w'), 7);
    });

    test('enums of the same type compare by index (Java ordinal)', () {
      final context = StandardEvaluationContext()
        ..setVariable('lo', _Level.low)
        ..setVariable('hi', _Level.high);
      expect(eval('#lo < #hi', null, context), isTrue);
      expect(eval('#hi >= #lo', null, context), isTrue);
      expect(eval('#lo > #hi', null, context), isFalse);
      expect(
        const StandardTypeComparator().canCompare(_Level.low, _Shade.dark),
        isFalse,
      );
    });

    test('selection criteria must be boolean', () {
      for (final expression in [
        "{1,2,3}.?['true']",
        '{1,2,3}.^[null]',
        "{a: 1}.?['true']",
      ]) {
        expect(
          () => eval(expression),
          spelError(SpelMessage.resultOfSelectionCriteriaIsNotBoolean),
        );
      }
    });

    test('+ converts the non-String operand with the TypeConverter', () {
      expect(eval("'a' + {1,2}"), 'a1,2');
      expect(eval("{1,2} + 'a'"), '1,2a');
      expect(eval("'a' + null"), 'anull');
      expect(
        parser
            .parseExpression('list: #{ {1,2} }!', ParserContext.template)
            .getValue(),
        'list: 1,2!',
      );
    });

    test('map selection first/last without a match is null', () {
      expect(eval('{a: 1, b: 2}.^[value > 5]'), isNull);
      expect(eval(r'{a: 1, b: 2}.$[value > 5]'), isNull);
      expect(eval('{a: 1, b: 2}.^[value > 0]'), {'a': 1});
      expect(eval(r'{a: 1, b: 2}.$[value > 0]'), {'b': 2});
      expect(eval('{a: 1, b: 2}.?[value > 5]'), <Object?, Object?>{});
    });
  });
}

enum _Level { low, high }

enum _Shade { dark }

SpelParseException _catch(void Function() body) {
  try {
    body();
  } on SpelParseException catch (e) {
    return e;
  }
  fail('expected SpelParseException');
}

SpelEvaluationException _catchEval(void Function() body) {
  try {
    body();
  } on SpelEvaluationException catch (e) {
    return e;
  }
  fail('expected SpelEvaluationException');
}

class _ListConcat implements OperatorOverloader {
  @override
  bool overridesOperation(Operation operation, Object? left, Object? right) =>
      operation == Operation.add && left is List && right is List;

  @override
  Object? operate(Operation operation, Object? left, Object? right) => [
    ...left! as List,
    ...right! as List,
  ];
}

class _MapBeanResolver implements BeanResolver {
  @override
  Object? resolve(EvaluationContext context, String beanName) =>
      switch (beanName) {
        'missing' => throw AccessException('no bean'),
        'broken' => throw StateError('broken resolver'),
        _ => 'bean:$beanName',
      };
}
