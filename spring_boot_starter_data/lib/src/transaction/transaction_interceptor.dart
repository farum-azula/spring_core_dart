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
/// - An error rolls back, unless the entry of `rollbackFor` or
///   `noRollbackFor` closest to its class (the type itself or the nearest
///   supertype listed) is in `noRollbackFor`: then the transaction commits
///   and the error is thrown again. Types are matched with subtypes through
///   [Introspector.isInstanceOf], the closest found with
///   [Introspector.typeDepth], as Spring's
///   `RuleBasedTransactionAttribute` does.
/// - The transaction is named `Class.method`.
///
/// A call made from inside the same class does not go through the proxy,
/// so it does not run in a transaction of its own (Spring's proxy rule).
///
/// Use `TransactionValidator` to have mistakes (a method that is not
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
    Introspector? introspector,
  }) : _fixedManager = transactionManager,
       introspector = introspector ?? Introspector.shared {
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
  final Introspector introspector;

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
    return TransactionPlan._(
      annotation,
      annotation.definition('${signature.targetType}.${signature.name}'),
      (error) => _rollsBackOn(annotation, error),
    );
  }

  // Spring's RuleBasedTransactionAttribute: of the entries of `rollbackFor`
  // and `noRollbackFor` that match the error, the one whose type is the
  // closest to the error's class decides; with none, the error rolls back.
  // The closest is the deepest in the hierarchy (the generator registers
  // each listed type's depth, see `BeanModule.typeDepths`: an error is an
  // instance of both only when one is a subtype of the other, or the
  // two are the same type). On a tie the first entry wins, `rollbackFor`
  // before `noRollbackFor`, as in Spring; a type without a registered depth
  // counts as 0, so `rollbackFor` wins among those.
  bool _rollsBackOn(Transactional annotation, Object error) {
    var closest = -1;
    var rollback = true;
    void consider(List<Type> types, bool rolls) {
      for (final type in types) {
        if (!introspector.isInstanceOf(type, error)) {
          continue;
        }
        final depth = introspector.typeDepth(type) ?? 0;
        if (depth > closest) {
          closest = depth;
          rollback = rolls;
        }
      }
    }

    consider(annotation.rollbackFor, true);
    consider(annotation.noRollbackFor, false);
    return rollback;
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
