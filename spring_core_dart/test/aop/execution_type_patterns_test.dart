// Return and parameter type patterns of `execution(...)`: qualified names,
// `Type+`, `!Type` and parenthesized `&&` / `||` combinations (AspectJ).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

const _find = MethodSignature(
  name: 'find',
  declaringType: 'Books',
  targetType: 'Books',
  returnType: 'String',
  parameterTypes: ['int', 'Map'],
);

const _count = MethodSignature(
  name: 'count',
  declaringType: 'Books',
  targetType: 'Books',
  returnType: 'int',
  parameterTypes: ['String'],
);

const _clear = MethodSignature(
  name: 'clear',
  declaringType: 'Books',
  targetType: 'Books',
  returnType: 'void',
);

bool _matches(String expression, MethodSignature signature) =>
    ExpressionPointcut(expression).matches(signature, 'books');

void main() {
  test('qualified return and parameter types match by simple name', () {
    expect(_matches('execution(java.lang.String find(..))', _find), isTrue);
    expect(_matches('execution(* count(java.lang.String))', _count), isTrue);
    expect(_matches('execution(java.lang.String *(..))', _count), isFalse);
  });

  test('Object+ matches every type except void', () {
    expect(_matches('execution(Object+ *(..))', _find), isTrue);
    expect(_matches('execution(Object+ *(..))', _count), isTrue);
    expect(_matches('execution(Object+ *(..))', _clear), isFalse);
    expect(_matches('execution(* *(Object+, ..))', _find), isTrue);
  });

  test('num+ knows int and double', () {
    expect(_matches('execution(num+ *(..))', _count), isTrue);
    expect(_matches('execution(* *(num+, ..))', _find), isTrue);
  });

  test('negation', () {
    expect(_matches('execution(!String *(..))', _find), isFalse);
    expect(_matches('execution(!String *(..))', _count), isTrue);
    expect(_matches('execution(* *(!String))', _count), isFalse);
  });

  test('parenthesized || and && combinations', () {
    expect(_matches('execution((String || int) *(..))', _find), isTrue);
    expect(_matches('execution((String||int) *(..))', _count), isTrue);
    expect(_matches('execution((String || int) *(..))', _clear), isFalse);
    expect(_matches('execution(* *((int || double), ..))', _find), isTrue);
    expect(_matches('execution(* *((String || double)))', _count), isTrue);
    expect(_matches('execution((Object+ && !String) *(..))', _count), isTrue);
    expect(_matches('execution((Object+ && !String) *(..))', _find), isFalse);
  });

  test('type arguments are ignored, also with spaces', () {
    expect(_matches('execution(* find(int, Map<String, int>))', _find), isTrue);
  });

  test('String||int without parentheses is a syntax error', () {
    expect(
      () => ExpressionPointcut('execution(String||int *(..))'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains("write '(String||int)'"),
        ),
      ),
    );
    expect(
      () => ExpressionPointcut('execution(* *(String||int))'),
      throwsFormatException,
    );
  });

  test('Type+ of a type whose subtypes are unknown is rejected', () {
    expect(
      () => ExpressionPointcut('execution(Animal+ *(..))'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('the subtypes of Animal are unknown'),
        ),
      ),
    );
  });

  test('a qualified wildcard stays an error', () {
    expect(
      () => ExpressionPointcut('execution(com.x.* *(..))'),
      throwsFormatException,
    );
  });
}
