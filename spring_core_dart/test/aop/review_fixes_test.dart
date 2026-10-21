import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

/// Stands in for an annotation whose runtime type name is minified in a
/// release build: the generated name is `Timed`, the class is not.
class Minified {
  const Minified();
}

const _signature = MethodSignature(
  name: 'price',
  declaringType: 'PriceService',
  targetType: 'PriceService',
  returnType: 'int',
  annotations: [Minified()],
  annotationTypes: ['Timed'],
  targetAnnotations: [Minified()],
  targetAnnotationTypes: ['Audited'],
  targetTypes: ['PriceService'],
);

bool matches(String expression) =>
    ExpressionPointcut(expression).matches(_signature, 'priceService');

void main() {
  test('@annotation and @within use the generated (release-safe) names', () {
    expect(matches('@annotation(Timed)'), isTrue);
    expect(matches('@annotation(Minified)'), isFalse);
    expect(matches('@within(Audited)'), isTrue);
  });

  test('package-qualified wildcards are rejected instead of matching all', () {
    for (final expression in [
      'within(com.example.service..*)',
      'within(com.example.service.*)',
      'execution(* com.example.service..*.*(..))',
    ]) {
      expect(
        () => matches(expression),
        throwsA(isA<FormatException>()),
        reason: expression,
      );
    }
  });

  test('a qualified concrete type name is reduced to its simple name', () {
    expect(matches('within(com.example.PriceService)'), isTrue);
    expect(matches('within(com.example.OtherService)'), isFalse);
  });

  test('argument binding is rejected instead of matching nothing', () {
    expect(
      () => matches('@annotation(timed)'),
      throwsA(isA<FormatException>()),
    );
  });
}
