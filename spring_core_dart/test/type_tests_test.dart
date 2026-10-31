import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Base implements Exception {}

class Sub extends Base {}

void main() {
  test('a registered test matches subtypes', () {
    final introspector = BeanIntrospector()
      ..registerTypeTests({Base: (value) => value is Base});
    expect(introspector.isInstanceOf(Base, Sub()), isTrue);
    expect(introspector.isInstanceOf(Base, Base()), isTrue);
    expect(introspector.isInstanceOf(Base, 'x'), isFalse);
    expect(introspector.isInstanceOf(Base, null), isFalse);
  });

  test('without a test, only the exact runtime type matches', () {
    final introspector = BeanIntrospector();
    expect(introspector.isInstanceOf(Base, Base()), isTrue);
    expect(introspector.isInstanceOf(Base, Sub()), isFalse);
  });

  test('tests of the parent are used', () {
    final parent = BeanIntrospector()
      ..registerTypeTests({Base: (value) => value is Base});
    expect(
      BeanIntrospector(parent: parent).isInstanceOf(Base, Sub()),
      isTrue,
    );
  });

  test('a module registers its tests in the context', () {
    final context = ApplicationContext.run([
      BeanModule('m', const [], typeTests: {Base: (value) => value is Base}),
    ]);
    addTearDown(context.close);
    expect(
      context.getBean<BeanIntrospector>().isInstanceOf(Base, Sub()),
      isTrue,
    );
  });
}
