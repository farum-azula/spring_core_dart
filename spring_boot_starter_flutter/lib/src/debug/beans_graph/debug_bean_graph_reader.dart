import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_edge.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_graph_snapshot.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_module.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_role.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_skipped_bean.dart';
import 'package:spring_boot_starter_flutter/src/spring_widgets.dart';

/// Reads a [DebugBeanGraphSnapshot] from an application context, without
/// creating a bean: the definitions, the singletons created, the
/// condition evaluation report, the startup trace, the advisors of the
/// created proxies and the Spring widgets' bindings. The
/// [DebugBeanGraph] runs it on demand; nothing of it runs otherwise.
final class DebugBeanGraphReader {
  /// A reader of [context] by [modules] and [roles]; [instances] holds
  /// the live instances of the beans that are no singletons, as the
  /// graph counted them; [declaredEdges] keeps the edges of the
  /// definitions' injection points from one read to the next (the
  /// definitions do not change once the context runs).
  DebugBeanGraphReader(
    this.context, {
    required this.modules,
    required this.roles,
    this.instances = const {},
    Map<String, List<DebugBeanEdge>>? declaredEdges,
  }) : declaredEdges = declaredEdges ?? {};

  /// The application.
  final ConfigurableApplicationContext context;

  /// Where its beans come from.
  final DebugBeanModules modules;

  /// The roles of its beans.
  final DebugBeanRoles roles;

  /// The instances of the beans of custom scopes and prototypes, by name.
  final Map<String, int> instances;

  /// The declared edges by bean name, resolved once.
  final Map<String, List<DebugBeanEdge>> declaredEdges;

  /// The step the bean factory records each bean's creation as.
  static const instantiateStep = 'spring.beans.instantiate';

  ConfigurableListableBeanFactory get _factory => context.beanFactory;

  /// The snapshot: only the application's beans, or with
  /// [includeFramework] the framework's too.
  DebugBeanGraphSnapshot read({bool includeFramework = false}) {
    bool included(DebugBeanOrigin origin) =>
        includeFramework || origin.application;
    final factory = _factory;
    final conditions = _conditionsBySource();
    final trace = _trace();
    final advisorNames = _advisorNames();
    final order = {
      for (final (index, name) in factory.singletonNames.indexed) name: index,
    };
    final beans = <DebugBean>[];
    final edges = <(String, String), DebugBeanEdge>{};
    final definitionNames = factory.beanDefinitionNames;
    for (final name in definitionNames) {
      final definition = factory.getBeanDefinition(name);
      final origin = modules.originOf(name, definition.source);
      if (!included(origin)) {
        continue;
      }
      beans.add(
        _bean(
          definition,
          origin,
          conditions: [
            for (final source in _conditionSources(definition))
              ...?conditions[source],
          ],
          step: trace[name],
          order: order[name],
          advisorNames: advisorNames,
        ),
      );
      _declaredEdges(definition, edges);
    }
    final known = definitionNames.toSet();
    for (final name in factory.singletonNames) {
      if (known.contains(name)) {
        continue;
      }
      final origin = modules.originOf(name, 'registerSingleton');
      if (included(origin)) {
        beans.add(_registered(name, origin, order[name]));
      }
    }
    for (final bean in beans) {
      _observedEdges(bean.name, edges);
    }
    _widgets(beans, edges, included);
    final names = {for (final bean in beans) bean.name};
    return DebugBeanGraphSnapshot(
      beans: beans,
      modules: _modules(beans),
      edges: [
        for (final edge in edges.values)
          if (names.contains(edge.from) && names.contains(edge.to)) edge,
      ],
      skipped: _skipped(conditions, known, included),
      includesFramework: includeFramework,
    );
  }

