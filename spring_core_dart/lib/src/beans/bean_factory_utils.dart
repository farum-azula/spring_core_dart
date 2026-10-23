import 'package:spring_core_dart/src/beans/bean_factory.dart';

/// Lookups over a whole factory hierarchy, like Spring's
/// `BeanFactoryUtils`.
///
/// `ListableBeanFactory` methods list local beans only; these helpers add
/// the beans of the parent factories. A bean hides the beans with the same
/// name in its ancestors.
///
/// ```dart
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
///     BeanFactoryUtils.beansOfTypeIncludingAncestors(childContext, Greeter.class);
/// ```
abstract final class BeanFactoryUtils {
  /// Whether [name] refers to a factory bean itself (`&name`).
  static bool isFactoryDereference(String name) =>
      name.startsWith(BeanFactory.factoryBeanPrefix);

  /// [name] without its `&` prefixes.
  static String transformedBeanName(String name) {
    var result = name;
    while (isFactoryDereference(result)) {
      result = result.substring(1);
    }
    return result;
  }

  /// Names of the beans of [type] in [factory] and its ancestors: local
  /// names first (see `ListableBeanFactory.getBeanNamesForType`).
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

  /// The beans of [T] in [factory] and its ancestors, by name (creates
  /// them).
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
