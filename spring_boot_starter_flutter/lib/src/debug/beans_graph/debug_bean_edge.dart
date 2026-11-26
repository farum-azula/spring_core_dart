/// How the bean at the start of a [DebugBeanEdge] gets the one at its end.
enum DebugBeanEdgeKind {
  /// Injected when the bean is created: a constructor parameter, a field,
  /// a setter, a `@Resource`.
  direct,

  /// One of the beans of a `List`, `Set` or `Map` injected when the bean
  /// is created.
  collection,

  /// A `@Lazy` point: resolved on first use, never part of a cycle.
  lazy,

  /// An `ObjectProvider` (or `ObjectFactory`, `Provider`): resolved when
  /// the bean asks, never part of a cycle.
  provider,

  /// `@DependsOn`: created before, destroyed after, without injection.
  dependsOn,

  /// A bean in the record of a Spring widget (`SpringStatelessWidget`,
  /// `SpringState`).
  widget,
}

/// "[from] depends on [to]": an edge of a [DebugBeanGraphSnapshot].
final class DebugBeanEdge {
  /// The edge from [from] to [to] of [kind].
  const DebugBeanEdge(
    this.from,
    this.to,
    this.kind, {
    this.declared = true,
    this.observed = false,
  });

  /// The bean that depends (or the widget's name).
  final String from;

  /// The bean it depends on.
  final String to;

  /// How it gets it.
  final DebugBeanEdgeKind kind;

  /// Whether the definition declares it: an injection point the generator
  /// listed, or a `@DependsOn`. A hand-written definition declares none.
  final bool declared;

  /// Whether the container saw [from] take [to] since the beans were
  /// created (`getDependenciesForBean`): a declared edge used, or one only
  /// a hand-written definition's code knows of.
  final bool observed;

  /// Whether [to] is resolved later than [from]'s creation (a lazy point,
  /// a provider): such an edge never closes a cycle.
  bool get deferred =>
      kind == DebugBeanEdgeKind.lazy || kind == DebugBeanEdgeKind.provider;

  @override
  String toString() => '$from -${kind.name}-> $to';
}
