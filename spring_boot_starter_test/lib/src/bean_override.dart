import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Spring's bean name of a class, as `ApplicationContextRunner.withBean`
/// and [BeanOverride] name a new bean of [type]: lower camel case
/// (`HttpClient` → `httpClient`), a name starting with two capitals stays
/// (`URLService`, `Introspector.decapitalize`), type arguments are left
/// out (`Cache<String>` → `cache`).
String defaultBeanName(String type) {
  final generic = type.indexOf('<');
  final simple = generic < 0 ? type : type.substring(0, generic);
  if (simple.isEmpty) {
    return 'bean';
  }
  if (simple.length > 1 &&
      simple[1].toUpperCase() == simple[1] &&
      simple[1].toLowerCase() != simple[1] &&
      simple[0].toUpperCase() == simple[0]) {
    return simple;
  }
  return simple[0].toLowerCase() + simple.substring(1);
}

/// Replaces the bean of type [T] with [instance] in a test context, like
/// Spring's `@TestBean` / `@MockitoBean` (bean overriding).
///
/// The original definition is removed before any bean is created, so the
/// real object (and whatever it would connect to) is never built. The
/// replacement keeps the original's name, aliases, qualifiers and
/// `@Primary` / `@Fallback` flags, so `@Qualifier` injection points still find it. Without
/// an existing bean of [T] the instance is simply registered.
///
/// ```dart
/// final app = springBootTest(
///   springApplication,
///   overrides: [
///     BeanOverride<PaymentGateway>(FakeGateway()),        // the only one
///     BeanOverride<Mailer>(MockMailer(), name: 'mailer'),  // one of many
///   ],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @MockitoBean PaymentGateway gateway;
/// ```
final class BeanOverride<T extends Object> {
  /// Overrides the bean of type [T] (or the bean called [name]).
  const BeanOverride(this.instance, {this.name});

  /// The object to inject instead of the real bean.
  final T instance;

  /// The bean to replace when several beans of [T] exist; also the name of
  /// a newly registered bean (default: [defaultBeanName] of [T], the rule
  /// of `ApplicationContextRunner.withBean`).
  final String? name;

  /// The overridden type.
  Type get type => T;

  /// Replaces the definition in [registry] ([factory] finds the beans of
  /// [T]); called by [BeanOverrideProcessor].
  void apply(
    ConfigurableListableBeanFactory factory,
    BeanDefinitionRegistry registry,
  ) {
    final candidates = factory.getBeanNamesForType(T);
    final String target;
    final name = this.name;
    if (name != null) {
      target = name;
    } else if (candidates.length > 1) {
      throw StateError(
        'BeanOverride<$T>: expected a single bean of $T to replace but '
        'found ${candidates.length}: ${candidates.join(', ')}. '
        'Pass name: to choose one.',
      );
    } else {
      target = candidates.isEmpty ? defaultBeanName('$T') : candidates.single;
    }
    final original = registry.containsBeanDefinition(target)
        ? registry.getBeanDefinition(target)
        : null;
    if (original != null) {
      registry.removeBeanDefinition(target);
    }
    final instance = this.instance;
    registry.registerBeanDefinition(
      BeanDefinition<T>(
        name: target,
        types: [T],
        create: (_) => instance,
        primary: original?.primary ?? false,
        fallback: original?.fallback ?? false,
        autowireCandidate: original?.autowireCandidate ?? true,
        order: original?.order,
        qualifiers: original?.qualifiers ?? const {},
        aliases: original?.aliases ?? const [],
        source: 'BeanOverride<$T>',
      ),
    );
  }

  @override
  String toString() => 'BeanOverride<$T>(${name ?? ''})';
}

/// Applies [overrides] after every registry post-processor ran, before any
/// application bean is created.
final class BeanOverrideProcessor
    implements BeanDefinitionRegistryPostProcessor {
  /// Creates the processor.
  BeanOverrideProcessor(List<BeanOverride<Object>> overrides)
    : overrides = List.unmodifiable(overrides);

  /// The overrides, applied in order.
  final List<BeanOverride<Object>> overrides;

  BeanDefinitionRegistry? _registry;

  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) =>
      _registry = registry;

  // Here, not in postProcessBeanDefinitionRegistry: the application's own
  // registry post-processors have registered their beans by now.
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory factory) {
    final registry =
        _registry ??
        (factory is BeanDefinitionRegistry
            ? factory as BeanDefinitionRegistry
            : throw StateError('BeanOverride needs a BeanDefinitionRegistry'));
    for (final override in overrides) {
      override.apply(factory, registry);
    }
  }
}
