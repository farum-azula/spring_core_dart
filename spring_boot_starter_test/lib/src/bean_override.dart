import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The bean name Spring would give a class, used for a bean that
/// `ApplicationContextRunner.withBean` or a [BeanOverride] adds without a
/// `name`.
///
/// The type name in lower camel case (`HttpClient` → `httpClient`); a name
/// that starts with two capitals stays as it is (`URLService`, Java's
/// `Introspector.decapitalize`); type arguments are left out
/// (`Cache<String>` → `cache`). Tests need it to look such a bean up by
/// name.
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

/// Replaces one of the application's beans with an object of the test, a
/// fake or a mock, in a context started by `springBootTest` or
/// `ApplicationContextRunner`.
///
/// Use it when the real bean talks to something a test cannot use: a
/// payment provider, the wall clock, a mail server. The original
/// definition is removed before any bean is created, so the real object
/// (and whatever it would connect to) is never built, and every bean that
/// injects it gets [instance]. The replacement keeps the original's name,
/// aliases, qualifiers, order and `@Primary` / `@Fallback` flags, so
/// `@Qualifier` injection points still find it. It is registered under
/// [T] only (use [BeanOverride.named] to keep the original's types).
///
/// Which bean: the one called [name] (or whose alias it is) when given;
/// else the only bean of [T]; among several, the single `@Primary` one,
/// and a [StateError] listing them when there is no single primary.
/// Without any bean of [T], [instance] is simply registered as a new
/// bean. Any mock library works (for example `mocktail`); reset shared
/// mocks in `setUp`, since nothing is reset between tests.
///
/// ```dart
/// final gateway = FakeGateway();
/// final app = springBootTest(
///   springApplication,
///   overrides: [
///     // No real payment: the checkout charges the fake.
///     BeanOverride<PaymentGateway>(gateway),
///     // One of several mailers, chosen by name.
///     BeanOverride<Mailer>(MockMailer(), name: 'mailer'),
///   ],
/// );
/// ```
///
/// Spring (Java): `@MockitoBean` and `@TestBean`. Here the object is your
/// own, ready-made; no mock is generated.
/// ```java
/// @MockitoBean PaymentGateway gateway;
/// ```
final class BeanOverride<T extends Object> {
  /// Replaces the bean of type [T], or the bean called [name], with
  /// [instance].
  const BeanOverride(this.instance, {this.name}) : _keepTypes = false;

  /// Replaces the bean called [name] with [instance], whatever the bean's
  /// type; this is what a `@TestBean(name: ...)` field generates.
  ///
  /// The replacement keeps the types the bean was registered under except
  /// its own class, and adds the class of [instance]. So a fake of another
  /// class takes its place: injection points of the interface get the fake,
  /// and a lookup of the real class finds nothing. Without such a bean,
  /// [instance] is registered under [name] with its runtime type.
  ///
  /// ```dart
  /// // The 'sandbox' PaymentGateway becomes the fake.
  /// BeanOverride.named(FakeGateway(), name: 'sandbox')
  /// ```
  const BeanOverride.named(this.instance, {required String this.name})
    : _keepTypes = true;

  final bool _keepTypes;

  // The types of a [named] override: those of the replaced bean but its own
  // class (the fake is another class; a lookup of the real class must not
  // return it), plus the fake's class.
  static List<Type> _namedTypes(
    BeanDefinition<Object>? original,
    Object instance,
  ) => {
    if (original != null)
      for (final type in original.types)
        if (type != original.beanType) type,
    instance.runtimeType,
  }.toList();

  /// The object that every injection point of the replaced bean receives.
  final T instance;

  /// The name, or an alias, of the bean to replace; when given it wins over
  /// the choice by type. Needed when several beans of [T] exist and none is
  /// `@Primary`.
  ///
  /// When no bean has that name, [instance] is added under it, next to any
  /// existing bean of [T] (a misspelt name does not fail). Without [name],
  /// a new bean is called [defaultBeanName] of [T].
  final String? name;

  /// The type the replacement is registered under, [T].
  Type get type => T;

  /// Removes the chosen bean definition from [registry] and registers
  /// [instance] in its place; [factory] is used to find the beans of [T].
  ///
  /// [BeanOverrideProcessor] calls it; tests do not. Throws a [StateError]
  /// when several beans of [T] exist and neither [name] nor a single
  /// `@Primary` one chooses.
  void apply(
    ConfigurableListableBeanFactory factory,
    BeanDefinitionRegistry registry,
  ) {
    final candidates = factory.getBeanNamesForType(T);
    final String target;
    final name = this.name;
    if (name != null) {
      // An alias overrides the bean it names (under its canonical name).
      target = registry.isAlias(name)
          ? registry.getBeanDefinition(name).name
          : name;
    } else if (candidates.length > 1) {
      // Like Spring's BeanOverrideBeanFactoryPostProcessor: the single
      // `@Primary` candidate wins.
      final primary = [
        for (final candidate in candidates)
          if (registry.containsBeanDefinition(candidate) &&
              registry.getBeanDefinition(candidate).primary)
            candidate,
      ];
      if (primary.length != 1) {
        throw StateError(
          'BeanOverride<$T>: expected a single bean of $T to replace but '
          'found ${candidates.length}: ${candidates.join(', ')}'
          '${primary.length > 1 ? ' (${primary.length} marked primary)' : ''}. '
          'Pass name: to choose one.',
        );
      }
      target = primary.single;
    } else {
      target = candidates.isEmpty ? defaultBeanName('$T') : candidates.single;
    }
    final original = registry.containsBeanDefinition(target)
        ? registry.getBeanDefinition(target)
        : null;
    // Aliases registered with registerAlias are removed with the
    // definition; keep them.
    final aliases = original == null
        ? const <String>[]
        : {...original.aliases, ...factory.getAliases(target)}.toList();
    if (original != null) {
      registry.removeBeanDefinition(target);
    }
    final instance = this.instance;
    registry.registerBeanDefinition(
      BeanDefinition<T>(
        name: target,
        types: _keepTypes ? _namedTypes(original, instance) : [T],
        create: (_) => instance,
        primary: original?.primary ?? false,
        fallback: original?.fallback ?? false,
        autowireCandidate: original?.autowireCandidate ?? true,
        order: original?.order,
        qualifiers: original?.qualifiers ?? const {},
        aliases: aliases,
        source: 'BeanOverride<$T>',
      ),
    );
  }

  @override
  String toString() => 'BeanOverride<$T>(${name ?? ''})';
}

/// The container hook that applies a list of [BeanOverride]s: after the
/// bean definitions are registered, before any application bean is
/// created.
///
/// `springBootTest(overrides:)` and
/// `ApplicationContextRunner.withBeanOverride` add it for you; tests do not
/// create it. It replaces the definitions in `postProcessBeanFactory`
/// rather than earlier, so the beans that the application's own registry
/// post-processors add can be replaced too.
final class BeanOverrideProcessor
    implements BeanDefinitionRegistryPostProcessor {
  /// A processor that applies [overrides].
  BeanOverrideProcessor(List<BeanOverride<Object>> overrides)
    : overrides = List.unmodifiable(overrides);

  /// The overrides, applied in order: when two replace the same bean, the
  /// last wins.
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
