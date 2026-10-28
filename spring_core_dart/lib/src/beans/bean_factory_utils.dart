import 'package:spring_core_dart/src/beans/bean_factory.dart';

/// Helpers that list beans across a whole hierarchy of factories, and that
/// handle the `&` prefix of factory bean names.
///
/// The listing methods of `ListableBeanFactory` see only the factory's own
/// beans. When contexts are nested (a child context on top of a shared
/// parent), code that must find every bean of a type, wherever it is
/// declared, uses these helpers. A bean hides the beans with the same name
/// in its ancestors. Applications with a single context do not need them.
///
/// ```dart
/// // In a child context: the greeters of the child and of its parents.
/// final names = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
///   childContext,
///   Greeter,
/// );
/// final greeters =
///     BeanFactoryUtils.beansOfTypeIncludingAncestors<Greeter>(childContext);
/// ```
///
/// Spring (Java):
/// ```java
/// String[] names = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
///     childContext, Greeter.class);
/// Map<String, Greeter> greeters =
///     BeanFactoryUtils.beansOfTypeIncludingAncestors(
///         childContext, Greeter.class);
/// ```
abstract final class BeanFactoryUtils {
  /// Whether [name] asks for a factory bean itself, that is, starts with
  /// `&`.
  static bool isFactoryDereference(String name) =>
      name.startsWith(BeanFactory.factoryBeanPrefix);

  /// [name] without its leading `&` characters: the bean name that `&name`
  /// refers to.
  static String transformedBeanName(String name) {
    var result = name;
    while (isFactoryDereference(result)) {
      result = result.substring(1);
    }
    return result;
  }

  /// The names of the beans of [type] in [factory] and its ancestors,
  /// without creating them: [factory]'s own names first (as
  /// `ListableBeanFactory.getBeanNamesForType` lists them), then the
  /// parents' names that no factory below declares.
  static List<String> beanNamesForTypeIncludingAncestors(
    ListableBeanFactory factory,
    Type type, {
    bool includeNonSingletons = true,
  }) {
    final result = factory.getBeanNamesForType(
      type,
      includeNonSingletons: includeNonSingletons,
    );
    if (factory case HierarchicalBeanFactory(
      parentBeanFactory: final ListableBeanFactory parent,
    )) {
      final names = [...result];
      for (final name in beanNamesForTypeIncludingAncestors(
        parent,
        type,
        includeNonSingletons: includeNonSingletons,
      )) {
        if (!names.contains(name) &&
            !(factory as HierarchicalBeanFactory).containsLocalBean(name)) {
          names.add(name);
        }
      }
      return names;
    }
    return result;
  }

  /// The beans of [T] in [factory] and its ancestors, by name, created if
  /// needed. A bean hides a parent's bean with the same name.
  static Map<String, T> beansOfTypeIncludingAncestors<T extends Object>(
    ListableBeanFactory factory, {
    bool includeNonSingletons = true,
  }) {
    final result = {
      ...factory.getBeansOfType<T>(includeNonSingletons: includeNonSingletons),
    };
    if (factory case HierarchicalBeanFactory(
      parentBeanFactory: final ListableBeanFactory parent,
    )) {
      final inherited = beansOfTypeIncludingAncestors<T>(
        parent,
        includeNonSingletons: includeNonSingletons,
      );
      for (final MapEntry(key: name, value: bean) in inherited.entries) {
        if (!result.containsKey(name) &&
            !(factory as HierarchicalBeanFactory).containsLocalBean(name)) {
          result[name] = bean;
        }
      }
    }
    return result;
  }
}