  DebugBean _bean(
    BeanDefinition<Object> definition,
    DebugBeanOrigin origin, {
    required List<DebugBeanCondition> conditions,
    required RecordedStartupStep? step,
    required int? order,
    required Map<Object, String> advisorNames,
  }) {
    final name = definition.name;
    final singleton = definition.isSingleton
        ? _factory.getSingleton(name)
        : null;
    return DebugBean(
      name: name,
      type: '${definition.beanType}',
      role: roles.of(definition, application: origin.application),
      module: origin.module,
      application: origin.application,
      scope: definition.scope,
      lazy: definition.lazy,
      primary: definition.primary,
      instances: definition.isSingleton
          ? (singleton == null ? 0 : 1)
          : instances[name] ?? 0,
      source: definition.source,
      description: definition.description,
      annotations: [
        for (final annotation in definition.annotations)
          '${annotation.runtimeType}',
      ],
      advisors: switch (singleton) {
        final Advised advised => [
          for (final advisor in advised.aopAdvisors)
            advisorNames[advisor] ?? '${advisor.advice.runtimeType}',
        ],
        _ => const [],
      },
      advisedMethods: [
        for (final signature
            in _proxyOf(definition)?.signatures ?? const <MethodSignature>[])
          if (signature.annotationTypes.isNotEmpty)
            DebugBeanAdvisedMethod(signature.name, signature.annotationTypes),
      ],
      conditions: conditions,
      eventListeners: [
        for (final listener in definition.eventListeners) listener.id,
      ],
      publishesEvents: definition.dependencies.any(
        (dependency) => dependency.type == ApplicationEventPublisher,
      ),
      creationOrder: singleton == null ? null : order,
      createdAt: step?.startedAt,
      creationTime: step?.duration,
    );
  }

  AopProxyFactory? _proxyOf(BeanDefinition<Object> definition) =>
      switch (_factory) {
        final DependencyResolver resolver => resolver.aopProxyOf(definition),
        _ => definition.aopProxy,
      };

  DebugBean _registered(String name, DebugBeanOrigin origin, int? order) =>
      DebugBean(
        name: name,
        type: '${_factory.getSingleton(name).runtimeType}',
        role: origin.application
            ? DebugBeanRole.component
            : DebugBeanRole.infrastructure,
        module: origin.module,
        application: origin.application,
        scope: ScopeType.singleton,
        instances: 1,
        source: 'registerSingleton',
        creationOrder: order,
      );

  // The definition's injection points and @DependsOn, resolved to the
  // beans the container would choose.
  void _declaredEdges(
    BeanDefinition<Object> definition,
    Map<(String, String), DebugBeanEdge> edges,
  ) {
    for (final edge in declaredEdges[definition.name] ??= _resolve(
      definition,
    )) {
      edges.putIfAbsent((edge.from, edge.to), () => edge);
    }
  }

  List<DebugBeanEdge> _resolve(BeanDefinition<Object> definition) {
    final from = definition.name;
    final edges = <String, DebugBeanEdge>{};
    void add(String to, DebugBeanEdgeKind kind) =>
        edges.putIfAbsent(to, () => DebugBeanEdge(from, to, kind));
    for (final name in definition.dependsOn) {
      add(name, DebugBeanEdgeKind.dependsOn);
    }
    final factory = _factory;
    if (factory is DefaultListableBeanFactory) {
      for (final dependency in definition.dependencies) {
        final kind = _edgeKinds[dependency.kind];
        if (kind == null) {
          continue;
        }
        for (final to in factory.dependencyCandidateNames(
          dependency,
          requester: from,
        )) {
          add(to, kind);
        }
      }
    }
    return List.unmodifiable(edges.values);
  }

  static const _edgeKinds = {
    DependencyKind.single: DebugBeanEdgeKind.direct,
    DependencyKind.resource: DebugBeanEdgeKind.direct,
    DependencyKind.collection: DebugBeanEdgeKind.collection,
    DependencyKind.map: DebugBeanEdgeKind.collection,
    DependencyKind.lazy: DebugBeanEdgeKind.lazy,
    DependencyKind.provider: DebugBeanEdgeKind.provider,
  };

  // What the container saw the bean take (getDependenciesForBean): marks
  // the declared edges used, adds those only a hand-written definition's
  // code knows of.
  void _observedEdges(
    String from,
    Map<(String, String), DebugBeanEdge> edges,
  ) {
    for (final to in _factory.getDependenciesForBean(from)) {
      final declared = edges[(from, to)];
      edges[(from, to)] = declared == null
          ? DebugBeanEdge(
              from,
              to,
              DebugBeanEdgeKind.direct,
              declared: false,
              observed: true,
            )
          : DebugBeanEdge(from, to, declared.kind, observed: true);
    }
  }

