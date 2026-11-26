// What a tool drawing the bean graph reads from the container without
// creating a bean: the beans each injection point of a definition points
// to (`dependencyCandidateNames`), and a post-processor it adds only
// while it watches and takes away after (`removeBeanPostProcessor`).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

abstract interface class Store {}

class MainStore implements Store {}

class SpareStore implements Store {}

class Shop {}

class _Recorder extends BeanPostProcessor {
  final created = <String>[];

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    created.add(beanName);
    return bean;
  }
}

BeanDefinition<Object> _store<T extends Store>(
  String name,
  T Function() create, {
  bool primary = false,
}) => BeanDefinition<T>(
  name: name,
  types: [T, Store],
  primary: primary,
  create: (_) => create(),
);

DefaultListableBeanFactory _factory({bool primary = false}) =>
    DefaultListableBeanFactory()
      ..registerBeanDefinition(
        _store('mainStore', MainStore.new, primary: primary),
      )
      ..registerBeanDefinition(_store('spareStore', SpareStore.new))
      ..registerBeanDefinition(
        BeanDefinition<Shop>(name: 'shop', create: (_) => Shop()),
      );

void main() {
  group('dependencyCandidateNames', () {
    test('a single point names the bean the container would choose', () {
      final factory = _factory(primary: true);
      expect(
        factory.dependencyCandidateNames(
          const Dependency(Store),
          requester: 'shop',
        ),
        ['mainStore'],
      );
      expect(
        factory.dependencyCandidateNames(
          const Dependency(Store, qualifier: 'spareStore'),
          requester: 'shop',
        ),
        ['spareStore'],
      );
      expect(factory.singletonNames, isEmpty, reason: 'nothing created');
    });

    test('the injection point name picks among equal candidates', () {
      expect(
        _factory().dependencyCandidateNames(
          const Dependency(Store, name: 'spareStore'),
          requester: 'shop',
        ),
        ['spareStore'],
      );
    });

    test('an ambiguous point gives every candidate', () {
      expect(
        _factory().dependencyCandidateNames(
          const Dependency(Store),
          requester: 'shop',
        ),
        ['mainStore', 'spareStore'],
      );
    });

    test('lazy and provider points name their bean like a single one', () {
      final factory = _factory(primary: true);
      for (final dependency in const [
        Dependency.lazy(Store),
        Dependency.provider(Store),
      ]) {
        expect(
          factory.dependencyCandidateNames(dependency, requester: 'shop'),
          ['mainStore'],
          reason: '$dependency',
        );
      }
    });

    test('a collection or a map names every candidate', () {
      final factory = _factory(primary: true);
      for (final dependency in const [
        Dependency.collection(Store),
        Dependency.map(Store),
      ]) {
        expect(
          factory.dependencyCandidateNames(dependency, requester: 'shop'),
          ['mainStore', 'spareStore'],
        );
      }
    });

    test('a resource names its bean, or falls back to the type', () {
      final factory = _factory(primary: true);
      expect(
        factory.dependencyCandidateNames(
          const Dependency.resource(Store, 'spareStore'),
        ),
        ['spareStore'],
      );
      expect(
        factory.dependencyCandidateNames(
          const Dependency.resource(Store, 'other', fallbackToType: true),
        ),
        ['mainStore'],
      );
      expect(
        factory.dependencyCandidateNames(
          const Dependency.resource(Store, 'other'),
        ),
        isEmpty,
      );
    });

    test('a value, a missing bean or a resolvable dependency name none', () {
      final factory = _factory()
        ..registerResolvableDependency(String, 'resolvable');
      expect(
        factory.dependencyCandidateNames(const Dependency.value(r'${x}')),
        isEmpty,
      );
      expect(
        factory.dependencyCandidateNames(const Dependency(int)),
        isEmpty,
      );
      expect(
        factory.dependencyCandidateNames(const Dependency(String)),
        isEmpty,
      );
    });

    test('a bean of the parent factory is no local name', () {
      final parent = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<Shop>(name: 'shop', create: (_) => Shop()),
        );
      final child = DefaultListableBeanFactory(parentBeanFactory: parent);
      expect(child.dependencyCandidateNames(const Dependency(Shop)), isEmpty);
    });
  });

  group('removeBeanPostProcessor', () {
    test('the beans created after the removal no longer pass through it', () {
      final recorder = _Recorder();
      final factory = _factory(primary: true)
        ..addBeanPostProcessor(recorder)
        ..getBean<Shop>();
      expect(factory.removeBeanPostProcessor(recorder), isTrue);
      expect(factory.beanPostProcessors, isNot(contains(recorder)));
      factory.getBean<Store>();
      expect(recorder.created, ['shop']);
      expect(factory.removeBeanPostProcessor(recorder), isFalse);
    });
  });
}
