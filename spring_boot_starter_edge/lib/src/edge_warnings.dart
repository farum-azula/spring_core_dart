import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Names what works differently in a function, for the list the starter
/// logs once when a function starts.
///
/// One contributor per kind of thing; each reads the context for what it
/// covers and gives a line for every item it finds, or nothing. A bean of
/// this type adds its lines to the list:
///
/// ```dart
/// @Component()
/// class ReportFilesWarning implements EdgeWarningContributor {
///   @override
///   Iterable<String> warnings(ApplicationContext context) => [
///     'ReportFiles: a function has no file system; reports go to Storage',
///   ];
/// }
/// ```
abstract interface class EdgeWarningContributor {
  /// A line for every part of [context] that works differently in a
  /// function.
  Iterable<String> warnings(ApplicationContext context);
}

/// An in-memory rate limiter counts per instance, and a platform runs
/// many short-lived ones: the limit is then not one limit.
final class RateLimitStoreEdgeWarning implements EdgeWarningContributor {
  /// The contributor.
  const RateLimitStoreEdgeWarning();

  @override
  Iterable<String> warnings(ApplicationContext context) sync* {
    final store = context.getBeanProvider<RateLimitStore>().getIfAvailable();
    if (store is InMemoryRateLimitStore ||
        store is PrimaryIsolateRateLimitStore) {
      yield 'the rate limiter counts in memory: every instance has its own '
          'counters, so a limit is not one limit; use a shared store '
          '(spring.web.rate-limit.store: procedure or jdbc, or a '
          'RateLimitStore bean)';
    }
  }
}

/// The work beans run on timers ([TimerDrivenWork]: the scheduling
/// starter's `@Scheduled` methods), a line for each: a timer does not
/// outlive the request that started the instance.
final class TimerWorkEdgeWarning implements EdgeWarningContributor {
  /// The contributor over the beans of [beans].
  const TimerWorkEdgeWarning(this.beans);

  /// The bean factory of the application.
  final ConfigurableListableBeanFactory beans;

  @override
  Iterable<String> warnings(ApplicationContext context) sync* {
    for (final name in beans.singletonNames) {
      if (beans.getSingleton(name) case final TimerDrivenWork bean) {
        for (final work in bean.timerDrivenWork) {
          yield '$work: timers do not outlive a request; use the '
              "platform's cron to call an endpoint";
        }
      }
    }
  }
}

/// What beans keep in the memory of their instance ([IsolateLocalState]:
/// in-memory caches, in-memory sessions), a line for each bean: a
/// platform runs many short-lived instances, and they share no memory.
/// A bean that keeps its state elsewhere (a cache in a database) is not
/// one of them and is not listed.
final class InstanceStateEdgeWarning implements EdgeWarningContributor {
  /// The contributor over the beans of [beans].
  const InstanceStateEdgeWarning(this.beans);

  /// The bean factory of the application.
  final ConfigurableListableBeanFactory beans;

  @override
  Iterable<String> warnings(ApplicationContext context) sync* {
    for (final name in beans.singletonNames) {
      final bean = beans.getSingleton(name);
      // The rate limiter has a line of its own.
      if (bean is IsolateLocalState && bean is! RateLimitStore) {
        yield "${bean.isolateLocalState} (bean '$name'): kept in the memory "
            'of each short-lived instance, not shared between instances';
      }
    }
  }
}

/// Logs once, when a function starts, what its [EdgeWarningContributor]
/// beans found (the bean `edgeWarnings`); nothing found, nothing logged.
/// `spring.edge.warnings: false` turns it off.
final class EdgeWarnings
    implements ApplicationContextAware, SmartInitializingSingleton {
  /// The list of [contributors].
  EdgeWarnings(
    this.contributors, {
    this.log = const SpringLog('spring.edge'),
  });

  /// The contributors, in the order of their beans.
  final List<EdgeWarningContributor> contributors;

  /// Where the list goes.
  final SpringLog log;

  ApplicationContext? _context;

  /// The lines found at start.
  List<String> found = const [];

  @override
  void setApplicationContext(ApplicationContext context) => _context = context;

  @override
  void afterSingletonsInstantiated() {
    final context = _context;
    if (context == null) {
      return;
    }
    found = List.unmodifiable([
      for (final contributor in contributors) ...contributor.warnings(context),
    ]);
    if (found.isNotEmpty) {
      log.warning(
        'Running as a function; these work differently here:\n'
        '${found.map((line) => '  - $line').join('\n')}',
      );
    }
  }
}
