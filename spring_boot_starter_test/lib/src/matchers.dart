import 'package:matcher/matcher.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' hide Description;
import 'package:spring_boot_starter_test/src/application_context_runner.dart';
import 'package:spring_boot_starter_test/src/spring_boot_test.dart';

/// Matches a context with exactly one bean of [T] (AssertJ's
/// `assertThat(context).hasSingleBean(T.class)`).
///
/// Works on an [AssertableApplicationContext], a [SpringBootTestContext] or
/// any [ListableBeanFactory]. Like AssertJ, the beans of the parent
/// contexts count too (`withParent`).
///
/// ```dart
/// expect(context, hasSingleBean<MessageSource>());
/// ```
Matcher hasSingleBean<T extends Object>() =>
    _BeanCount<T>((count) => count == 1, 'exactly one bean of $T');

/// Matches a context with at least one bean of [T].
Matcher hasBean<T extends Object>() =>
    _BeanCount<T>((count) => count > 0, 'a bean of $T');

/// Matches a context without beans of [T] (`doesNotHaveBean`).
Matcher doesNotHaveBean<T extends Object>() =>
    _BeanCount<T>((count) => count == 0, 'no bean of $T');

/// Matches a context with a bean called [name].
Matcher hasBeanNamed(String name) => _HasBeanNamed(name);

/// Matches an [AssertableApplicationContext] that failed to start, with a
/// failure matching [failure] if given.
///
/// ```dart
/// expect(context, hasFailed(isA<BeanCreationException>()));
/// ```
Matcher hasFailed([Object? failure]) =>
    _HasFailed(failure == null ? null : wrapMatcher(failure));

ListableBeanFactory? _factory(Object? item) => switch (item) {
  AssertableApplicationContext(hasFailed: false) => item.context,
  SpringBootTestContext() => item.context,
  ListableBeanFactory() => item,
  _ => null,
};

// The names of the beans of [type] in [factory] and its ancestors (Spring's
// `BeanFactoryUtils.beanNamesForTypeIncludingAncestors`, the scope
// AssertJ's `hasSingleBean` / `doesNotHaveBean` use): a parent's bean
// hidden by a local bean of the same name is not counted twice.
List<String> _namesIncludingAncestors(ListableBeanFactory factory, Type type) {
  final names = [...factory.getBeanNamesForType(type)];
  if (factory case final HierarchicalBeanFactory local
      when local.parentBeanFactory is ListableBeanFactory) {
    final parent = local.parentBeanFactory! as ListableBeanFactory;
    for (final name in _namesIncludingAncestors(parent, type)) {
      if (!names.contains(name) && !local.containsLocalBean(name)) {
        names.add(name);
      }
    }
  }
  return names;
}

final class _BeanCount<T extends Object> extends Matcher {
  _BeanCount(this._test, this._description);

  final bool Function(int count) _test;
  final String _description;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final factory = _factory(item);
    return factory != null &&
        _test(_namesIncludingAncestors(factory, T).length);
  }

  @override
  Description describe(Description description) =>
      description.add('a context with $_description');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item case AssertableApplicationContext(:final startupFailure?)) {
      return mismatchDescription.add('failed to start: $startupFailure');
    }
    final factory = _factory(item);
    if (factory == null) {
      return mismatchDescription.add('is not an application context');
    }
    final names = _namesIncludingAncestors(factory, T);
    return mismatchDescription.add(
      names.isEmpty
          ? 'has no bean of $T'
          : 'has beans of $T: ${names.join(', ')}',
    );
  }
}

final class _HasBeanNamed extends Matcher {
  _HasBeanNamed(this._name);

  final String _name;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      _factory(item)?.containsBean(_name) ?? false;

  @override
  Description describe(Description description) =>
      description.add('a context with a bean named "$_name"');
}

final class _HasFailed extends Matcher {
  _HasFailed(this._failure);

  final Matcher? _failure;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is AssertableApplicationContext &&
      item.hasFailed &&
      (_failure?.matches(item.startupFailure, matchState) ?? true);

  @override
  Description describe(Description description) {
    description.add('a context that failed to start');
    final failure = _failure;
    return failure == null
        ? description
        : description.add(' with ').addDescriptionOf(failure);
  }

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) => switch (item) {
    AssertableApplicationContext(hasFailed: false) => mismatchDescription.add(
      'started successfully',
    ),
    AssertableApplicationContext(:final startupFailure) =>
      mismatchDescription.add('failed with $startupFailure'),
    _ => mismatchDescription.add('is not an AssertableApplicationContext'),
  };
}
