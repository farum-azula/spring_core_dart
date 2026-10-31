import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_template.dart';

/// The rule that picks which bean methods the [TransactionInterceptor]
/// wraps: the public methods with `@Transactional`, or whose class (or a
/// superclass) has it.
///
/// The starter pairs it with the interceptor in an advisor. Applications do
/// not use it, unless they set transactions up without the starter's
/// auto-configuration.
///
/// ```dart
/// DefaultPointcutAdvisor(const TransactionAnnotationPointcut(), interceptor);
/// ```
///
/// Spring (Java): `AnnotationTransactionAttributeSource`, behind the
/// `BeanFactoryTransactionAttributeSourceAdvisor` that
/// `@EnableTransactionManagement` registers.
final class TransactionAnnotationPointcut implements AnnotationPointcut {
  /// The pointcut; it has no settings.
  const TransactionAnnotationPointcut();

  /// The annotations this pointcut matches; the generator reads them to
  /// give a proxy class only to the beans that carry one.
  static const List<Type> annotationTypes = [Transactional];

  /// The `@Transactional` that applies to [signature]: the one on the
  /// method (or on the method it overrides), else the nearest one on its
  /// class or a superclass; null when there is none, for a getter or a
  /// setter, for a protected member and for the members of `Object`.
  static Transactional? transactionalOf(MethodSignature signature) {
    if (signature.kind != MemberKind.method ||
        signature.isProtected ||
        _objectMembers.contains(signature.name)) {
      return null;
    }
    return signature.annotations.whereType<Transactional>().firstOrNull ??
        signature.mergedAnnotations.whereType<Transactional>().firstOrNull ??
        signature.implementingTypeHierarchyAnnotations
            .whereType<Transactional>()
            .firstOrNull;
  }

  static const _objectMembers = {'toString', 'noSuchMethod', '==', 'hashCode'};

  @override
  bool matches(MethodSignature signature, String beanName) =>
      transactionalOf(signature) != null;

  @override
  String toString() => 'TransactionAnnotationPointcut';
}

/// What the [TransactionInterceptor] knows of one `@Transactional` method:
/// the annotation, the definition of its transactions, and which errors
/// roll back.
final class TransactionPlan {
  TransactionPlan._(this.annotation, this.definition, this._rollbackOn);

  /// The annotation that applies.
  final Transactional annotation;

  /// The settings of the transactions of the method (named
  /// `Class.method`).
  final TransactionDefinition definition;

  final bool Function(Object error) _rollbackOn;

  /// Whether [error], thrown by the method, rolls the transaction back.
  bool rollsBackOn(Object error) => _rollbackOn(error);
}

/// The code that runs around every call of a `@Transactional` method: it
/// opens a transaction as the annotation says, runs the method in it, and
/// commits when the method's `Future` completes or rolls back when it
/// fails.
///
/// - The transaction manager is the annotation's `transactionManager` (a
///   bean name or qualifier) or, when empty, the only (or primary)
///   `PlatformTransactionManager` bean.
/// - An error rolls back, unless its type (or a supertype) is in
///   `noRollbackFor` and no entry of `rollbackFor` matches it: then the
///   transaction commits and the error is thrown again. Types are matched
///   with subtypes through [BeanIntrospector.isInstanceOf].
/// - The transaction is named `Class.method`.
///
/// A call made from inside the same class does not go through the proxy,
/// so it does not run in a transaction of its own (Spring's proxy rule).
///
/// Use [TransactionValidator] to have mistakes (a method that is not
/// async, an unknown manager) stop the startup.
///
/// Spring (Java):
/// `org.springframework.transaction.interceptor.TransactionInterceptor`.
final class TransactionInterceptor implements MethodInterceptor {
  /// An interceptor. [beanFactory] finds the transaction manager beans;
  /// without it pass a [transactionManager] (used whatever the annotation
  /// names). [introspector] matches the exception types of
  /// `rollbackFor` and `noRollbackFor`.
  TransactionInterceptor({
    this.beanFactory,
    PlatformTransactionManager? transactionManager,
    BeanIntrospector? introspector,
  }) : _fixedManager = transactionManager,
       introspector = introspector ?? BeanIntrospector.shared {
    if (beanFactory == null && transactionManager == null) {
      throw ArgumentError(
        'Give a beanFactory or a transactionManager to find the transaction '
        'manager with',
      );
    }
  }

  /// Whether one manager is used whatever the annotations name.
  bool get hasFixedManager => _fixedManager != null;

  /// Where the transaction manager beans are found.
  final BeanFactory? beanFactory;

  /// Matches exception types with subtypes.
  final BeanIntrospector introspector;

  final PlatformTransactionManager? _fixedManager;
  final _plans = Map<MethodSignature, TransactionPlan?>.identity();
  final _managers = <String, PlatformTransactionManager>{};

  /// The plan of [signature], or null when it is not transactional.
  /// Computed once per member.
  TransactionPlan? planOf(MethodSignature signature) =>
      _plans.putIfAbsent(signature, () => _plan(signature));

  TransactionPlan? _plan(MethodSignature signature) {
    final annotation = TransactionAnnotationPointcut.transactionalOf(
      signature,
    );
    if (annotation == null) {
      return null;
    }
    bool matches(List<Type> types, Object error) =>
        types.any((type) => introspector.isInstanceOf(type, error));
    return TransactionPlan._(
      annotation,
      annotation.definition('${signature.targetType}.${signature.name}'),
      (error) =>
          matches(annotation.rollbackFor, error) ||
          !matches(annotation.noRollbackFor, error),
    );
  }

  /// The manager named [name] by `transactionManager` (empty: the primary
  /// one). Throws a [StateError] for an unknown or ambiguous one.
  PlatformTransactionManager managerFor(String name) =>
      _fixedManager ?? (_managers[name] ??= _resolve(name));

  PlatformTransactionManager _resolve(String name) {
    final factory = beanFactory!;
    try {
      return name.isEmpty
          ? factory.getBean<PlatformTransactionManager>()
          : factory.getBean<PlatformTransactionManager>(qualifier: name);
    } on Object catch (error) {
      throw StateError(
        name.isEmpty
            ? 'No single PlatformTransactionManager bean for @Transactional: '
                  'declare one, mark one @Primary, or name it with '
                  '@Transactional(transactionManager: ...): $error'
            : "No PlatformTransactionManager bean '$name' for "
                  "@Transactional(transactionManager: '$name'): $error",
      );
    }
  }

  @override
  Object? invoke(MethodInvocation invocation) {
    final plan = planOf(invocation.signature);
    if (plan == null) {
      return invocation.proceed();
    }
    final PlatformTransactionManager manager;
    try {
      manager = managerFor(plan.annotation.transactionManager);
    } on Object catch (error, stackTrace) {
      return Future<Object?>.error(error, stackTrace);
    }
    return runInTransaction<Object?>(
      manager,
      plan.definition,
      (_) => invocation.proceed(),
      rollbackOn: plan.rollsBackOn,
    );
  }
}

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
