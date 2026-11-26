/// What happened to a bean in a [DebugBeanEvent].
enum DebugBeanEventKind {
  /// An instance was created (a route's bean when the screen opens, a
  /// lazy singleton on first use, a prototype).
  created,

  /// An instance was destroyed (a route's bean when the screen closes).
  destroyed,
}

/// A bean created or destroyed while the [DebugBeanGraph] runs.
final class DebugBeanEvent {
  /// The [kind] of event number [sequence] for the bean [beanName], [at].
  const DebugBeanEvent(this.sequence, this.kind, this.beanName, this.at);

  /// Its number, growing by one from event to event, so a reader takes
  /// those after the last it has seen (`eventsAfter`).
  final int sequence;

  /// What happened.
  final DebugBeanEventKind kind;

  /// The bean.
  final String beanName;

  /// When.
  final DateTime at;

  @override
  String toString() => '#$sequence ${kind.name} $beanName';
}
