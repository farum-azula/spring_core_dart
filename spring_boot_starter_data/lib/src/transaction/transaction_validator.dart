import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_interceptor.dart';

/// Checks the `@Transactional` methods of the application when it
/// starts, so a mistake stops the start (with every problem listed)
/// instead of failing the first call:
///
/// - a method that does not return a `Future` (a synchronous one, or one
///   returning a `Stream`): the transaction could not tell when the work
///   ends;
/// - a `transactionManager` that names no `PlatformTransactionManager`
///   bean, or several, or an empty one with no single manager to use.
///
/// It is a bean post-processor. When the first bean with a generated proxy
/// that has `@Transactional` methods is created, it reads the definitions
/// of all such beans, once, and throws with every problem it found. It
/// creates no bean. The starter registers it; applications do not use it.
///
/// Spring (Java): none; Spring fails at the first call (a reactive return
/// type needs the reactive manager), or builds the proxy without
/// complaint.
final class TransactionValidator extends BeanPostProcessor
    implements BeanFactoryAware {
  /// A validator; it finds the beans through the factory the container
  /// gives it.
  TransactionValidator();

  BeanFactory? _beanFactory;
  late final List<String> _problems = _check();

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  /// The problems found in the application (empty when it is right).
  List<String> get problems => _problems;

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    final factory = _beanFactory;
    if (factory is! ConfigurableListableBeanFactory ||
        !factory.containsBeanDefinition(beanName)) {
      return bean;
    }
    final signatures =
        factory.getBeanDefinition(beanName).aopProxy?.signatures ??
        const <MethodSignature>[];
    if (signatures.any(
      (s) => TransactionAnnotationPointcut.transactionalOf(s) != null,
    )) {
      if (problems.isNotEmpty) {
        throw StateError(
          'Invalid @Transactional configuration:\n'
          '${problems.map((p) => '  - $p').join('\n')}',
        );
      }
    }
    return bean;
  }

  List<String> _check() {
    final factory = _beanFactory;
    if (factory is! ConfigurableListableBeanFactory) {
      return const [];
    }
    final problems = <String>[];
    final checkedManagers = <String, String?>{};
    for (final name in factory.beanDefinitionNames) {
      final signatures =
          factory.getBeanDefinition(name).aopProxy?.signatures ??
          const <MethodSignature>[];
      for (final signature in signatures) {
        final annotation = TransactionAnnotationPointcut.transactionalOf(
          signature,
        );
        if (annotation == null) {
          continue;
        }
        final member = '${signature.targetType}.${signature.name}';
        final returnType = signature.returnType.split('<').first;
        if (returnType != 'Future') {
          problems.add(
            '@Transactional $member returns '
            '${signature.returnType == 'dynamic' ? 'dynamic' : returnType}'
            ', not a Future: the transaction ends when the Future completes '
            '(a ${returnType == 'Stream' ? 'Stream' : 'synchronous method'} '
            'cannot be covered); make it async',
          );
        }
        final manager = annotation.transactionManager;
        final failure = checkedManagers.putIfAbsent(
          manager,
          () => _managerProblem(factory, manager),
        );
        if (failure != null) {
          problems.add('@Transactional $member: $failure');
        }
      }
    }
    return problems;
  }

  // Null when [name] (empty: the primary) selects exactly one manager.
  static String? _managerProblem(
    ConfigurableListableBeanFactory factory,
    String name,
  ) {
    final candidates = <(String, BeanDefinition<Object>?, List<String>)>[];
    for (
      ConfigurableListableBeanFactory? level = factory;
      level != null;
      level = switch (level.parentBeanFactory) {
        final ConfigurableListableBeanFactory parent => parent,
        _ => null,
      }
    ) {
      for (final candidate in level.getBeanNamesForType(
        PlatformTransactionManager,
      )) {
        final definition = level.containsBeanDefinition(candidate)
            ? level.getBeanDefinition(candidate)
            : null;
        if (definition == null ||
            (definition.autowireCandidate && definition.defaultCandidate)) {
          candidates.add((candidate, definition, level.getAliases(candidate)));
        }
      }
    }
    if (name.isEmpty) {
      if (candidates.isEmpty) {
        return 'no PlatformTransactionManager bean: declare one';
      }
      if (candidates.length == 1 ||
          candidates.where((c) => c.$2?.primary ?? false).length == 1 ||
          candidates.where((c) => !(c.$2?.fallback ?? false)).length == 1) {
        return null;
      }
      return 'several PlatformTransactionManager beans '
          '(${candidates.map((c) => c.$1).join(', ')}): mark one @Primary, '
          'or name one with @Transactional(transactionManager: ...)';
    }
    final named = [
      for (final (candidate, definition, aliases) in candidates)
        if (candidate == name ||
            aliases.contains(name) ||
            (definition?.qualifiers.contains(name) ?? false))
          candidate,
    ];
    if (named.isEmpty) {
      return "no PlatformTransactionManager bean or qualifier named '$name'"
          ' (transactionManager: ...)';
    }
    if (named.length > 1) {
      return "several PlatformTransactionManager beans match '$name' "
          '(${named.join(', ')})';
    }
    return null;
  }
}
