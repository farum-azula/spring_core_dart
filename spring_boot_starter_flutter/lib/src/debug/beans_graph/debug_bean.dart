import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_role.dart';

/// One bean (or Spring widget) of a [DebugBeanGraphSnapshot]: what it is,
/// where it comes from, how it was created and what advises it.
final class DebugBean {
  /// A bean of these values.
  const DebugBean({
    required this.name,
    required this.type,
    required this.role,
    required this.module,
    required this.application,
    required this.scope,
    this.lazy = false,
    this.primary = false,
    this.instances = 0,
    this.source,
    this.description,
    this.beansType,
    this.annotations = const [],
    this.advisors = const [],
    this.advisedMethods = const [],
    this.conditions = const [],
    this.eventListeners = const [],
    this.publishesEvents = false,
    this.creationOrder,
    this.createdAt,
    this.creationTime,
  });

  /// The bean's name; for a widget, its class
  /// (`package:app/basket/basket_badge.dart#BasketBadge`).
  final String name;

  /// The bean's class (`Session`), or the widget's.
  final String type;

  /// What it is for.
  final DebugBeanRole role;

  /// The [DebugBeanModule] it belongs to.
  final String module;

  /// Whether the application defined it (its own classes and `@Bean`
  /// methods), not the framework or an auto-configuration.
  final bool application;

  /// The scope: `singleton`, `prototype`, a custom scope's name (`route`,
  /// `branch`), or `widget` for a widget.
  final String scope;

  /// Whether a singleton is created on first use (`@Lazy()`).
  final bool lazy;

  /// Whether it wins among beans of one type (`@Primary()`).
  final bool primary;

  /// How many instances there are now: `0` or `1` for a singleton; for a
  /// bean of a custom scope those created and not destroyed while the
  /// graph ran (the scope does not tell of older ones); for a prototype
  /// those created while the graph ran (the container does not follow a
  /// prototype after its creation).
  final int instances;

  /// Where the definition comes from (`package:app/x.dart#Session`).
  final String? source;

  /// Its `@Description`.
  final String? description;

  /// For a widget: the record type of its beans, as the widget's
  /// `beansType` gives it, to find the node of a widget on screen.
  final Type? beansType;

  /// The annotations of its class (of the method, for a `@Bean`), by type
  /// name: `Service`, `Transactional`, `Log`.
  final List<String> annotations;

  /// The advisors around the created bean, outermost first: the advisor
  /// bean's name (`notifyListenersAdvisor`), else the advice's type. Empty
  /// for a bean not created yet, or not proxied.
  final List<String> advisors;

  /// The members the bean's generated proxy has, with their annotations
  /// (`@Transactional`, `@Cacheable`, `@PreAuthorize`, `@SignalBuffer`,
  /// `@Observed`...): known before the bean exists.
  final List<DebugBeanAdvisedMethod> advisedMethods;

  /// The conditions it was registered under, with their outcome (each
  /// matched, or it would not be here).
  final List<DebugBeanCondition> conditions;

  /// Its `@EventListener` methods (`Session.restore`).
  final List<String> eventListeners;

  /// Whether it injects an `ApplicationEventPublisher`.
  final bool publishesEvents;

  /// Its place among the singletons in the order they were created
  /// (`0` first); `null` when not created.
  final int? creationOrder;

  /// When its creation started in the application's start, from the
  /// startup trace (`spring.beans.instantiate`): only for the singletons
  /// created during the start, with the trace or the timeline on.
  final Duration? createdAt;

  /// How long its creation took (the beans it created on the way
  /// included), from the same trace.
  final Duration? creationTime;

  /// Whether an instance exists now.
  bool get created => instances > 0;

  /// Whether a singleton waits for its first use (lazy, not created).
  bool get pending => lazy && !created;

  @override
  String toString() => 'DebugBean($name: $type, ${role.name}, $module)';
}

/// A member of a bean's generated proxy and its annotations.
final class DebugBeanAdvisedMethod {
  /// The member [name] with [annotations].
  const DebugBeanAdvisedMethod(this.name, this.annotations);

  /// The member's name.
  final String name;

  /// Its annotations by type name (`Transactional`).
  final List<String> annotations;

  @override
  String toString() => '$name ${annotations.map((a) => '@$a').join(' ')}';
}

/// A condition evaluated for a bean, as the condition evaluation report
/// gives it.
final class DebugBeanCondition {
  /// The [condition] and whether it [matched].
  const DebugBeanCondition(this.condition, {required this.matched});

  /// The condition, as the report describes it (`@Profile(dev)`,
  /// `@ConditionalOnProperty(...)`).
  final String condition;

  /// Whether it matched.
  final bool matched;

  @override
  String toString() => '$condition ${matched ? 'matched' : 'did not match'}';
}
