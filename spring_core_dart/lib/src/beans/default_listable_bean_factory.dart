import 'dart:async';

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
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/order.dart';

Type _typeOf<T>() => T;

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

  /// Whether a definition may replace another with the same name (and an
  /// alias may be re-pointed). Off by default (Spring Boot's default too);
  /// the replaced singleton is destroyed.
  bool allowBeanDefinitionOverriding = false;

  @override
  ConversionService conversionService = DefaultConversionService.sharedInstance;

  /// Turns `@Value` strings into [Resource]s (like Spring's
  /// `ResourceEditor`, registered by the context), so protocol resolvers
  /// and asset loaders of the context apply; `null` falls back to the
  /// [conversionService].
  ResourceLoader? resourceLoader;

  @override
  BeanExpressionResolver? beanExpressionResolver;

  BeanFactory? _parent;
  final _definitions = <String, BeanDefinition<Object>>{};
  // Synthetic definitions of the objects of registerSingleton: they make
  // the objects visible to lookups by type, but are not bean definitions
  // (like Spring's manual singletons).
  final _manualDefinitions = <String, BeanDefinition<Object>>{};
  // Type -> definitions declaring it, like Spring's `allBeanNamesByType`;
  // filled on demand and cleared whenever definitions change.
  final _byType = <Type, List<BeanDefinition<Object>>>{};
  final _candidatesByType = <Type, List<_Candidate>>{};
  // (type, qualifier, injection point name, requester, injection?) ->
  // selected bean, for lookups after the configuration is frozen.
  final _resolved = <(Type, String?, String?, String?, bool), _Candidate>{};
  // alias -> name (which may itself be an alias).
  final _aliases = <String, String>{};
  // Exposed singletons (possibly wrapped by post-processors).
  final _singletons = <String, Object>{};
  // The same singletons before post-processing; callbacks run on these.
  final _rawSingletons = <String, Object>{};
  // Cached products of singleton FactoryBeans, by factory bean name.
  final _factoryProducts = <String, Object>{};
  // Factory beans whose getObject() is running -> creation stack depth at
  // that moment (to report re-entrant product requests as cycles).
  final _productsInCreation = <String, int>{};
  // Singletons in creation order (insertion-ordered set: O(1) removal);
  // destroyed in reverse.
  final _creationOrder = <String>{};
  // Singletons that have destroy callbacks to run.
  final _disposables = <String>{};
  // Init callbacks that returned a Future, collected until the singletons
  // are pre-instantiated; `null` afterwards (then such a callback fails
  // the bean's creation).
  List<(String, Future<void>)>? _pendingInits = [];
  // Whether destroy callbacks returning a Future are awaited
  // (destroySingletonsAsync) or logged (the synchronous paths).
  bool _asyncDestroy = false;
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
  final _configurablePostConstruct = <Type, void Function(Object bean)>{};
  final _configurablePreDestroy = <Type, void Function(Object bean)>{};
  final _resolvable = <Type, Object>{};
  // (singleton, scoped bean) pairs already warned about.
  final _scopedInjectionWarnings = <(String, String)>{};

  // Raw instances of custom-scoped beans, keyed by the exposed object.
  final _scopedRaw = Expando<Object>('scopedRaw');
  final _destructionErrors = <Object>[];
  bool _frozen = false;
  bool _destroyingSingletons = false;

  @override
  List<Object> get destructionErrors => List.unmodifiable(_destructionErrors);

  // ---------------------------------------------------------------------
  // Hierarchy
  // ---------------------------------------------------------------------

  @override
  BeanFactory? get parentBeanFactory => _parent;

  @override
  set parentBeanFactory(BeanFactory? parent) {
    _parent = parent;
    _resolved.clear();
  }

  @override
  bool containsLocalBean(String name) {
    final definition = _definitionForName(name);
    return definition != null &&
        (!name.startsWith(BeanFactory.factoryBeanPrefix) ||
            definition.isFactoryBean);
  }

  // ---------------------------------------------------------------------
  // Registry
  // ---------------------------------------------------------------------

  @override
  void registerBeanDefinition(BeanDefinition<Object> definition) {
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
    } else if (_aliases.containsKey(name)) {
      // Like Spring: with overriding allowed the definition takes the name
      // over from the alias.
      if (!allowBeanDefinitionOverriding) {
        throw BeanDefinitionOverrideException(name, definition.source);
      }
      _aliases.remove(name);
    }
    // Replacing a definition or a registered singleton destroys the old
    // singleton (and its dependents), like Spring's resetBeanDefinition.
    if (existing != null || _manualDefinitions.containsKey(name)) {
      destroySingleton(name);
    }
    _definitions[name] = definition;
    _clearByTypeCache();
    for (final alias in definition.aliases) {
      registerAlias(name, alias);
    }
  }

  @override
  void removeBeanDefinition(String name) {
    final canonical = _canonical(name);
    if (!_definitions.containsKey(canonical)) {
      throw NoSuchBeanDefinitionException.named(name);
    }
    destroySingleton(canonical);
    _definitions.remove(canonical);
    // Every alias leading to the bean, also through other aliases.
    final aliases = [
      for (final alias in _aliases.keys)
        if (_canonical(alias) == canonical) alias,
    ];
    aliases.forEach(_aliases.remove);
    _clearByTypeCache();
  }

  /// Destroys the singleton named [name] (or alias) after the beans that
  /// depend on it, and forgets an object added with [registerSingleton].
  /// The next lookup creates the bean again. Spring:
  /// `destroySingleton(String)`.
  ///
  /// ```dart
  /// factory.destroySingleton('cache'); // recreated on next use
  /// ```
  void destroySingleton(String name) {
    final canonical = _canonical(name);
    if (_manualDefinitions.remove(canonical) != null) {
      _singletons.remove(canonical);
      _rawSingletons.remove(canonical);
      _clearByTypeCache();
    }
    _destroySingleton(canonical);
  }

  @override
  BeanDefinition<Object> getBeanDefinition(String name) =>
      _definitions[_canonical(_stripFactoryPrefix(name))] ??
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
      _resolved.clear();
      return;
    }
    if (_definitions.containsKey(alias) ||
        _manualDefinitions.containsKey(alias)) {
      throw BeanDefinitionOverrideException(alias, 'alias for $name');
    }
    final existing = _aliases[alias];
    if (existing == name) {
      return;
    }
    // Re-pointing an alias needs overriding (Spring's allowAliasOverriding);
    // an alias may never lead back to itself.
    if ((existing != null && !allowBeanDefinitionOverriding) ||
        _canonical(name) == alias) {
      throw BeanDefinitionOverrideException(alias, 'alias for $name');
    }
    _aliases[alias] = name;
    _resolved.clear();
  }

  @override
  void removeAlias(String alias) {
    if (_aliases.remove(alias) == null) {
      throw ArgumentError.value(alias, 'alias', 'Alias is not registered');
    }
    _resolved.clear();
  }

  @override
  bool isAlias(String name) => _aliases.containsKey(name);

  @override
  bool isBeanNameInUse(String name) =>
      _aliases.containsKey(name) ||
      containsLocalBean(name) ||
      _dependents.containsKey(name);

  @override
  List<String> getAliases(String name) {
    final stripped = _stripFactoryPrefix(name);
    final canonical = _canonical(stripped);
    if (_localDefinition(canonical) == null) {
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

  /// The definition, or registered singleton, named exactly [canonical].
  BeanDefinition<Object>? _localDefinition(String canonical) =>
      _definitions[canonical] ?? _manualDefinitions[canonical];

  /// The local definition (or registered singleton) for [name], which may
  /// be an alias or start with `&`.
  BeanDefinition<Object>? _definitionForName(String name) =>
      _localDefinition(_canonical(_stripFactoryPrefix(name)));

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
        _manualDefinitions.containsKey(name) ||
        _aliases.containsKey(name)) {
      throw BeanDefinitionOverrideException(name, 'registerSingleton');
    }
    // A synthetic definition makes the object visible to lookups by type;
    // the instance is stored directly, so `create` is never called. A
    // FactoryBean is dereferenced by name (its product types are unknown).
    _manualDefinitions[name] = BeanDefinition<Object>(
      name: name,
      types: types ?? [singleton.runtimeType],
      create: (_) => singleton,
      source: 'registerSingleton',
      factoryObjectTypes: singleton is FactoryBean<Object> ? const [] : null,
    );
    _clearByTypeCache();
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
  void registerResolvableDependency(Type type, Object value) {
    _resolvable[type] = value;
    _resolved.clear();
  }

  /// Registers how `autowireBean` injects objects of [type] (the exact
  /// runtime type), and the `@PostConstruct` / `@PreDestroy` methods that
  /// `initializeBean` / `destroyBean` run for them. Generated modules do
  /// this for `@Configurable` classes.
  ///
  /// ```dart
  /// factory.registerConfigurer(
  ///   Holder,
  ///   (bean, r) => (bean as Holder).greeter = r.dependency<Greeter>(),
  ///   postConstruct: (bean) => (bean as Holder).init(),
  /// );
  /// factory.autowireBean(Holder());
  /// ```
  void registerConfigurer(
    Type type,
    BeanConfigurer configurer, {
    void Function(Object bean)? postConstruct,
    void Function(Object bean)? preDestroy,
  }) {
    _configurers[type] = configurer;
    if (postConstruct != null) {
      _configurablePostConstruct[type] = postConstruct;
    }
    if (preDestroy != null) {
      _configurablePreDestroy[type] = preDestroy;
    }
  }

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
  // Candidates
  // ---------------------------------------------------------------------

  /// Definitions declaring [type] (through the type index): definitions
  /// first, then registered singletons, like Spring.
  List<BeanDefinition<Object>> _definitionsOf(Type type) => _byType[type] ??= [
    for (final definition in _definitions.values)
      if (definition.matchesType(type)) definition,
    for (final definition in _manualDefinitions.values)
      if (definition.matchesType(type)) definition,
  ];

  /// The local beans of [type] as candidates.
  List<_Candidate> _localCandidates(Type type) => _candidatesByType[type] ??= [
    for (final definition in _definitionsOf(type))
      _Candidate(
        this,
        definition.isFactoryBean && !definition.isProductType(type)
            ? '${BeanFactory.factoryBeanPrefix}${definition.name}'
            : definition.name,
        definition,
      ),
  ];

  void _clearByTypeCache() {
    _byType.clear();
    _candidatesByType.clear();
    _resolved.clear();
  }

  /// Beans of [type] here and in the ancestors, like Spring's
  /// `beanNamesForTypeIncludingAncestors`: local beans first; a bean of an
  /// ancestor is hidden by a bean (of any type) with the same name in a
  /// factory below it.
  List<_Candidate> _candidatesIncludingAncestors(Type type) {
    final local = _localCandidates(type);
    var current = _parent;
    if (current == null) {
      return local;
    }
    final result = [...local];
    final below = <HierarchicalBeanFactory>[this];
    while (current != null) {
      for (final candidate in _listLocal(current, type)) {
        if (!below.any((f) => f.containsLocalBean(candidate.beanName))) {
          result.add(candidate);
        }
      }
      if (current is! HierarchicalBeanFactory) {
        break;
      }
      below.add(current);
      current = current.parentBeanFactory;
    }
    return result;
  }

  /// The local beans of [type] of any factory.
  static List<_Candidate> _listLocal(BeanFactory factory, Type type) =>
      switch (factory) {
        final DefaultListableBeanFactory listable => listable._localCandidates(
          type,
        ),
        final ListableBeanFactory listable => [
          for (final name in listable.getBeanNamesForType(type))
            _Candidate(listable, name, switch (listable) {
              final ConfigurableListableBeanFactory configurable
                  when configurable.containsBeanDefinition(
                    _stripFactoryPrefix(name),
                  ) =>
                configurable.getBeanDefinition(_stripFactoryPrefix(name)),
              _ => null,
            }),
        ],
        _ => const [],
      };

  /// Beans of [type] here and in the ancestors selected by [qualifier]
  /// (all with `null`), whether autowire candidates or not: what lookups
  /// such as `getBeanProvider(...).orderedList()` list.
  List<_Candidate> _lookupCandidates(Type type, String? qualifier) => [
    for (final candidate in _candidatesIncludingAncestors(type))
      if (qualifier == null || candidate.qualifies(qualifier)) candidate,
  ];

  /// Candidates for an injection point of [type] in the bean [requester],
  /// like Spring's `findAutowireCandidates`.
  ///
  /// Only autowire candidates take part; without a [qualifier] only
  /// default candidates. Spring's `isSelfReference`: the requester itself
  /// and the beans of its own `@Bean` methods are never candidates for its
  /// collections ([multiple]), and for a single dependency only when
  /// nothing else matches — so composites and decorators
  /// (`Composite(List<Greeter>)`, `Caching(Greeter delegate)`) get the
  /// other beans of their own type.
  List<_Candidate> _autowireCandidates(
    Type type,
    String? qualifier, {
    String? requester,
    required bool multiple,
  }) {
    final all = [
      for (final candidate in _candidatesIncludingAncestors(type))
        if (candidate.isAutowireCandidate &&
            (qualifier == null
                ? candidate.isDefaultCandidate
                : candidate.qualifies(qualifier)))
          candidate,
    ];
    if (requester == null) {
      return all;
    }
    final others = [
      for (final candidate in all)
        if (!_isSelfReference(requester, candidate)) candidate,
    ];
    return !multiple && others.isEmpty ? all : others;
  }

  bool _isSelfReference(String requester, _Candidate candidate) {
    if (!identical(candidate.owner, this)) {
      return false;
    }
    final factoryBeanName = candidate.definition?.factoryBeanName;
    return candidate.beanName == requester ||
        (factoryBeanName != null && _canonical(factoryBeanName) == requester);
  }

  /// Whether [definition] is selected by [qualifier]: its name, an alias
  /// (also from [registerAlias]) or a qualifier value.
  bool _qualifies(BeanDefinition<Object> definition, String qualifier) =>
      definition.isQualifiedBy(qualifier) ||
      _canonical(qualifier) == definition.name;

  /// Whether [name] is the name or an alias of [definition] (Spring's
  /// `matchesBeanName`; qualifier values do not count).
  bool _matchesBeanName(BeanDefinition<Object> definition, String name) =>
      definition.name == name ||
      definition.aliases.contains(name) ||
      _canonical(name) == definition.name;

  /// Spring's `determineAutowireCandidate`: the only candidate, the
  /// primary one (a local primary beats an ancestor's; two at the same
  /// level are ambiguous), the only non-fallback one, the one named like
  /// the injection point ([name]), the one named like the [qualifier], the
  /// only default candidate.
  _Candidate? _determineAutowireCandidate(
    Type type,
    List<_Candidate> candidates, {
    String? qualifier,
    String? name,
    String? requiredBy,
  }) {
    if (candidates.length <= 1) {
      return candidates.firstOrNull;
    }
    final primary = _primaryCandidate(
      type,
      candidates,
      qualifier: qualifier,
      requiredBy: requiredBy,
    );
    if (primary != null) {
      return primary;
    }
    if (name != null) {
      for (final candidate in candidates) {
        if (candidate.matchesName(name)) {
          return candidate;
        }
      }
    }
    if (qualifier != null) {
      for (final candidate in candidates) {
        if (candidate.matchesName(qualifier)) {
          return candidate;
        }
      }
    }
    final selected = _uniqueDefaultCandidate(candidates);
    if (selected != null) {
      return selected;
    }
    throw NoUniqueBeanDefinitionException(
      type,
      [for (final candidate in candidates) candidate.name],
      qualifier: qualifier,
      requiredBy: requiredBy,
    );
  }

  /// Spring's `determinePrimaryCandidate`: the single primary candidate,
  /// else the only non-fallback one.
  _Candidate? _primaryCandidate(
    Type type,
    List<_Candidate> candidates, {
    String? qualifier,
    String? requiredBy,
  }) {
    _Candidate? primary;
    for (final candidate in candidates) {
      if (!candidate.primary) {
        continue;
      }
      if (primary == null) {
        primary = candidate;
        continue;
      }
      final candidateLocal = identical(candidate.owner, this);
      if (candidateLocal == identical(primary.owner, this)) {
        throw NoUniqueBeanDefinitionException(
          type,
          [
            for (final candidate in candidates)
              if (candidate.primary) candidate.name,
          ],
          qualifier: qualifier,
          requiredBy: requiredBy,
        );
      }
      if (candidateLocal) {
        primary = candidate;
      }
    }
    if (primary != null) {
      return primary;
    }
    final regular = [
      for (final candidate in candidates)
        if (!candidate.fallback) candidate,
    ];
    return regular.length == 1 ? regular.single : null;
  }

  static _Candidate? _uniqueDefaultCandidate(List<_Candidate> candidates) {
    final defaults = [
      for (final candidate in candidates)
        if (candidate.isDefaultCandidate) candidate,
    ];
    return defaults.length == 1 ? defaults.single : null;
  }

  // Whether selections may be cached: the definitions here and in the
  // parent factories no longer change.
  bool get _cacheable {
    if (!_frozen) {
      return false;
    }
    final parent = _parent;
    return parent == null ||
        (parent is DefaultListableBeanFactory && parent._cacheable);
  }

  String? get _currentBean => _inCreation.lastOrNull;

  // ---------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------

  /// Spring's `resolveNamedBean`: the local bean of [type] (selected by
  /// [qualifier]). With several matches the autowire candidates are
  /// preferred, then the primary, non-fallback, qualifier-named or only
  /// default candidate.
  _Candidate? _resolveNamedBean(Type type, String? qualifier) {
    final key = (type, qualifier, null, null, false);
    final cacheable = _frozen;
    if (cacheable) {
      final cached = _resolved[key];
      if (cached != null) {
        return cached;
      }
    }
    var candidates = [
      for (final candidate in _localCandidates(type))
        if (qualifier == null || candidate.qualifies(qualifier)) candidate,
    ];
    if (candidates.length > 1 && qualifier == null) {
      final autowire = [
        for (final candidate in candidates)
          if (candidate.isAutowireCandidate) candidate,
      ];
      if (autowire.isNotEmpty) {
        candidates = autowire;
      }
    }
    if (candidates.length > 1) {
      final requiredBy = _currentBean;
      final selected =
          _primaryCandidate(
            type,
            candidates,
            qualifier: qualifier,
            requiredBy: requiredBy,
          ) ??
          (qualifier == null
              ? null
              : candidates
                    .where((c) => c.matchesName(qualifier))
                    .firstOrNull) ??
          _uniqueDefaultCandidate(candidates);
      if (selected == null) {
        throw NoUniqueBeanDefinitionException(
          type,
          [for (final candidate in candidates) candidate.name],
          qualifier: qualifier,
          requiredBy: requiredBy,
        );
      }
      candidates = [selected];
    }
    final candidate = candidates.firstOrNull;
    if (candidate != null && cacheable) {
      _resolved[key] = candidate;
    }
    return candidate;
  }

  /// `getBean` / `findBean`: local beans, then resolvable dependencies,
  /// then the parent.
  T? _getBean<T extends Object>(String? qualifier, {required bool required}) {
    final candidate = _resolveNamedBean(T, qualifier);
    if (candidate != null) {
      return candidate.resolve<T>();
    }
    final resolvable = qualifier == null ? _resolvable[T] : null;
    if (resolvable != null) {
      return _castTo<T>(resolvable, T.toString());
    }
    final found = _parent?.findBean<T>(qualifier: qualifier);
    if (found != null) {
      return found;
    }
    if (required) {
      throw NoSuchBeanDefinitionException(
        T,
        qualifier: qualifier,
        requiredBy: _currentBean,
      );
    }
    return null;
  }

  /// Resolves a single injection point of [T] in the bean [requester]
  /// (Spring's `doResolveDependency`); resolvable dependencies come after
  /// the beans. [direct] marks a point injected while the requester is
  /// created (not through a provider or lazy proxy).
  T? _resolveDependency<T extends Object>({
    String? qualifier,
    String? name,
    String? requester,
    required bool required,
    bool direct = false,
  }) {
    final key = (T, qualifier, name, requester, true);
    final cacheable = _cacheable;
    var candidate = cacheable ? _resolved[key] : null;
    if (candidate == null) {
      candidate = _determineAutowireCandidate(
        T,
        _autowireCandidates(
          T,
          qualifier,
          requester: requester,
          multiple: false,
        ),
        qualifier: qualifier,
        name: name,
        requiredBy: requester,
      );
      if (candidate != null && cacheable) {
        _resolved[key] = candidate;
      }
    }
    if (candidate != null) {
      if (requester != null) {
        _registerDependency(candidate, requester, direct: direct);
      }
      return candidate.resolve<T>();
    }
    final resolvable = qualifier == null ? _resolvable[T] : null;
    if (resolvable != null) {
      return _castTo<T>(resolvable, T.toString());
    }
    if (required) {
      throw NoSuchBeanDefinitionException(
        T,
        qualifier: qualifier,
        requiredBy: requester,
      );
    }
    return null;
  }

  /// Beans for a collection injection point of [T] in [requester], in
  /// registration order (local beans first, then the ancestors').
  List<(_Candidate, T)> _resolveMultiple<T extends Object>(
    String? qualifier,
    String? requester,
  ) => [
    for (final candidate in _autowireCandidates(
      T,
      qualifier,
      requester: requester,
      multiple: true,
    ))
      (_registeredFor(candidate, requester), candidate.resolve<T>()),
  ];

  _Candidate _registeredFor(_Candidate candidate, String? requester) {
    if (requester != null) {
      _registerDependency(candidate, requester, direct: true);
    }
    return candidate;
  }

  /// Records that [requester] depends on [candidate] (so it is destroyed
  /// first) and warns once when a custom-scoped bean is injected directly
  /// into a singleton.
  void _registerDependency(
    _Candidate candidate,
    String requester, {
    required bool direct,
  }) {
    if (!identical(candidate.owner, this)) {
      return;
    }
    registerDependentBean(candidate.beanName, requester);
    final target = candidate.definition;
    final requesting = _definitions[requester];
    if (direct &&
        target != null &&
        requesting != null &&
        requesting.isSingleton &&
        !target.isSingleton &&
        !target.isPrototype &&
        _scopedInjectionWarnings.add((requester, candidate.beanName))) {
      _log.warning(
        "Bean '${candidate.beanName}' of scope '${target.scope}' is injected "
        "directly into the singleton '$requester', which keeps the first "
        'instance. Inject an ObjectProvider<${target.beanType}> or mark the '
        'injection point @Lazy() to get the current instance on every use.',
      );
    }
  }

  /// Runs [resolve] for an injection point ([point]) of the bean being
  /// created; a failure becomes an [UnsatisfiedDependencyException] naming
  /// the bean and the point, like Spring.
  R _injecting<R>(Dependency point, R Function() resolve) {
    final current = _currentBean;
    if (current == null) {
      return resolve();
    }
    try {
      return resolve();
    } on BeansException catch (error, stackTrace) {
      if (error is UnsatisfiedDependencyException &&
          error.beanName == current) {
        rethrow;
      }
      throw UnsatisfiedDependencyException(
        current,
        point.toString(),
        error.message,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
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
      _getBean<T>(qualifier, required: true)!;

  @override
  T? findBean<T extends Object>({String? qualifier}) =>
      _getBean<T>(qualifier, required: false);

  @override
  Object getBeanByName(String name) {
    final isFactoryReference = name.startsWith(BeanFactory.factoryBeanPrefix);
    final canonical = _canonical(_stripFactoryPrefix(name));
    final definition = _localDefinition(canonical);
    if (definition == null) {
      final parent = _parent;
      if (parent != null && parent.containsBean(name)) {
        return parent.getBeanByName(name);
      }
      throw NoSuchBeanDefinitionException.named(name, requiredBy: _currentBean);
    }
    if (isFactoryReference) {
      if (!definition.isFactoryBean) {
        throw BeanIsNotAFactoryException(
          canonical,
          _singletons[canonical]?.runtimeType ?? definition.beanType,
        );
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
  bool containsBean(String name) =>
      containsLocalBean(name) || (_parent?.containsBean(name) ?? false);

  @override
  bool containsBeanOfType(
    Type type, {
    String? qualifier,
    bool includeAncestors = true,
  }) =>
      _localCandidates(type).any(
        (candidate) =>
            candidate.isAutowireCandidate &&
            (qualifier == null
                ? candidate.isDefaultCandidate
                : candidate.qualifies(qualifier)),
      ) ||
      (qualifier == null && _resolvable.containsKey(type)) ||
      (includeAncestors &&
          (_parent?.containsBeanOfType(type, qualifier: qualifier) ?? false));

  @override
  bool isTypeMatch(String name, Type type) {
    final definition = _definitionForName(name);
    if (definition == null) {
      return _parentOrThrow(name).isTypeMatch(name, type);
    }
    if (type == Object) {
      return true;
    }
    if (name.startsWith(BeanFactory.factoryBeanPrefix)) {
      return definition.isFactoryBean && definition.types.contains(type);
    }
    return definition.isFactoryBean
        ? definition.factoryObjectTypes!.contains(type)
        : definition.types.contains(type);
  }

  @override
  bool isFactoryBean(String name) {
    final definition = _definitionForName(name);
    if (definition != null) {
      return definition.isFactoryBean;
    }
    return switch (_parentOrThrow(name)) {
      final ConfigurableBeanFactory parent => parent.isFactoryBean(name),
      _ => false,
    };
  }

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
      if (definition.isPrototype) {
        return true;
      }
      return switch (_instanceOf(definition)) {
        final SmartFactoryBean<Object> smart => smart.isPrototype,
        final FactoryBean<Object> factory => !factory.isSingleton,
        _ => false,
      };
    }
    return definition.isPrototype;
  }

  BeanFactory _parentOrThrow(String name) =>
      _parent != null && _parent!.containsBean(name)
      ? _parent!
      : throw NoSuchBeanDefinitionException.named(name);

  @override
  Type? getType(String name) {
    final canonical = _canonical(_stripFactoryPrefix(name));
    final definition = _localDefinition(canonical);
    if (definition == null) {
      return _parent != null && _parent!.containsBean(name)
          ? _parent!.getType(name)
          : null;
    }
    final manual = _manualDefinitions.containsKey(canonical);
    if (definition.isFactoryBean &&
        !name.startsWith(BeanFactory.factoryBeanPrefix)) {
      final products = definition.factoryObjectTypes!;
      return products.isNotEmpty
          ? products.first
          : _factoryProducts[canonical]?.runtimeType;
    }
    return manual ? _singletons[canonical]?.runtimeType : definition.beanType;
  }

  // ---------------------------------------------------------------------
  // Listing
  // ---------------------------------------------------------------------

  @override
  List<String> getBeanNamesForType(
    Type type, {
    bool includeNonSingletons = true,
  }) => [
    for (final candidate in _localCandidates(type))
      if (includeNonSingletons || candidate.definition!.isSingleton)
        candidate.name,
  ];

  @override
  Map<String, T> getBeansOfType<T extends Object>({
    bool includeNonSingletons = true,
  }) => {
    for (final candidate in _localCandidates(T))
      if (includeNonSingletons || candidate.definition!.isSingleton)
        candidate.name: candidate.resolve<T>(),
  };

  @override
  List<T> getSortedBeans<T extends Object>({String? qualifier}) => [
    for (final (_, bean) in _sortEntries([
      for (final candidate in _lookupCandidates(T, qualifier))
        (candidate.name, candidate.resolve<T>(), candidate.definition),
    ]))
      bean,
  ];

  @override
  List<String> getBeanNamesForAnnotation<A extends Object>() => [
    for (final definition in _definitions.values)
      if (definition.annotations.any((annotation) => annotation is A))
        definition.name,
  ];

  @override
  Map<String, Object> getBeansWithAnnotation<A extends Object>() => {
    for (final name in getBeanNamesForAnnotation<A>())
      name: getBeanByName(name),
  };

  @override
  A? findAnnotationOnBean<A extends Object>(String beanName) {
    final definition = _definitionForName(beanName);
    if (definition != null) {
      return definition.annotations.whereType<A>().firstOrNull;
    }
    return switch (_parentOrThrow(beanName)) {
      final ListableBeanFactory parent => parent.findAnnotationOnBean<A>(
        beanName,
      ),
      _ => null,
    };
  }

  /// Stable sort: `PriorityOrdered` first, then by order (see
  /// [_orderOf]), then registration order.
  static List<(String, T)> _sortEntries<T extends Object>(
    List<(String, T, BeanDefinition<Object>?)> entries,
  ) {
    final indexed = entries.indexed.toList()
      ..sort((a, b) {
        final (aIndex, (_, aBean, aDefinition)) = a;
        final (bIndex, (_, bBean, bDefinition)) = b;
        final aPriority = aBean is PriorityOrdered ? 0 : 1;
        final bPriority = bBean is PriorityOrdered ? 0 : 1;
        if (aPriority != bPriority) {
          return aPriority - bPriority;
        }
        final byOrder = _orderOf(
          aBean,
          aDefinition,
        ).compareTo(_orderOf(bBean, bDefinition));
        return byOrder != 0 ? byOrder : aIndex - bIndex;
      });
    return [for (final (_, (name, bean, _)) in indexed) (name, bean)];
  }

  /// The order of [bean]: an `@Order` on its `@Bean` method beats
  /// `Ordered.order`, which beats an `@Order` on its class (Spring's
  /// `FactoryAwareOrderSourceProvider`).
  static int _orderOf(Object bean, BeanDefinition<Object>? definition) {
    final order = definition?.order;
    if (order != null && definition!.factoryMethodName != null) {
      return order;
    }
    return OrderComparator.orderOf(bean, order);
  }

  // ---------------------------------------------------------------------
  // Dependency resolution (generated code)
  // ---------------------------------------------------------------------

  @override
  T dependency<T extends Object>({String? qualifier, String? name}) =>
      _injecting(
        Dependency(T, qualifier: qualifier, name: name),
        () => _resolveDependency<T>(
          qualifier: qualifier,
          name: name,
          requester: _currentBean,
          required: true,
          direct: true,
        )!,
      );

  @override
  T? optionalDependency<T extends Object>({String? qualifier, String? name}) =>
      _injecting(
        Dependency(T, qualifier: qualifier, name: name, optional: true),
        () => _resolveDependency<T>(
          qualifier: qualifier,
          name: name,
          requester: _currentBean,
          required: false,
          direct: true,
        ),
      );

  @override
  List<T> dependencyList<T extends Object>({String? qualifier}) =>
      optionalDependencyList<T>(qualifier: qualifier) ??
      _injecting(
        Dependency.collection(T, qualifier: qualifier),
        () => throw NoSuchBeanDefinitionException(
          T,
          qualifier: qualifier,
          requiredBy: _currentBean,
        ),
      );

  @override
  List<T>? optionalDependencyList<T extends Object>({String? qualifier}) =>
      _injecting(Dependency.collection(T, qualifier: qualifier), () {
        final entries = _resolveMultiple<T>(qualifier, _currentBean);
        if (entries.isEmpty) {
          return null;
        }
        return [
          for (final (_, bean) in _sortEntries([
            for (final (candidate, bean) in entries)
              (candidate.name, bean, candidate.definition),
          ]))
            bean,
        ];
      });

  @override
  Map<String, T> dependencyMap<T extends Object>({String? qualifier}) =>
      optionalDependencyMap<T>(qualifier: qualifier) ??
      _injecting(
        Dependency.map(T, qualifier: qualifier),
        () => throw NoSuchBeanDefinitionException(
          T,
          qualifier: qualifier,
          requiredBy: _currentBean,
        ),
      );

  @override
  Map<String, T>? optionalDependencyMap<T extends Object>({
    String? qualifier,
  }) => _injecting(Dependency.map(T, qualifier: qualifier), () {
    final entries = _resolveMultiple<T>(qualifier, _currentBean);
    if (entries.isEmpty) {
      return null;
    }
    return {for (final (candidate, bean) in entries) candidate.name: bean};
  });

  @override
  ObjectProvider<T> provider<T extends Object>({
    String? qualifier,
    String? name,
  }) => _BeanObjectProvider<T>.injected(this, qualifier, name, _currentBean);

  @override
  T Function() lazyDependency<T extends Object>({
    String? qualifier,
    String? name,
  }) {
    // Resolved later on behalf of the bean being created now, so a lazy
    // `Greeter` in a `@Primary` Greeter decorator still gets the other one.
    final requester = _currentBean;
    return () => _resolveDependency<T>(
      qualifier: qualifier,
      name: name,
      requester: requester,
      required: true,
    )!;
  }

  @override
  T value<T>(String expression) => _value<T>(expression, optional: false) as T;

  @override
  T? optionalValue<T>(String expression) =>
      _value<T>(expression, optional: true);

  /// Resolves placeholders, evaluates the result with the
  /// [beanExpressionResolver] (which looks for its own template prefix,
  /// `#{` by default) and converts to [T]. An optional value is `null` when
  /// a placeholder cannot be resolved.
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
    final expressionResolver = beanExpressionResolver;
    final Object? evaluated = expressionResolver == null
        ? resolved
        : expressionResolver.evaluate(resolved, this);
    // A Resource comes from the context's loader, like Spring's
    // ResourceEditor (consulted before the conversion service).
    final loader = resourceLoader;
    if (loader != null &&
        evaluated is String &&
        (T == Resource || T == _typeOf<Resource?>())) {
      return loader.getResource(evaluated.trim()) as T;
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
        if (_destroyingSingletons) {
          throw BeanCreationNotAllowedException(name);
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
    final name = definition.name;
    if (factory is! FactoryBean<Object>) {
      throw BeanIsNotAFactoryException(name, factory.runtimeType);
    }
    final shared = definition.isSingleton && factory.isSingleton;
    if (shared) {
      final cached = _factoryProducts[name];
      if (cached != null) {
        return cached;
      }
    }
    // getObject() asking (directly or through other beans) for the product
    // it is creating would recurse forever.
    final start = _productsInCreation[name];
    if (start != null) {
      throw BeanCurrentlyInCreationException.factoryProduct([
        name,
        ..._inCreation.sublist(start),
        name,
      ]);
    }
    _productsInCreation[name] = _inCreation.length;
    try {
      final product = _createProduct(name, factory);
      if (shared) {
        _factoryProducts[name] = product;
      }
      return product;
    } finally {
      _productsInCreation.remove(name);
    }
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
    } on BeanCreationException catch (error, stackTrace) {
      if (error.beanName == name) {
        rethrow;
      }
      throw BeanCreationException(name, error, stackTrace);
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
    // wrapped it. They run one after another, an asynchronous one awaited
    // before the next; the bean is exposed while its Future is pending.
    final initializing = raw is InitializingBean;
    final init = _runInOrder(
      [
        if (definition == null)
          () => _configurablePostConstruct[raw.runtimeType]?.call(raw)
        else
          () => definition.invokePostConstruct(raw),
        if (raw is InitializingBean) raw.afterPropertiesSet,
        // Like Spring, an init method named afterPropertiesSet runs once.
        if (definition != null &&
            !(initializing &&
                definition.initMethodName == 'afterPropertiesSet'))
          () => definition.invokeInitMethod(raw),
      ].iterator,
    );
    if (init is Future<void>) {
      final pending = _pendingInits;
      if (pending == null) {
        init.ignore();
        throw StateError(
          "An init callback of bean '$name' returned a Future. Asynchronous "
          'init callbacks are awaited by refreshAsync() for the beans created '
          'during the refresh; a bean created later (lazy, prototype, scoped) '
          'needs synchronous ones.',
        );
      }
      pending.add((name, init));
    }
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
  void destroyBean(Object existingBean, {String? beanName}) {
    if (beanName != null) {
      final definition = getBeanDefinition(beanName);
      final raw = _canExpando(existingBean) ? _scopedRaw[existingBean] : null;
      _destroyBean(definition, raw ?? existingBean, existingBean);
      return;
    }
    final name = '${existingBean.runtimeType}';
    _destructionAwareCallbacks(existingBean, name);
    if (_configurablePreDestroy[existingBean.runtimeType]
        case final callback?) {
      _guardDestruction(name, () => callback(existingBean));
    }
    if (existingBean is DisposableBean) {
      _guardDestruction(name, existingBean.destroy);
    }
  }

  @override
  void preInstantiateSingletons() {
    final pending = _createEagerSingletons();
    if (pending.isNotEmpty) {
      for (final (_, future) in pending) {
        future.ignore();
      }
      final (name, _) = pending.first;
      throw BeanCreationException(
        name,
        StateError(
          'An init callback returned a Future; refresh the context with '
          'refreshAsync() to await asynchronous init callbacks.',
        ),
        StackTrace.current,
      );
    }
    _afterSingletonsInstantiated();
  }

  @override
  Future<void> preInstantiateSingletonsAsync() async {
    final pending = _createEagerSingletons();
    // Every Future gets its listener right away (no unhandled errors);
    // the first failure wins, named after its bean.
    await Future.wait<void>([
      for (final (name, future) in pending)
        future.catchError(
          (Object error, StackTrace stackTrace) =>
              throw BeanCreationException(name, error, stackTrace),
        ),
    ], eagerError: true);
    _afterSingletonsInstantiated();
  }

  // Creates the eager singletons and ends the collection of asynchronous
  // init callbacks, returning the pending ones.
  List<(String, Future<void>)> _createEagerSingletons() {
    // Copy: creating beans may register further definitions.
    for (final definition in _definitions.values.toList()) {
      if (definition.isSingleton && !definition.lazy) {
        final instance = _instanceOf(definition);
        if (definition.isFactoryBean &&
            instance is SmartFactoryBean<Object> &&
            instance.isEagerInit) {
          _productOf(definition, instance);
        }
      }
    }
    final pending = _pendingInits ?? const [];
    _pendingInits = null;
    return pending;
  }

  void _afterSingletonsInstantiated() {
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
    // with a depth-first search. Registered singletons and parent beans
    // are leaves: they cannot point back into this factory.
    final edges = <String, List<String>>{};
    for (final definition in _definitions.values) {
      final targets = edges[definition.name] = [];
      for (final name in definition.dependsOn) {
        final target = _canonical(name);
        if (_definitions.containsKey(target)) {
          targets.add(target);
        } else if (!_manualDefinitions.containsKey(target) &&
            !(_parent?.containsBean(name) ?? false)) {
          throw NoSuchBeanDefinitionException.named(
            name,
            requiredBy: definition.name,
          );
        }
      }
      for (final dependency in definition.dependencies) {
        targets.addAll(_checkedDependency(definition, dependency));
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

  /// Names of the local definitions among [candidates] (graph edges).
  List<String> _edges(Iterable<_Candidate> candidates) => [
    for (final candidate in candidates)
      if (identical(candidate.owner, this) &&
          _definitions.containsKey(candidate.beanName))
        candidate.beanName,
  ];

  /// [_validateDependency] with a failure (a missing or ambiguous bean, a
  /// placeholder without value) reported as an
  /// [UnsatisfiedDependencyException] naming the bean and the injection
  /// point, like a failure while the bean is created ([_injecting]).
  List<String> _checkedDependency(
    BeanDefinition<Object> definition,
    Dependency dependency,
  ) {
    try {
      return _validateDependency(definition, dependency);
    } on BeansException catch (error, stackTrace) {
      throw UnsatisfiedDependencyException(
        definition.name,
        dependency.toString(),
        error.message,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on PlaceholderResolutionException catch (error, stackTrace) {
      throw UnsatisfiedDependencyException(
        definition.name,
        dependency.toString(),
        error.message,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
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
          resolveEmbeddedValue(dependency.expression!);
        }
        return const [];
      case DependencyKind.collection || DependencyKind.map:
        final candidates = _autowireCandidates(
          dependency.type,
          dependency.qualifier,
          requester: definition.name,
          multiple: true,
        );
        if (candidates.isEmpty && !dependency.optional) {
          throw NoSuchBeanDefinitionException(
            dependency.type,
            qualifier: dependency.qualifier,
            requiredBy: definition.name,
          );
        }
        return _edges(candidates);
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
        final target = _determineAutowireCandidate(
          dependency.type,
          _autowireCandidates(
            dependency.type,
            dependency.qualifier,
            requester: definition.name,
            multiple: false,
          ),
          qualifier: dependency.qualifier,
          name: dependency.name,
          requiredBy: definition.name,
        );
        if (target != null) {
          return _edges([target]);
        }
        if (dependency.qualifier == null &&
            _resolvable.containsKey(dependency.type)) {
          return const [];
        }
        if (!dependency.optional) {
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
    _destroyingSingletons = true;
    try {
      for (final name in _creationOrder.toList().reversed) {
        // Synchronous: a returned Future is logged by _guardDestruction.
        _destroySingleton(name);
      }
    } finally {
      _destroyingSingletons = false;
    }
    _forgetSingletons();
  }

  @override
  Future<void> destroySingletonsAsync() async {
    _destructionErrors.clear();
    _destroyingSingletons = true;
    _asyncDestroy = true;
    try {
      for (final name in _creationOrder.toList().reversed) {
        await _destroySingleton(name);
      }
    } finally {
      _destroyingSingletons = false;
      _asyncDestroy = false;
    }
    _forgetSingletons();
  }

  void _forgetSingletons() {
    _singletons.removeWhere((name, _) => !_manualDefinitions.containsKey(name));
    _rawSingletons.removeWhere(
      (name, _) => !_manualDefinitions.containsKey(name),
    );
    _factoryProducts.clear();
    _creationOrder.clear();
    _disposables.clear();
    _dependents.clear();
    _dependencies.clear();
  }

  /// Destroys [name] after every bean that depends on it and forgets its
  /// dependency bookkeeping, like Spring's `destroyBean(name, bean)`; each
  /// call costs the number of its dependencies, so shutdown is linear.
  /// A `Future` when an awaited destroy callback is asynchronous.
  FutureOr<void> _destroySingleton(String name) {
    // Removing the dependents first also stops recursion on cycles of
    // dependent registrations.
    final dependents = _dependents.remove(name);
    return _runInOrder(
      [
        if (dependents != null)
          for (final dependent in dependents)
            () {
              _dependencies[dependent]?.remove(name);
              return _destroySingleton(dependent);
            },
        () => _destroyOwn(name),
      ].iterator,
    );
  }

  FutureOr<void> _destroyOwn(String name) {
    FutureOr<void> destroyed;
    if (_creationOrder.remove(name)) {
      final exposed = _singletons.remove(name);
      final raw = _rawSingletons.remove(name);
      final definition = _definitions[name];
      if (_disposables.remove(name) &&
          raw != null &&
          exposed != null &&
          definition != null) {
        destroyed = _destroyBean(definition, raw, exposed);
      }
    }
    if (destroyed is Future<void>) {
      return destroyed.then((_) => _forgetDependencies(name));
    }
    _forgetDependencies(name);
  }

  void _forgetDependencies(String name) {
    _factoryProducts.remove(name);
    final dependencies = _dependencies.remove(name);
    if (dependencies != null) {
      for (final dependency in dependencies) {
        final users = _dependents[dependency];
        if (users != null && users.remove(name) && users.isEmpty) {
          _dependents.remove(dependency);
        }
      }
    }
  }

  /// Runs destruction post-processors (on the exposed bean), then
  /// `@PreDestroy`, `DisposableBean.destroy` and the destroy method (on the
  /// raw bean), one after another. Errors are logged and collected in
  /// [destructionErrors]. A `Future` when a callback is asynchronous and
  /// awaited (see [_guardDestruction]).
  FutureOr<void> _destroyBean(
    BeanDefinition<Object> definition,
    Object raw,
    Object exposed,
  ) {
    final name = definition.name;
    _destructionAwareCallbacks(exposed, name);
    final disposable = raw is DisposableBean;
    // Like Spring, an inferred destroy method, or one named destroy, does
    // not run again for a DisposableBean.
    final destroyMethod = definition.destroyMethodName;
    return _runInOrder(
      [
        () => _guardDestruction(name, () => definition.invokePreDestroy(raw)),
        if (raw is DisposableBean) () => _guardDestruction(name, raw.destroy),
        if (!(disposable &&
            (destroyMethod == BeanDefinition.inferMethod ||
                destroyMethod == 'destroy')))
          () => _guardDestruction(
            name,
            () => definition.invokeDestroyMethod(raw),
          ),
      ].iterator,
    );
  }

  void _destructionAwareCallbacks(Object exposed, String name) {
    for (final processor in _postProcessors) {
      if (processor is DestructionAwareBeanPostProcessor &&
          processor.requiresDestruction(exposed)) {
        _guardDestruction(
          name,
          () => processor.postProcessBeforeDestruction(exposed, name),
        );
      }
    }
  }

  // Runs a destroy callback: errors are logged and collected. A returned
  // Future is awaited in destroySingletonsAsync; elsewhere the callback
  // goes on unawaited, its errors logged too, and the bean is reported.
  FutureOr<void> _guardDestruction(
    String name,
    FutureOr<void> Function() callback,
  ) {
    try {
      final result = callback();
      if (result is Future<void>) {
        final guarded = result.then(
          (_) {},
          onError: (Object error, StackTrace stackTrace) =>
              _destructionFailed(name, error, stackTrace),
        );
        if (_asyncDestroy) {
          return guarded;
        }
        _destructionFailed(
          name,
          StateError(
            'A destroy callback returned a Future that is not awaited; '
            'close the context with closeAsync() to await it.',
          ),
          StackTrace.current,
        );
      }
    } catch (error, stackTrace) {
      _destructionFailed(name, error, stackTrace);
    }
  }

  void _destructionFailed(String name, Object error, StackTrace stackTrace) {
    _destructionErrors.add(error);
    _destroyLog.warning(
      "Destroy callback of bean '$name' failed",
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Expando keys cannot be numbers, strings, booleans or records.
  static bool _canExpando(Object value) =>
      value is! num && value is! String && value is! bool && value is! Record;

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

/// A bean of a requested type in a factory of the hierarchy.
final class _Candidate {
  _Candidate(this.owner, this.name, this.definition);

  /// The factory holding the bean.
  final BeanFactory owner;

  /// The bean name as `getBeanNamesForType` lists it: `&name` for a factory
  /// bean looked up by its own type.
  final String name;

  /// The definition, when the owner exposes it.
  final BeanDefinition<Object>? definition;

  String get beanName => DefaultListableBeanFactory._stripFactoryPrefix(name);

  bool get primary => definition?.primary ?? false;

  bool get fallback => definition?.fallback ?? false;

  bool get isAutowireCandidate => definition?.autowireCandidate ?? true;

  bool get isDefaultCandidate => definition?.defaultCandidate ?? true;

  /// Whether [qualifier] selects the bean (name, alias or qualifier).
  bool qualifies(String qualifier) => switch (owner) {
    final DefaultListableBeanFactory factory => factory._qualifies(
      definition!,
      qualifier,
    ),
    _ =>
      (definition?.isQualifiedBy(qualifier) ?? false) || matchesName(qualifier),
  };

  /// Whether [candidateName] is the bean's name or an alias.
  bool matchesName(String candidateName) => switch (owner) {
    final DefaultListableBeanFactory factory => factory._matchesBeanName(
      definition!,
      candidateName,
    ),
    _ =>
      beanName == candidateName ||
          owner.getAliases(beanName).contains(candidateName),
  };

  /// The bean (or factory product) as [T], created by its owner.
  T resolve<T extends Object>() => switch (owner) {
    final DefaultListableBeanFactory factory =>
      DefaultListableBeanFactory._castTo<T>(
        factory._objectFor(definition!, T),
        beanName,
      ),
    _ => DefaultListableBeanFactory._castTo<T>(
      owner.getBeanByName(name),
      beanName,
    ),
  };
}

/// [ObjectProvider] backed by a [DefaultListableBeanFactory]: a lookup
/// (`getBeanProvider`) or an injection point ([_BeanObjectProvider.injected]).
final class _BeanObjectProvider<T extends Object> extends Iterable<T>
    implements ObjectProvider<T> {
  _BeanObjectProvider(this._factory, this._qualifier)
    : _name = null,
      _requester = null,
      _injected = false;

  /// Resolves like an injection point named [_name] of [_requester].
  _BeanObjectProvider.injected(
    this._factory,
    this._qualifier,
    this._name,
    this._requester,
  ) : _injected = true;

  final DefaultListableBeanFactory _factory;
  final String? _qualifier;
  final String? _name;
  final String? _requester;
  final bool _injected;

  T? _resolve({required bool required}) => _injected
      ? _factory._resolveDependency<T>(
          qualifier: _qualifier,
          name: _name,
          requester: _requester,
          required: required,
        )
      : _factory._getBean<T>(_qualifier, required: required);

  List<_Candidate> get _candidates => _injected
      ? _factory._autowireCandidates(
          T,
          _qualifier,
          requester: _requester,
          multiple: true,
        )
      : _factory._lookupCandidates(T, _qualifier);

  T _beanOf(_Candidate candidate) {
    final requester = _requester;
    if (requester != null) {
      _factory._registerDependency(candidate, requester, direct: false);
    }
    return candidate.resolve<T>();
  }

  @override
  T getObject() => _resolve(required: true)!;

  @override
  T? getIfAvailable([T Function()? defaultSupplier]) =>
      _resolve(required: false) ?? defaultSupplier?.call();

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
  List<T> orderedList() => [
    for (final (_, bean) in DefaultListableBeanFactory._sortEntries([
      for (final candidate in _candidates)
        (candidate.name, _beanOf(candidate), candidate.definition),
    ]))
      bean,
  ];

  // Beans are created one by one while iterating (Spring's stream()).
  @override
  Iterator<T> get iterator => _candidates.map(_beanOf).iterator;

  @override
  bool get isEmpty => _candidates.isEmpty;

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  int get length => _candidates.length;

  @override
  String toString() => 'ObjectProvider<$T>';
}

const _log = SpringLog('spring_core_dart.beans');

// Named like Spring's DisposableBeanAdapter logger, which reports failed
// destroy callbacks.
const _destroyLog = SpringLog(
  'spring_core_dart.beans.factory.support.DisposableBeanAdapter',
);

/// Runs [steps] one after another; when one returns a `Future`, the rest
/// run after it completes and the result is a `Future` (synchronous
/// otherwise).
FutureOr<void> _runInOrder(Iterator<FutureOr<void> Function()> steps) {
  while (steps.moveNext()) {
    final result = steps.current();
    if (result is Future<void>) {
      return result.then((_) => _runInOrder(steps));
    }
  }
}
