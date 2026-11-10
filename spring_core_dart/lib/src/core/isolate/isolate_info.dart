/// The isolate the code runs in: its name, as the logs show it
/// (`%thread`), and its place in the application's pool of isolates.
///
/// An application runs in one isolate, `main`, unless the web server runs
/// a pool (`server.isolates.count`): then every isolate of the pool runs
/// the whole application, with its own beans, and the first one is the
/// primary. Use it for work that must happen once for the application and
/// not once per isolate: a scheduled job, a data migration, a warm-up.
///
/// ```dart
/// @Component()
/// class Migrations {
///   Migrations(this.isolate);
///   final IsolateInfo isolate;
///
///   @PostConstruct()
///   void run() {
///     if (isolate.primary) migrate();
///   }
/// }
/// ```
///
/// The bean `isolateInfo` is [current]; the condition
/// `@ConditionalOnPrimaryIsolate()` keeps a whole bean to the primary.
///
/// Spring has no counterpart: its beans share one JVM and its threads.
final class IsolateInfo {
  /// The isolate named [name], number [index] of its pool.
  const IsolateInfo({this.name = 'main', this.index = 0, this.primary = true});

  /// The isolate's name in the logs: `main`, or `isolate-2` in a pool.
  final String name;

  /// Its number in the pool; `0` for the primary.
  final int index;

  /// Whether it is the first isolate of the application: the one that
  /// started the others, and the only one without a pool.
  final bool primary;

  /// The isolate this code runs in. A pool sets it in each isolate it
  /// starts, before the application starts there.
  static IsolateInfo current = const IsolateInfo();

  @override
  String toString() => name;
}

/// A bean that keeps state in the memory of its isolate: sessions, a
/// cache, counters.
///
/// With a pool of isolates each isolate has its own copy of such a bean,
/// and a request may reach any of them: a session made by one is unknown
/// to the next. The pool names every bean that implements this in one
/// warning when it starts, so the choice is made knowingly: keep the
/// state where all isolates see it (a database, a shared store), or
/// accept one copy per isolate (a cache often can).
abstract interface class IsolateLocalState {
  /// What is kept, for the warning: `sessions`, `the cache`.
  String get isolateLocalState;
}
