import 'package:spring_core_dart/src/beans/aware.dart';
import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/beans/factory_bean.dart';
import 'package:spring_core_dart/src/beans/lifecycle_callbacks.dart';
import 'package:spring_core_dart/src/beans/object_provider.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Injects a `@Configurable` object the container did not create.
///
/// Generated per `@Configurable` class and registered with
/// [DefaultListableBeanFactory.registerConfigurer] (modules do this);
/// `autowireBean` then looks it up by the object's runtime type.
///
/// ```dart
/// factory.registerConfigurer(
///   ProfileScreenState,
///   (bean, r) =>
///       (bean as ProfileScreenState).profiles = r.dependency<Profiles>(),
/// );
/// ```
///
/// Spring (Java): no counterpart; Spring injects `@Configurable` objects
/// by reflection (AspectJ weaving or `autowireBean`).
typedef BeanConfigurer = void Function(
  Object bean,
  DependencyResolver resolver,
);

/// The bean container, like Spring's `DefaultListableBeanFactory`.
///
/// Usually used through an application context, which adds environment,
/// events, post-processor detection and lifecycle management. Used alone it
/// is a small, reflection-free DI container:
///
/// ```dart
/// final factory = DefaultListableBeanFactory()
///   ..registerBeanDefinition(
///     BeanDefinition<Repo>(name: 'repo', create: (_) => Repo()),
///   )
///   ..registerBeanDefinition(
///     BeanDefinition<Service>(
///       name: 'service',
///       dependencies: const [Dependency(Repo)],
///       create: (r) => Service(r.dependency<Repo>()),
///     ),
///   )
///   ..validateBeanGraph()
///   ..preInstantiateSingletons();
///
/// final service = factory.getBean<Service>();
/// factory.destroySingletons();
/// ```
///
/// Spring (Java):
/// ```java
/// DefaultListableBeanFactory factory = new DefaultListableBeanFactory();
/// factory.registerBeanDefinition("repo", new RootBeanDefinition(Repo.class));
/// factory.registerBeanDefinition("service",
///     new RootBeanDefinition(Service.class,
///         () -> new Service(factory.getBean(Repo.class))));
/// factory.preInstantiateSingletons();
///
/// Service service = factory.getBean(Service.class);
/// factory.destroySingletons();
/// ```
///
/// Differences from Spring: no reflection (definitions carry closures and
/// their lookup types), circular references are always an error (no early
/// singleton references), and a definition's `dependencies` allow
/// validating the whole graph before anything is created.
class DefaultListableBeanFactory
    implements DependencyResolver, BeanDefinitionRegistry {
  /// Creates an empty factory; lookups that fail locally go to
  /// [parentBeanFactory].
  DefaultListableBeanFactory({BeanFactory? parentBeanFactory})
    : _parent = parentBeanFactory;

  /// Whether a definition may replace another with the same name. Off by
  /// default (Spring Boot's default too); the replaced singleton is
  /// destroyed.
  bool allowBeanDefinitionOverriding = false;

  @override
  ConversionService conversionService = DefaultConversionService.sharedInstance;

  @override
  BeanExpressionResolver? beanExpressionResolver;

  BeanFactory? _parent;
  final _definitions = <String, BeanDefinition<Object>>{};
  // Type -> definitions declaring it, like Spring's `allBeanNamesByType`;
  // filled on demand and cleared whenever definitions change.
  final _byType = <Type, List<BeanDefinition<Object>>>{};
  // (type, qualifier, parameter name) -> selected definition, for lookups
  // after the configuration is frozen (the answer can no longer change).
  final _resolved =
      <(Type, String?, String?, String?), BeanDefinition<Object>>{};
  // alias -> name (which may itself be an alias).
  final _aliases = <String, String>{};
  // Names registered with registerSingleton; they survive destroySingletons.
  final _manualSingletons = <String>{};
  // Exposed singletons (possibly wrapped by post-processors).
  final _singletons = <String, Object>{};
  // The same singletons before post-processing; callbacks run on these.
  final _rawSingletons = <String, Object>{};
  // Cached products of singleton FactoryBeans, by factory bean name.
  final _factoryProducts = <String, Object>{};
  // Singletons in creation order; destroyed in reverse.
  final _creationOrder = <String>[];
  // Singletons that have destroy callbacks to run.
  final _disposables = <String>{};
  // Stack of beans being created; used for cycle detection and to know
  // which bean a lookup is made for.
  final _inCreation = <String>[];
  // bean -> beans that depend on it, and the inverse relation.
  final _dependents = <String, Set<String>>{};
  final _dependencies = <String, Set<String>>{};
  final _postProcessors = <BeanPostProcessor>[];
  final _valueResolvers = <StringValueResolver>[];
  final _scopes = <String, CustomScope>{};
  final _configurers = <Type, BeanConfigurer>{};
  final _resolvable = <Type, Object>{};

  // Raw instances of custom-scoped beans, keyed by the exposed object.
  final _scopedRaw = Expando<Object>('scopedRaw');
  final _destructionErrors = <Object>[];
  bool _frozen = false;

  /// Errors thrown by destroy callbacks during the last
  /// [destroySingletons] (they do not stop the shutdown).
  List<Object> get destructionErrors => List.unmodifiable(_destructionErrors);

  // ---------------------------------------------------------------------
  // Hierarchy
  // ---------------------------------------------------------------------

  @override
  BeanFactory? get parentBeanFactory => _parent;

  @override
  set parentBeanFactory(BeanFactory? parent) => _parent = parent;

  @override
  bool containsLocalBean(String name) {
    final canonical = _canonical(_stripFactoryPrefix(name));
    return _definitions.containsKey(canonical);
  }

  // ---------------------------------------------------------------------
  // Registry
  // ---------------------------------------------------------------------

  @override
  void registerBeanDefinition(BeanDefinition<Object> definition) {
    _checkNotFrozen();
    final name = definition.name;
    if (name.isEmpty || name.startsWith(BeanFactory.factoryBeanPrefix)) {
      throw BeanDefinitionStoreException("Invalid bean name '$name'.");
    }
    final existing = _definitions[name];
    if (existing != null) {
      // The same module registered twice (e.g. imported by two modules).
      if (definition.source != null && existing.source == definition.source) {
        return;
      }
      if (!allowBeanDefinitionOverriding) {
        throw BeanDefinitionOverrideException(name, definition.source);
      }
      _destroySingleton(name);
      _forgetManualSingleton(name);
    }
    if (_aliases.containsKey(name)) {
      throw BeanDefinitionOverrideException(name, definition.source);
    }
    _definitions[name] = definition;
    _clearByTypeCache();
    for (final alias in definition.aliases) {
      registerAlias(name, alias);
    }
  }

  @override
  void removeBeanDefinition(String name) {
    _checkNotFrozen();
    final canonical = _canonical(name);
    if (!_definitions.containsKey(canonical)) {
      throw NoSuchBeanDefinitionException.named(name);
    }
    _destroySingleton(canonical);
    _forgetManualSingleton(canonical);
    _definitions.remove(canonical);
    _clearByTypeCache();
    _aliases.removeWhere((_, target) => target == canonical);
  }

  /// Drops a `registerSingleton` object: it is not in the creation order,
  /// so `_destroySingleton` does not see it.
  void _forgetManualSingleton(String name) {
    if (_manualSingletons.remove(name)) {
      _singletons.remove(name);
      _rawSingletons.remove(name);
    }
  }

  @override
  BeanDefinition<Object> getBeanDefinition(String name) =>
      _definitions[_canonical(name)] ??
      (throw NoSuchBeanDefinitionException.named(name));

  @override
  bool containsBeanDefinition(String name) => _definitions.containsKey(name);

  @override
  List<String> get beanDefinitionNames => List.unmodifiable(_definitions.keys);

  @override
  int get beanDefinitionCount => _definitions.length;

  @override
  void registerAlias(String name, String alias) {
    if (alias == name) {
      _aliases.remove(alias);
      return;
    }
    if (_definitions.containsKey(alias)) {
      throw BeanDefinitionOverrideException(alias, 'alias for $name');
    }
    final existing = _aliases[alias];
    if (existing == name) {
      return;
    }
    if (existing != null || _canonical(name) == alias) {
      throw BeanDefinitionOverrideException(alias, 'alias for $name');
    }
    _aliases[alias] = name;
  }

  @override
  void removeAlias(String alias) {
    if (_aliases.remove(alias) == null) {
      throw ArgumentError.value(alias, 'alias', 'Alias is not registered');
    }
  }

  @override
  bool isAlias(String name) => _aliases.containsKey(name);

  @override
  bool isBeanNameInUse(String name) =>
      _definitions.containsKey(name) ||
      _aliases.containsKey(name) ||
      _dependents.containsKey(name);

  @override
  List<String> getAliases(String name) {
    final stripped = _stripFactoryPrefix(name);
    final canonical = _canonical(stripped);
    if (!_definitions.containsKey(canonical)) {
      return _parent?.getAliases(name) ?? const [];
    }
    final prefix = name.startsWith(BeanFactory.factoryBeanPrefix)
        ? BeanFactory.factoryBeanPrefix
        : '';
    return [
      if (canonical != stripped) '$prefix$canonical',
      for (final MapEntry(:key, :value) in _aliases.entries)
        if (_canonical(value) == canonical && key != stripped) '$prefix$key',
    ];
  }

  /// Follows alias chains to the bean name.
  String _canonical(String name) {
    // The hop limit guards against alias cycles.
    var current = name;
    for (var hops = 0; hops <= _aliases.length; hops++) {
      final target = _aliases[current];
      if (target == null) {
        return current;
      }
      current = target;
    }
    return current;
  }

  /// Removes any leading `&` (Spring also strips repeated prefixes).
  static String _stripFactoryPrefix(String name) {
    var result = name;
    while (result.startsWith(BeanFactory.factoryBeanPrefix)) {
      result = result.substring(1);
    }
    return result;
  }

  void _checkNotFrozen() {
    if (_frozen) {
      throw const BeanDefinitionStoreException(
        'Bean definitions are frozen; register them before refresh.',
      );
    }
  }

  @override
  void freezeConfiguration() => _frozen = true;

  @override
  bool get isConfigurationFrozen => _frozen;

  // ---------------------------------------------------------------------
  // Singleton registry
  // ---------------------------------------------------------------------

  @override
  void registerSingleton(String name, Object singleton, {List<Type>? types}) {
    // Allowed after freezeConfiguration, as in Spring: frozen applies to
    // bean definitions, not to ready-made objects.
    if (_definitions.containsKey(name) ||
        _singletons.containsKey(name) ||
        _aliases.containsKey(name)) {
      throw BeanDefinitionOverrideException(name, 'registerSingleton');
    }
    // A synthetic definition makes the object visible to lookups by type;
    // the instance is stored directly, so `create` is never called.
    _definitions[name] = BeanDefinition<Object>(
      name: name,
      types: types ?? [singleton.runtimeType],
      create: (_) => singleton,
      source: 'registerSingleton',
    );
    _clearByTypeCache();
    _manualSingletons.add(name);
    _singletons[name] = singleton;
    _rawSingletons[name] = singleton;
  }

  @override
  Object? getSingleton(String name) => _singletons[_canonical(name)];

  @override
  bool containsSingleton(String name) =>
      _singletons.containsKey(_canonical(name));

  @override
  List<String> get singletonNames => List.unmodifiable(_singletons.keys);

  // ---------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------

  @override
  void addEmbeddedValueResolver(StringValueResolver resolver) =>
      _valueResolvers.add(resolver);

  @override
  bool get hasEmbeddedValueResolver => _valueResolvers.isNotEmpty;

  @override
  String resolveEmbeddedValue(String value) {
    var result = value;
    for (final resolver in _valueResolvers) {
      result = resolver(result);
    }
    return result;
  }

  @override
  void addBeanPostProcessor(BeanPostProcessor processor) {
    // Re-adding moves the processor to the end, like Spring.
    _postProcessors
      ..remove(processor)
      ..add(processor);
  }

  @override
  int get beanPostProcessorCount => _postProcessors.length;

  /// Registered post-processors, in invocation order.
  List<BeanPostProcessor> get beanPostProcessors =>
      List.unmodifiable(_postProcessors);

  @override
  void registerScope(String name, CustomScope scope) {
    if (name == ScopeType.singleton || name == ScopeType.prototype) {
      throw ArgumentError.value(
        name,
        'name',
        'Cannot replace a built-in scope',
      );
    }
    _scopes[name] = scope;
  }

  @override
  List<String> get registeredScopeNames => List.unmodifiable(_scopes.keys);

  @override
  CustomScope? getRegisteredScope(String name) => _scopes[name];

  @override
  void registerResolvableDependency(Type type, Object value) =>
      _resolvable[type] = value;

  /// Registers how `autowireBean` injects objects of [type] (the exact
  /// runtime type). Generated modules do this for `@Configurable` classes.
  ///
  /// ```dart
  /// factory.registerConfigurer(
  ///   Holder,
  ///   (bean, r) => (bean as Holder).greeter = r.dependency<Greeter>(),
  /// );
  /// factory.autowireBean(Holder());
  /// ```
  void registerConfigurer(Type type, BeanConfigurer configurer) =>
      _configurers[type] = configurer;

  @override
  void registerDependentBean(String beanName, String dependentBeanName) {
    final bean = _canonical(beanName);
    final dependent = _canonical(dependentBeanName);
    if (bean == dependent) {
      return;
    }
    (_dependents[bean] ??= {}).add(dependent);
    (_dependencies[dependent] ??= {}).add(bean);
  }

  @override
  List<String> getDependentBeans(String beanName) =>
      List.unmodifiable(_dependents[_canonical(beanName)] ?? const {});

  @override
  List<String> getDependenciesForBean(String beanName) =>
      List.unmodifiable(_dependencies[_canonical(beanName)] ?? const {});

  @override
  bool isCurrentlyInCreation(String beanName) =>
      _inCreation.contains(_canonical(beanName));

  // ---------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------

  /// Autowire candidates of [type], filtered by [qualifier].
  ///
  /// Like Spring's `isSelfReference`, the bean being created
  /// ([requester]) is never a candidate for its own collections, and for a
  /// single dependency only when nothing else matches — so composites and
  /// decorators (`Composite(List<Greeter>)`, `Caching(Greeter delegate)`)
  /// get the other beans of their own type.
  List<BeanDefinition<Object>> _candidates(
    Type type,
    String? qualifier, {
    String? requester,
    bool single = false,
  }) {
    final all = [
      for (final definition in _definitionsOf(type))
        if ((qualifier == null
            ? definition.autowireCandidate
            : definition.isQualifiedBy(qualifier)))
          definition,
    ];
    if (requester == null) {
      return all;
    }
    final others = [
      for (final definition in all)
        if (definition.name != requester) definition,
    ];
    return single && others.isEmpty ? all : others;
  }

  /// Definitions declaring [type] (through the type index).
  List<BeanDefinition<Object>> _definitionsOf(Type type) => _byType[type] ??= [
    for (final definition in _definitions.values)
      if (definition.matchesType(type)) definition,
  ];

  void _clearByTypeCache() {
    _byType.clear();
    _resolved.clear();
  }

  /// Picks one definition: the only one, the primary one, the only
  /// non-fallback one, or the one named like the injection point.
  BeanDefinition<Object>? _select(
    Type type,
    List<BeanDefinition<Object>> candidates, {
    String? qualifier,
    String? name,
    String? requiredBy,
  }) {
    if (candidates.length <= 1) {
      return candidates.firstOrNull;
    }
    final primary = candidates.where((d) => d.primary).toList();
    if (primary.length == 1) {
      return primary.single;
    }
    if (primary.isEmpty) {
      final regular = candidates.where((d) => !d.fallback).toList();
      if (regular.length == 1) {
        return regular.single;
      }
    }
    if (name != null) {
      final byName = candidates.where((d) => d.isQualifiedBy(name)).toList();
      if (byName.length == 1) {
        return byName.single;
      }
    }
    throw NoUniqueBeanDefinitionException(
      type,
      [for (final d in primary.length > 1 ? primary : candidates) d.name],
      qualifier: qualifier,
      requiredBy: requiredBy,
    );
  }

  String? get _currentBean => _inCreation.lastOrNull;

  T? _find<T extends Object>({
    String? qualifier,
    String? name,
    required bool required,
    String? requester,
  }) {
    // Resolution order: local definitions, then resolvable dependencies
    // (the factory, the context, ...), then the parent factory.
    //
    // Once the configuration is frozen the selection is remembered; the
    // requester is part of the key because self-exclusion makes the answer
    // depend on who asks.
    final asking = requester ?? _currentBean;
    final cacheable = _frozen;
    final key = (T, qualifier, name, asking);
    final definition = cacheable && _resolved.containsKey(key)
        ? _resolved[key]
        : _select(
            T,
            _candidates(T, qualifier, requester: asking, single: true),
            qualifier: qualifier,
            name: name,
            requiredBy: asking,
          );
    if (definition != null && cacheable) {
      _resolved[key] = definition;
    }
    if (definition != null) {
      return _castTo<T>(_objectFor(definition, T), definition.name);
    }
    final resolvable = qualifier == null ? _resolvable[T] : null;
    if (resolvable != null) {
      return _castTo<T>(resolvable, T.toString());
    }
    final parent = _parent;
    if (parent != null && parent.containsBeanOfType(T, qualifier: qualifier)) {
      return parent.getBean<T>(qualifier: qualifier);
    }
    if (required) {
      throw NoSuchBeanDefinitionException(
        T,
        qualifier: qualifier,
        requiredBy: asking,
      );
    }
    return null;
  }

  /// [bean] as [T], or a [BeanNotOfRequiredTypeException] (e.g. when a
  /// post-processor replaced the bean with an unrelated wrapper).
  static T _castTo<T>(Object bean, String name) {
    if (bean case final T typed) {
      return typed;
    }
    throw BeanNotOfRequiredTypeException(name, T, bean.runtimeType);
  }

  @override
  T getBean<T extends Object>({String? qualifier}) =>
      _find<T>(qualifier: qualifier, required: true)!;

  @override
  T? findBean<T extends Object>({String? qualifier}) =>
      _find<T>(qualifier: qualifier, required: false);

  @override
  Object getBeanByName(String name) {
    final isFactoryReference = name.startsWith(BeanFactory.factoryBeanPrefix);
    final canonical = _canonical(_stripFactoryPrefix(name));
    final definition = _definitions[canonical];
    if (definition == null) {
      final parent = _parent;
      if (parent != null && parent.containsBean(name)) {
        return parent.getBeanByName(name);
      }
      throw NoSuchBeanDefinitionException.named(name, requiredBy: _currentBean);
    }
    if (isFactoryReference) {
      if (!definition.isFactoryBean) {
        throw BeanIsNotAFactoryException(canonical);
      }
      return _instanceOf(definition);
    }
    return definition.isFactoryBean
        ? _productOf(definition, _instanceOf(definition))
        : _instanceOf(definition);
  }

  @override
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier}) =>
      _BeanObjectProvider<T>(this, qualifier);

  @override
  bool containsBean(String name) {
    final canonical = _canonical(_stripFactoryPrefix(name));
    if (_definitions.containsKey(canonical)) {
      return !name.startsWith(BeanFactory.factoryBeanPrefix) ||
          _definitions[canonical]!.isFactoryBean;
    }
    return _parent?.containsBean(name) ?? false;
  }

  @override
  bool containsBeanOfType(
    Type type, {
    String? qualifier,
    bool includeAncestors = true,
  }) =>
      _candidates(type, qualifier).isNotEmpty ||
      (qualifier == null && _resolvable.containsKey(type)) ||
      (includeAncestors &&
          (_parent?.containsBeanOfType(type, qualifier: qualifier) ?? false));

  BeanDefinition<Object>? _definitionForName(String name) =>
      _definitions[_canonical(_stripFactoryPrefix(name))];

  @override
  bool isSingleton(String name) {
    final definition = _definitionForName(name);
    if (definition == null) {
      return _parentOrThrow(name).isSingleton(name);
    }
    if (definition.isFactoryBean &&
        !name.startsWith(BeanFactory.factoryBeanPrefix)) {
      // Asking about the product needs the factory instance (creates it).
      return definition.isSingleton &&
          (_instanceOf(definition) as FactoryBean<Object>).isSingleton;
    }
    return definition.isSingleton;
  }

  @override
  bool isPrototype(String name) {
    final definition = _definitionForName(name);
    if (definition == null) {
      return _parentOrThrow(name).isPrototype(name);
    }
    if (definition.isFactoryBean &&
        !name.startsWith(BeanFactory.factoryBeanPrefix)) {
      return definition.isPrototype ||
          !(_instanceOf(definition) as FactoryBean<Object>).isSingleton;
    }
    return definition.isPrototype;
  }

  BeanFactory _parentOrThrow(String name) =>
      _parent != null && _parent!.containsBean(name)
      ? _parent!
      : throw NoSuchBeanDefinitionException.named(name);

  @override
  Type? getType(String name) {
    final definition = _definitionForName(name);
    if (definition == null) {
      return _parent != null && _parent!.containsBean(name)
          ? _parent!.getType(name)
          : null;
    }
    final products = definition.factoryObjectTypes;
    if (products != null &&
        products.isNotEmpty &&
        !name.startsWith(BeanFactory.factoryBeanPrefix)) {
      return products.first;
    }
    return definition.beanType;
  }

  // ---------------------------------------------------------------------
  // Listing
  // ---------------------------------------------------------------------

  @override
  List<String> getBeanNamesForType(
    Type type, {
    bool includeNonSingletons = true,
  }) => [
    for (final definition in _definitionsOf(type))
      if (includeNonSingletons || definition.isSingleton) definition.name,
  ];

  @override
  Map<String, T> getBeansOfType<T extends Object>({
    bool includeNonSingletons = true,
  }) => {
    for (final name in getBeanNamesForType(
      T,
      includeNonSingletons: includeNonSingletons,
    ))
      name: _castTo<T>(_objectFor(_definitions[name]!, T), name),
  };

  @override
  List<T> getSortedBeans<T extends Object>({String? qualifier}) => [
    for (final (_, bean) in _sorted<T>(_candidates(T, qualifier))) bean,
  ];

  /// (name, bean) pairs for [definitions], sorted by order.
  List<(String, T)> _sorted<T extends Object>(
    List<BeanDefinition<Object>> definitions,
  ) => _sortEntries([
    for (final definition in definitions)
      (
        definition.name,
        _castTo<T>(_objectFor(definition, T), definition.name),
        definition.order,
      ),
  ]);

  /// Stable sort: `PriorityOrdered` first, then by `Ordered.order` or the
  /// definition's `@Order`, then registration order.
  static List<(String, T)> _sortEntries<T extends Object>(
    List<(String, T, int?)> entries,
  ) {
    final indexed = entries.indexed.toList()
      ..sort((a, b) {
        final (aIndex, (_, aBean, aOrder)) = a;
        final (bIndex, (_, bBean, bOrder)) = b;
        final aPriority = aBean is PriorityOrdered ? 0 : 1;
        final bPriority = bBean is PriorityOrdered ? 0 : 1;
        if (aPriority != bPriority) {
          return aPriority - bPriority;
        }
        final byOrder = OrderComparator.orderOf(
          aBean,
          aOrder,
        ).compareTo(OrderComparator.orderOf(bBean, bOrder));
        return byOrder != 0 ? byOrder : aIndex - bIndex;
      });
    return [for (final (_, (name, bean, _)) in indexed) (name, bean)];
  }

  // ---------------------------------------------------------------------
  // Dependency resolution (generated code)
  // ---------------------------------------------------------------------

  @override
  T dependency<T extends Object>({String? qualifier, String? name}) =>
      _find<T>(qualifier: qualifier, name: name, required: true)!;

  @override
  T? optionalDependency<T extends Object>({String? qualifier, String? name}) =>
      _find<T>(qualifier: qualifier, name: name, required: false);

  @override
  List<T> dependencyList<T extends Object>({String? qualifier}) =>
      optionalDependencyList<T>(qualifier: qualifier) ??
      (throw NoSuchBeanDefinitionException(
        T,
        qualifier: qualifier,
        requiredBy: _currentBean,
      ));

  @override
  List<T>? optionalDependencyList<T extends Object>({String? qualifier}) {
    final map = optionalDependencyMap<T>(qualifier: qualifier);
    return map?.values.toList();
  }

  @override
  Map<String, T> dependencyMap<T extends Object>({String? qualifier}) =>
      optionalDependencyMap<T>(qualifier: qualifier) ??
      (throw NoSuchBeanDefinitionException(
        T,
        qualifier: qualifier,
        requiredBy: _currentBean,
      ));

  @override
  Map<String, T>? optionalDependencyMap<T extends Object>({String? qualifier}) {
    final entries = <(String, T, int?)>[
      for (final definition in _candidates(
        T,
        qualifier,
        requester: _currentBean,
      ))
        (
          definition.name,
          _castTo<T>(_objectFor(definition, T), definition.name),
          definition.order,
        ),
    ];
    // Like Spring, collection injection also sees the parent's beans.
    final parent = _parent;
    if (parent is ListableBeanFactory) {
      // Local beans shadow parent beans with the same name; the qualifier
      // matches the parent bean's name, aliases or qualifiers.
      for (final name in parent.getBeanNamesForType(T)) {
        if (!entries.any((e) => e.$1 == name) &&
            (qualifier == null || _parentQualifies(parent, name, qualifier))) {
          entries.add((
            name,
            _castTo<T>(parent.getBeanByName(name), name),
            null,
          ));
        }
      }
    }
    if (entries.isEmpty) {
      return null;
    }
    return {for (final (name, bean) in _sortEntries(entries)) name: bean};
  }

  @override
  ObjectProvider<T> provider<T extends Object>({String? qualifier}) =>
      getBeanProvider<T>(qualifier: qualifier);

  @override
  T Function() lazyDependency<T extends Object>({
    String? qualifier,
    String? name,
  }) {
    // Resolved later on behalf of the bean being created now, so a lazy
    // `Greeter` in a `@Primary` Greeter decorator still gets the other one.
    final requester = _currentBean;
    return () => _find<T>(
      qualifier: qualifier,
      name: name,
      required: true,
      requester: requester,
    )!;
  }

  @override
  T value<T>(String expression) => _value<T>(expression, optional: false) as T;

  @override
  T? optionalValue<T>(String expression) =>
      _value<T>(expression, optional: true);

  /// Resolves placeholders, evaluates `#{...}` and converts to [T]. An
  /// optional value is `null` when a placeholder cannot be resolved.
  T? _value<T>(String expression, {required bool optional}) {
    final String resolved;
    try {
      resolved = resolveEmbeddedValue(expression);
    } on PlaceholderResolutionException {
      if (optional) {
        return null;
      }
      rethrow;
    }
    Object? evaluated = resolved;
    final expressionResolver = beanExpressionResolver;
    if (expressionResolver != null && resolved.contains('#{')) {
      evaluated = expressionResolver.evaluate(resolved, this);
    }
    return optional
        ? conversionService.convert<T?>(evaluated)
        : conversionService.convert<T>(evaluated);
  }

  // ---------------------------------------------------------------------
  // Creation
  // ---------------------------------------------------------------------

  /// The object for [definition] when requested as [type]: the product of
  /// a factory bean when [type] is a product type.
  Object _objectFor(BeanDefinition<Object> definition, Type type) {
    final instance = _instanceOf(definition);
    return definition.isProductType(type)
        ? _productOf(definition, instance)
        : instance;
  }

  /// The (exposed) bean instance of [definition], created according to its
  /// scope. For a factory bean this is the factory itself.
  Object _instanceOf(BeanDefinition<Object> definition) {
    final name = definition.name;
    final current = _currentBean;
    // A lookup while another bean is being created is a dependency of that
    // bean: record it so destruction runs dependents first.
    if (current != null) {
      registerDependentBean(name, current);
    }
    switch (definition.scope) {
      case ScopeType.singleton:
        final existing = _singletons[name];
        if (existing != null) {
          return existing;
        }
        final (raw, exposed) = _createBean(definition);
        _singletons[name] = exposed;
        _rawSingletons[name] = raw;
        _creationOrder.add(name);
        if (_requiresDestruction(definition, raw, exposed)) {
          _disposables.add(name);
        }
        return exposed;
      case ScopeType.prototype:
        // Prototypes are not tracked: no destroy callbacks.
        return _createBean(definition).$2;
      case final scopeName:
        final scope =
            _scopes[scopeName] ??
            (throw ScopeNotRegisteredException(scopeName, name));
        return scope.get(name, () {
          final (raw, exposed) = _createBean(definition);
          if (_canExpando(exposed)) {
            _scopedRaw[exposed] = raw;
          }
          if (_requiresDestruction(definition, raw, exposed)) {
            scope.registerDestructionCallback(
              name,
              () => _destroyBean(definition, raw, exposed),
            );
          }
          return exposed;
        });
    }
  }

  /// The product of [factory]; cached only when both the definition and
  /// the factory are singletons.
  Object _productOf(BeanDefinition<Object> definition, Object factory) {
    if (factory is! FactoryBean<Object>) {
      throw BeanIsNotAFactoryException(definition.name);
    }
    final name = definition.name;
    if (definition.isSingleton && factory.isSingleton) {
      final cached = _factoryProducts[name];
      if (cached != null) {
        return cached;
      }
      return _factoryProducts[name] = _createProduct(name, factory);
    }
    return _createProduct(name, factory);
  }

  /// Calls `getObject` and applies only `postProcessAfterInitialization`
  /// (like Spring's `postProcessObjectFromFactoryBean`).
  Object _createProduct(String name, FactoryBean<Object> factory) {
    try {
      var product = factory.getObject();
      for (final processor in _postProcessors) {
        product = processor.postProcessAfterInitialization(product, name);
      }
      return product;
    } on BeansException {
      rethrow;
    } catch (error, stackTrace) {
      throw BeanCreationException(name, error, stackTrace);
    }
  }

  /// Creates, injects and initializes a bean; returns the raw instance and
  /// the exposed (post-processed) one.
  (Object, Object) _createBean(BeanDefinition<Object> definition) {
    final name = definition.name;
    // Already on the creation stack: report the cycle from there.
    final index = _inCreation.indexOf(name);
    if (index >= 0) {
      throw BeanCurrentlyInCreationException([
        ..._inCreation.sublist(index),
        name,
      ]);
    }
    _inCreation.add(name);
    try {
      for (final dependsOn in definition.dependsOn) {
        registerDependentBean(dependsOn, name);
        getBeanByName(dependsOn);
      }
      final raw = definition.instantiate(this);
      definition.populate(raw, this);
      final exposed = _initialize(raw, name, definition);
      return (raw, exposed);
    } on BeanCreationException catch (error, stackTrace) {
      // Wrap a nested bean's failure once per level so the message shows
      // the chain of beans being created.
      if (error.beanName == name) {
        rethrow;
      }
      throw BeanCreationException(name, error, stackTrace);
    } on BeansException {
      rethrow;
    } catch (error, stackTrace) {
      throw BeanCreationException(name, error, stackTrace);
    } finally {
      _inCreation.removeLast();
    }
  }

  /// Aware callbacks, post-processors and init callbacks; [definition] is
  /// `null` for `initializeBean` on an external object.
  Object _initialize(
    Object raw,
    String name,
    BeanDefinition<Object>? definition,
  ) {
    if (raw is BeanNameAware) {
      raw.setBeanName(name);
    }
    if (raw is BeanFactoryAware) {
      raw.setBeanFactory(this);
    }
    var exposed = raw;
    for (final processor in _postProcessors) {
      exposed = processor.postProcessBeforeInitialization(exposed, name);
    }
    // Init callbacks run on the raw instance; a processor may already have
    // wrapped it.
    definition?.invokePostConstruct(raw);
    if (raw is InitializingBean) {
      raw.afterPropertiesSet();
    }
    definition?.invokeInitMethod(raw);
    for (final processor in _postProcessors) {
      exposed = processor.postProcessAfterInitialization(exposed, name);
    }
    return exposed;
  }

  /// Whether a bean must be remembered for destruction at all.
  bool _requiresDestruction(
    BeanDefinition<Object> definition,
    Object raw,
    Object exposed,
  ) =>
      definition.hasDestroyCallbacks ||
      raw is DisposableBean ||
      _postProcessors.any(
        (p) =>
            p is DestructionAwareBeanPostProcessor &&
            p.requiresDestruction(exposed),
      );

  @override
  void autowireBean(Object existingBean) {
    final configurer = _configurers[existingBean.runtimeType];
    if (configurer == null) {
      throw ArgumentError.value(
        existingBean,
        'existingBean',
        '${existingBean.runtimeType} is not @Configurable or its module is '
            'not registered',
      );
    }
    configurer(existingBean, this);
  }

  @override
  Object initializeBean(Object existingBean, String beanName) =>
      _initialize(existingBean, beanName, null);

  @override
  void preInstantiateSingletons() {
    // Copy: creating beans may register further definitions.
    for (final definition in _definitions.values.toList()) {
      if (definition.isSingleton && !definition.lazy) {
        _instanceOf(definition);
      }
    }
    for (final name in _creationOrder.toList()) {
      final bean = _singletons[name];
      if (bean is SmartInitializingSingleton) {
        bean.afterSingletonsInstantiated();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  @override
  void validateBeanGraph() {
    // Build bean -> bean edges from `dependsOn` and declared dependencies
    // (checking each for missing or ambiguous targets), then find cycles
    // with a depth-first search. Parent beans are leaves: they cannot
    // point back into this factory.
    final edges = <String, List<String>>{};
    for (final definition in _definitions.values) {
      final targets = edges[definition.name] = [];
      for (final name in definition.dependsOn) {
        final target = _canonical(name);
        if (_definitions.containsKey(target)) {
          targets.add(target);
        } else if (!(_parent?.containsBean(name) ?? false)) {
          throw NoSuchBeanDefinitionException.named(
            name,
            requiredBy: definition.name,
          );
        }
      }
      for (final dependency in definition.dependencies) {
        targets.addAll(_validateDependency(definition, dependency));
      }
    }

    // `done`: fully explored nodes; `path`: the current DFS stack.
    final done = <String>{};
    final path = <String>[];
    void visit(String name) {
      if (done.contains(name)) {
        return;
      }
      final index = path.indexOf(name);
      if (index >= 0) {
        throw BeanCurrentlyInCreationException([...path.sublist(index), name]);
      }
      path.add(name);
      edges[name]!.forEach(visit);
      path.removeLast();
      done.add(name);
    }

    _definitions.keys.forEach(visit);
  }

  /// Checks [dependency] and returns the names it points to.
  List<String> _validateDependency(
    BeanDefinition<Object> definition,
    Dependency dependency,
  ) {
    switch (dependency.kind) {
      case DependencyKind.provider:
        // Providers resolve lazily, so they are neither required nor
        // edges of the graph (this is how cycles are broken).
        return const [];
      case DependencyKind.value:
        if (!dependency.optional) {
          try {
            resolveEmbeddedValue(dependency.expression!);
          } on PlaceholderResolutionException catch (error) {
            throw UnsatisfiedDependencyException(
              definition.name,
              dependency.toString(),
              error.message,
              cause: error,
            );
          }
        }
        return const [];
      case DependencyKind.collection || DependencyKind.map:
        final candidates = _candidates(
          dependency.type,
          dependency.qualifier,
          requester: definition.name,
        );
        if (candidates.isEmpty &&
            !dependency.optional &&
            !(_parent?.containsBeanOfType(
                  dependency.type,
                  qualifier: dependency.qualifier,
                ) ??
                false)) {
          throw NoSuchBeanDefinitionException(
            dependency.type,
            qualifier: dependency.qualifier,
            requiredBy: definition.name,
          );
        }
        return [for (final candidate in candidates) candidate.name];
      case DependencyKind.lazy:
        // Checked like a single dependency, but resolved on first use: no
        // edge, so `@Lazy` breaks cycles (including self-injection).
        _validateDependency(
          definition,
          Dependency(
            dependency.type,
            qualifier: dependency.qualifier,
            name: dependency.name,
          ),
        );
        return const [];
      case DependencyKind.single:
        final target = _select(
          dependency.type,
          _candidates(
            dependency.type,
            dependency.qualifier,
            requester: definition.name,
            single: true,
          ),
          qualifier: dependency.qualifier,
          name: dependency.name,
          requiredBy: definition.name,
        );
        if (target != null) {
          return [target.name];
        }
        if (dependency.qualifier == null &&
            _resolvable.containsKey(dependency.type)) {
          return const [];
        }
        if (!dependency.optional &&
            !(_parent?.containsBeanOfType(
                  dependency.type,
                  qualifier: dependency.qualifier,
                ) ??
                false)) {
          throw NoSuchBeanDefinitionException(
            dependency.type,
            qualifier: dependency.qualifier,
            requiredBy: definition.name,
          );
        }
        return const [];
    }
  }

  // ---------------------------------------------------------------------
  // Destruction
  // ---------------------------------------------------------------------

  @override
  void destroySingletons() {
    // Reverse creation order; _destroySingleton also destroys dependents
    // first. Singletons registered with registerSingleton are kept (they
    // are owned by the caller and were never initialized here).
    _destructionErrors.clear();
    for (final name in _creationOrder.reversed.toList()) {
      _destroySingleton(name);
    }
    _singletons.removeWhere((name, _) => !_manualSingletons.contains(name));
    _rawSingletons.removeWhere((name, _) => !_manualSingletons.contains(name));
    _factoryProducts.clear();
    _creationOrder.clear();
    _disposables.clear();
    _dependents.clear();
    _dependencies.clear();
  }

  /// Destroys [name] after every bean that depends on it.
  void _destroySingleton(String name) {
    // Removing from _creationOrder first also stops recursion on cycles of
    // dependent registrations.
    if (!_creationOrder.contains(name)) {
      return;
    }
    _creationOrder.remove(name);
    for (final dependent in (_dependents[name] ?? const <String>{}).toList()) {
      _destroySingleton(dependent);
    }
    final exposed = _singletons.remove(name);
    final raw = _rawSingletons.remove(name);
    _factoryProducts.remove(name);
    final definition = _definitions[name];
    if (_disposables.remove(name) &&
        raw != null &&
        exposed != null &&
        definition != null) {
      _destroyBean(definition, raw, exposed);
    }
  }

  /// Runs destruction post-processors (on the exposed bean), then
  /// `@PreDestroy`, `DisposableBean.destroy` and the destroy method (on the
  /// raw bean). Errors are collected in [destructionErrors].
  void _destroyBean(
    BeanDefinition<Object> definition,
    Object raw,
    Object exposed,
  ) {
    void guard(void Function() callback) {
      try {
        callback();
      } catch (error) {
        _destructionErrors.add(error);
      }
    }

    for (final processor in _postProcessors) {
      if (processor is DestructionAwareBeanPostProcessor &&
          processor.requiresDestruction(exposed)) {
        guard(
          () =>
              processor.postProcessBeforeDestruction(exposed, definition.name),
        );
      }
    }
    guard(() => definition.invokePreDestroy(raw));
    if (raw is DisposableBean) {
      guard(raw.destroy);
    }
    guard(() => definition.invokeDestroyMethod(raw));
  }

  // Expando keys cannot be numbers, strings, booleans or records.
  static bool _canExpando(Object value) =>
      value is! num && value is! String && value is! bool && value is! Record;

  static bool _parentQualifies(
    ListableBeanFactory parent,
    String name,
    String qualifier,
  ) {
    if (parent is ConfigurableListableBeanFactory) {
      return parent.getBeanDefinition(name).isQualifiedBy(qualifier);
    }
    return name == qualifier || parent.getAliases(name).contains(qualifier);
  }

  @override
  void destroyScopedBean(String name) {
    final definition = getBeanDefinition(name);
    final scope = _scopes[definition.scope];
    if (scope == null) {
      throw ArgumentError.value(name, 'name', 'Bean is not in a custom scope');
    }
    // The scope stores the exposed bean; destroy callbacks run on the raw
    // instance remembered at creation.
    final bean = scope.remove(definition.name);
    if (bean != null) {
      final raw = _canExpando(bean) ? _scopedRaw[bean] : null;
      _destroyBean(definition, raw ?? bean, bean);
    }
  }
}

/// [ObjectProvider] backed by a [DefaultListableBeanFactory].
final class _BeanObjectProvider<T extends Object> extends Iterable<T>
    implements ObjectProvider<T> {
  _BeanObjectProvider(this._factory, this._qualifier);

  final DefaultListableBeanFactory _factory;
  final String? _qualifier;

  @override
  T getObject() => _factory.getBean<T>(qualifier: _qualifier);

  @override
  T? getIfAvailable([T Function()? defaultSupplier]) =>
      _factory.findBean<T>(qualifier: _qualifier) ?? defaultSupplier?.call();

  @override
  T? getIfUnique([T Function()? defaultSupplier]) {
    // Ambiguity is treated like absence.
    try {
      return getIfAvailable(defaultSupplier);
    } on NoUniqueBeanDefinitionException {
      return defaultSupplier?.call();
    }
  }

  @override
  void ifAvailable(void Function(T bean) consumer) {
    final bean = getIfAvailable();
    if (bean != null) {
      consumer(bean);
    }
  }

  @override
  void ifUnique(void Function(T bean) consumer) {
    final bean = getIfUnique();
    if (bean != null) {
      consumer(bean);
    }
  }

  @override
  List<T> orderedList() =>
      _factory.optionalDependencyList<T>(qualifier: _qualifier) ?? const [];

  @override
  Iterator<T> get iterator =>
      (_factory.optionalDependencyMap<T>(qualifier: _qualifier)?.values ??
              const [])
          .iterator;
}
