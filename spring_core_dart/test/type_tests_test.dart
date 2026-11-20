import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Base implements Exception {}

class Sub extends Base {}

void main() {
  test('a registered test matches subtypes', () {
    final introspector = Introspector()
      ..registerTypeTests({Base: (value) => value is Base});
    expect(introspector.isInstanceOf(Base, Sub()), isTrue);
    expect(introspector.isInstanceOf(Base, Base()), isTrue);
    expect(introspector.isInstanceOf(Base, 'x'), isFalse);
    expect(introspector.isInstanceOf(Base, null), isFalse);
  });

  test('without a test, only the exact runtime type matches', () {
    final introspector = Introspector();
    expect(introspector.isInstanceOf(Base, Base()), isTrue);
    expect(introspector.isInstanceOf(Base, Sub()), isFalse);
  });

  test('tests of the parent are used', () {
    final parent = Introspector()
      ..registerTypeTests({Base: (value) => value is Base});
    expect(
      Introspector(parent: parent).isInstanceOf(Base, Sub()),
      isTrue,
    );
  });

  test('a module registers its tests in the context', () {
    final context = ApplicationContext.run([
      BeanModule('m', const [], typeTests: {Base: (value) => value is Base}),
    ]);
    addTearDown(context.close);
    expect(
      context.getBean<Introspector>().isInstanceOf(Base, Sub()),
      isTrue,
    );
  });

  test('depths are registered, found through the parent, and from modules', () {
    final parent = Introspector()..registerTypeDepths({Base: 2});
    final child = Introspector(parent: parent)..registerTypeDepths({Sub: 3});
    expect(child.typeDepth(Base), 2);
    expect(child.typeDepth(Sub), 3);
    expect(parent.typeDepth(Sub), isNull);
    final context = ApplicationContext.run([
      BeanModule('m', const [], typeDepths: {Base: 2}),
    ]);
    addTearDown(context.close);
    expect(context.getBean<Introspector>().typeDepth(Base), 2);
  });
}
