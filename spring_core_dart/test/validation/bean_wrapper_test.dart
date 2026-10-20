import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late Person person;
  late BeanWrapper wrapper;

  setUp(() {
    person = Person()
      ..name = 'Ada'
      ..address = (Address('London')..zip = '12345')
      ..previous = [Address('Paris')]
      ..byLabel = {'home': Address('Rome')}
      ..counts = {'a': 1};
    wrapper = BeanWrapper(person, introspector: introspector());
  });

  test('reads nested paths, lists, maps and sets', () {
    expect(wrapper.getPropertyValue('name'), 'Ada');
    expect(wrapper.getPropertyValue('address.city'), 'London');
    expect(wrapper.getPropertyValue('previous[0].city'), 'Paris');
    expect(wrapper.getPropertyValue("byLabel['home'].city"), 'Rome');
    expect(wrapper.getPropertyValue('byLabel["home"].city'), 'Rome');
    expect(wrapper.getPropertyValue('counts[a]'), 1);
    expect(wrapper.getPropertyValue('lucky[1]'), 2);
    expect(wrapper.isReadableProperty('address.zip'), isTrue);
    expect(wrapper.isReadableProperty('nope'), isFalse);
    expect(wrapper.getPropertyType('age'), int);
    expect(wrapper.getPropertyType('previous[0]'), Address);
    expect(wrapper.getPropertyType('nope.x'), isNull);
  });

  test('writes with conversion', () {
    wrapper
      ..setPropertyValue('age', '42')
      ..setPropertyValue('score', '9.5')
      ..setPropertyValue('score', null)
      ..setPropertyValue('tags', 'a, b')
      ..setPropertyValue('address.city', 'Berlin')
      ..setPropertyValue('previous[0].city', 'Madrid')
      ..setPropertyValue('previous[1]', Address('Added'))
      ..setPropertyValue('counts[b]', 2)
      ..setPropertyValue('byLabel[work]', Address('Office'));
    expect(person.age, 42);
    expect(person.score, isNull);
    expect(person.tags, ['a', 'b']);
    expect(person.address!.city, 'Berlin');
    expect(person.previous.map((a) => a.city), ['Madrid', 'Added']);
    expect(person.counts, {'a': 1, 'b': 2});
    expect(person.byLabel['work']!.city, 'Office');
    expect(wrapper.isWritableProperty('name'), isTrue);
    expect(wrapper.isWritableProperty('id'), isFalse);
    expect(wrapper.isWritableProperty('counts[x]'), isTrue);
    expect(wrapper.isWritableProperty('nope'), isFalse);
    expect(wrapper.isWritableProperty('missing.path'), isFalse);
  });

  test('map targets and integer map keys', () {
    final map = <String, Object?>{
      'a': 1,
      'nested': <int, String>{1: 'one'},
    };
    final mapWrapper = BeanWrapper(map);
    expect(mapWrapper.getPropertyValue('a'), 1);
    expect(mapWrapper.getPropertyValue('nested[1]'), 'one');
    mapWrapper.setPropertyValue('b', 2);
    expect(map['b'], 2);
    expect(mapWrapper.isWritableProperty('c'), isTrue);
  });

  test('errors', () {
    expect(
      () => wrapper.getPropertyValue('nope'),
      throwsA(
        isA<NotReadablePropertyException>().having(
          (e) => e.propertyName,
          'name',
          'nope',
        ),
      ),
    );
    expect(
      () => wrapper.getPropertyValue('previous[5]'),
      throwsA(isA<NotReadablePropertyException>()),
    );
    expect(
      () => wrapper.getPropertyValue('lucky[9]'),
      throwsA(isA<NotReadablePropertyException>()),
    );
    expect(
      () => wrapper.getPropertyValue('name[0]'),
      throwsA(isA<NotReadablePropertyException>()),
    );
    expect(
      () => wrapper.setPropertyValue('previous[9]', Address()),
      throwsA(isA<NotWritablePropertyException>()),
    );
    expect(
      () => wrapper.setPropertyValue('lucky[0]', 1),
      throwsA(isA<NotWritablePropertyException>()),
    );
    expect(
      () => wrapper.setPropertyValue('id', 'x'),
      throwsA(isA<NotWritablePropertyException>()),
    );
    expect(
      () => wrapper.setPropertyValue('nope', 'x'),
      throwsA(isA<NotWritablePropertyException>()),
    );
    expect(
      () => wrapper.setPropertyValue('age', 'old'),
      throwsA(
        isA<TypeMismatchException>()
            .having((e) => e.requiredType, 'type', int)
            .having((e) => e.toString(), 'text', contains("'age'")),
      ),
    );
    expect(
      () => wrapper.setPropertyValue('age', null),
      throwsA(isA<TypeMismatchException>()),
    );
    expect(
      () => wrapper.setPropertyValue('age', ''),
      throwsA(isA<TypeMismatchException>()),
    );
    person.address = null;
    expect(
      () => wrapper.getPropertyValue('address.city'),
      throwsA(isA<NullValueInNestedPathException>()),
    );
    expect(
      () => wrapper.setPropertyValue('address.city', 'x'),
      throwsA(isA<NullValueInNestedPathException>()),
    );
    person.counts = {};
    expect(
      () => wrapper.getPropertyValue('byLabel[none].city'),
      throwsA(isA<NullValueInNestedPathException>()),
    );
    expect(() => wrapper.getPropertyValue('a[0'), throwsArgumentError);
    expect(() => wrapper.getPropertyValue('a..b'), throwsArgumentError);
    expect(
      () => BeanWrapper(Object()).getPropertyValue('x'),
      throwsA(isA<NotReadablePropertyException>()),
    );
    expect(
      () => BeanWrapper(Object()).setPropertyValue('x', 1),
      throwsA(isA<NotWritablePropertyException>()),
    );
  });

  test('auto-grow nested paths', () {
    person.address = null;
    final growing = BeanWrapper(
      person,
      introspector: introspector(),
      autoGrowNestedPaths: true,
    )..setPropertyValue('address.city', 'Grown');
    expect(person.address!.city, 'Grown');
    expect(
      () => growing.setPropertyValue('tags.length', 1),
      throwsA(isA<NotWritablePropertyException>()),
    );
    final unknown = BeanWrapper(
      Person()..address = null,
      introspector: BeanIntrospector(introspections: [personIntrospection]),
      autoGrowNestedPaths: true,
    );
    expect(
      () => unknown.setPropertyValue('address.city', 'x'),
      throwsA(isA<NullValueInNestedPathException>()),
    );
  });

  test('batch updates', () {
    wrapper.setPropertyValues({
      'name': 'Bob',
      'unknown': 1,
    }, ignoreUnknown: true);
    expect(person.name, 'Bob');
    person.address = null;
    wrapper.setPropertyValues({'address.city': 'x'}, ignoreInvalid: true);
    expect(
      () => wrapper.setPropertyValues({
        'age': 'x',
        'unknown': 1,
        'address.city': 'x',
      }),
      throwsA(
        isA<PropertyBatchUpdateException>().having(
          (e) => e.exceptions,
          'exceptions',
          hasLength(3),
        ),
      ),
    );
  });

  group('introspection', () {
    test('metadata and registry', () {
      final registry = introspector();
      final metadata = registry.getIntrospection(person);
      expect(metadata.beanType, Person);
      expect(metadata.isInstantiable, isTrue);
      expect(metadata.instantiate(), isA<Person>());
      expect(metadata.properties, hasLength(10));
      expect(metadata.getProperty('id')!.isWritable, isFalse);
      expect(
        () => metadata.getProperty('id')!.setValue(person, 'x'),
        throwsStateError,
      );
      expect(
        metadata.getMethod('hello')!.invoke(person, ['Bob']),
        'hello Bob from Ada',
      );
      expect(metadata.methods.single.toString(), contains('hello'));
      expect(metadata.getProperty('name').toString(), contains('name: String'));
      expect(metadata.getProperty('score').toString(), contains('double?'));
      expect(metadata.toString(), 'BeanIntrospection<Person>');
      expect(
        metadata.getProperty('name')!.annotationsOf<Size>().single.max,
        10,
      );
      expect(registry.forType(Address), same(addressIntrospection));
      expect(registry.findIntrospection(Object()), isNull);
      expect(() => registry.getIntrospection(Object()), throwsArgumentError);
      final child = BeanIntrospector(parent: registry);
      expect(child.forType(Person), same(personIntrospection));
      expect(child.findIntrospection(Address()), same(addressIntrospection));
      final noCtor = BeanIntrospection<Object>();
      expect(noCtor.isInstantiable, isFalse);
      expect(noCtor.instantiate, throwsStateError);
    });

    test('subtypes find the supertype introspection', () {
      final registry = BeanIntrospector()..registerAll([addressIntrospection]);
      expect(
        registry.findIntrospection(_FancyAddress()),
        same(addressIntrospection),
      );
    });

    test('SpEL accessors', () {
      final registry = introspector();
      final context = StandardEvaluationContext(person)
        ..addPropertyAccessor(IntrospectionPropertyAccessor(registry))
        ..addMethodResolver(IntrospectionMethodResolver(registry));
      final parser = SpelExpressionParser();
      expect(
        parser.parseExpression('address.city').getValue(context),
        'London',
      );
      expect(
        parser.parseExpression("hello('Bob')").getValue(context),
        'hello Bob from Ada',
      );
      expect(
        parser.parseExpression('hello(42)').getValue(context),
        'hello 42 from Ada',
      );
      parser.parseExpression('age').setValue(context, null, '7');
      expect(person.age, 7);
      parser.parseExpression('score').setValue(context, null, null);
      expect(parser.parseExpression('id').isWritable(context), isFalse);
      expect(
        () => parser.parseExpression('hello(1, 2)').getValue(context),
        throwsA(isA<SpelEvaluationException>()),
      );
    });
  });
}

class _FancyAddress extends Address {}