  // The Spring widgets of the generated bindings, as nodes, with an edge
  // to each bean of their record.
  void _widgets(
    List<DebugBean> beans,
    Map<(String, String), DebugBeanEdge> edges,
    bool Function(DebugBeanOrigin origin) included,
  ) {
    final factory = _factory;
    for (final holder in factory.getBeanNamesForType(SpringWidgetBindings)) {
      final bindings = factory.getSingleton(holder);
      final origin = modules.originOf(
        holder,
        factory.containsBeanDefinition(holder)
            ? factory.getBeanDefinition(holder).source
            : null,
      );
      if (bindings is! SpringWidgetBindings || !included(origin)) {
        continue;
      }
      for (final binding in bindings.bindings) {
        final name = binding.widget;
        beans.add(
          DebugBean(
            name: name,
            type: name.substring(name.indexOf('#') + 1),
            role: DebugBeanRole.widget,
            module: origin.application
                ? DebugBeanModules.applicationGroupOf(name)
                : origin.module,
            application: origin.application,
            scope: 'widget',
            source: name,
            beansType: binding.beans,
          ),
        );
        for (final type in binding.types) {
          final targets = factory is DefaultListableBeanFactory
              ? factory.dependencyCandidateNames(Dependency(type))
              : factory.getBeanNamesForType(type);
          for (final to in targets) {
            edges.putIfAbsent(
              (name, to),
              () => DebugBeanEdge(name, to, DebugBeanEdgeKind.widget),
            );
          }
        }
      }
    }
  }

  static List<DebugBeanModule> _modules(List<DebugBean> beans) {
    final byName = <String, (bool, List<String>)>{};
    for (final bean in beans) {
      byName
          .putIfAbsent(bean.module, () => (bean.application, []))
          .$2
          .add(
            bean.name,
          );
    }
    return [
      for (final MapEntry(key: name, value: (application, names))
          in byName.entries)
        DebugBeanModule(name: name, application: application, beans: names),
    ];
  }

  // The sources the report files a definition's conditions under: its
  // name, and the key of each group it shares with its class.
  static Iterable<String> _conditionSources(
    BeanDefinition<Object> definition,
  ) => {
    definition.name,
    for (final condition in definition.conditions)
      if (condition is ConditionGroup) condition.key,
  };

  Map<String, List<DebugBeanCondition>> _conditionsBySource() {
    final context = this.context;
    final evaluations = context is AnnotationConfigApplicationContext
        ? context.conditionEvaluations
        : const <ConditionEvaluation>[];
    final bySource = <String, List<DebugBeanCondition>>{};
    for (final evaluation in evaluations) {
      (bySource[evaluation.source] ??= []).add(
        DebugBeanCondition(
          '${evaluation.condition}',
          matched: evaluation.matched,
        ),
      );
    }
    return bySource;
  }

  List<DebugSkippedBean> _skipped(
    Map<String, List<DebugBeanCondition>> conditions,
    Set<String> registered,
    bool Function(DebugBeanOrigin origin) included,
  ) => [
    for (final MapEntry(key: source, value: outcomes) in conditions.entries)
      if (!registered.contains(source) &&
          outcomes.any((outcome) => !outcome.matched))
        if (modules.originOf(source, null) case final origin
            when included(origin))
          DebugSkippedBean(
            source: source,
            module: origin.module,
            application: origin.application,
            conditions: outcomes,
          ),
  ];

  Map<String, RecordedStartupStep> _trace() {
    final startup = switch (_factory) {
      final DefaultListableBeanFactory factory => factory.applicationStartup,
      _ => null,
    };
    if (startup is! BufferingApplicationStartup) {
      return const {};
    }
    return {
      for (final step in startup.steps)
        if (step.name == instantiateStep)
          for (final (key, value) in step.tags)
            if (key == 'beanName' && value is String) value: step,
    };
  }

  // The advisor beans created, by identity, to name the advisors of a
  // proxy.
  Map<Object, String> _advisorNames() {
    final factory = _factory;
    final names = Map<Object, String>.identity();
    for (final name in factory.getBeanNamesForType(Advisor)) {
      if (factory.getSingleton(name) case final advisor?) {
        names[advisor] = name;
      }
    }
    return names;
  }
}
