import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#IsolateAutoConfiguration';

/// The beans about isolates, each left out when the app declares its own:
///
/// - `isolateInfo` ([IsolateInfo]): the isolate the context runs in;
/// - `isolateLoadSampler` ([IsolateLoadSampler]): how busy that isolate
///   is, measured only while someone reads it;
/// - `isolateTaskExecutor` ([IsolateTaskExecutor]): a pool of isolates for
///   work that would block (`spring.task.execution.isolates.*`), which
///   starts no isolate before its first task; shut down with the context;
/// - `isolateLoads` ([IsolateLoads]): the load of every isolate known,
///   from each [IsolateLoadSource] bean (the two above, and the web
///   server's pool);
/// - `isolateReports` ([IsolateReports]): what each isolate of a pool
///   tells the primary, from each [IsolateReporter] bean;
/// - `primaryIsolate` ([PrimaryIsolate]): asks the first isolate, where
///   each [PrimaryIsolateHandler] bean answers; `isolateLoadsHandler`
///   ([IsolateLoadsHandler]) is one, answering every isolate's load.
///
/// Spring Boot: `TaskExecutionAutoConfiguration` for the executor; the
/// rest has no counterpart.
final isolateAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<IsolateInfo>(
    name: 'isolateInfo',
    factoryMethodName: 'isolateInfo',
    source: _source,
    conditions: const [
      ConditionGroup('$_source#isolateInfo', [
        ConditionalOnMissingBean(IsolateInfo),
      ]),
    ],
    create: (_) => IsolateInfo.current,
  ),
  BeanDefinition<IsolateLoadSampler>(
    name: 'isolateLoadSampler',
    factoryMethodName: 'isolateLoadSampler',
    types: const [IsolateLoadSampler, IsolateLoadSource],
    source: _source,
    conditions: const [
      ConditionGroup('$_source#isolateLoadSampler', [
        ConditionalOnMissingBean(IsolateLoadSampler),
      ]),
    ],
    create: (_) => IsolateLoadSampler(),
    destroyMethodName: 'stop',
    destroyMethod: (sampler) => sampler.stop(),
  ),
  BeanDefinition<IsolateTaskExecutor>(
    name: 'isolateTaskExecutor',
    factoryMethodName: 'isolateTaskExecutor',
    types: const [IsolateTaskExecutor, IsolateLoadSource],
    source: _source,
    conditions: const [
      ConditionGroup('$_source#isolateTaskExecutor', [
        ConditionalOnMissingBean(IsolateTaskExecutor),
      ]),
    ],
    create: (r) {
      final pool = r.dependency<TaskExecutionIsolatesProperties>();
      return IsolateTaskExecutor(
        settings: IsolateTaskExecutorSettings(
          coreSize: pool.coreSize,
          maxSize: pool.maxSize,
          keepAlive: pool.keepAlive,
          queueCapacity: pool.queueCapacity,
          allowCoreTimeout: pool.allowCoreTimeout,
          // In an isolate of the server's pool its name comes first, so
          // every task isolate of the application has a name of its own.
          namePrefix: IsolateInfo.current.primary
              ? pool.namePrefix
              : '${IsolateInfo.current.name}-${pool.namePrefix}',
        ),
      );
    },
    destroyMethodName: 'shutdown',
    destroyMethod: (executor) => executor.shutdown(),
  ),
  BeanDefinition<IsolateLoads>(
    name: 'isolateLoads',
    factoryMethodName: 'isolateLoads',
    source: _source,
    conditions: const [
      ConditionGroup('$_source#isolateLoads', [
        ConditionalOnMissingBean(IsolateLoads),
      ]),
    ],
    create: (r) => IsolateLoads(
      r.optionalDependencyList<IsolateLoadSource>() ?? const [],
    ),
  ),
  BeanDefinition<PrimaryIsolate>(
    name: 'primaryIsolate',
    factoryMethodName: 'primaryIsolate',
    source: _source,
    conditions: const [
      ConditionGroup('$_source#primaryIsolate', [
        ConditionalOnMissingBean(PrimaryIsolate),
      ]),
    ],
    create: (r) => PrimaryIsolate(
      r.optionalDependencyList<PrimaryIsolateHandler>() ?? const [],
    ),
  ),
  BeanDefinition<IsolateLoadsHandler>(
    name: 'isolateLoadsHandler',
    types: const [IsolateLoadsHandler, PrimaryIsolateHandler],
    source: _source,
    create: (r) => IsolateLoadsHandler(
      r.dependency<IsolateLoads>(),
      r.dependency<IsolateReports>(),
    ),
  ),
  BeanDefinition<IsolateReports>(
    name: 'isolateReports',
    factoryMethodName: 'isolateReports',
    source: _source,
    conditions: const [
      ConditionGroup('$_source#isolateReports', [
        ConditionalOnMissingBean(IsolateReports),
      ]),
    ],
    create: (r) => IsolateReports(
      r.optionalDependencyList<IsolateReporter>() ?? const [],
    ),
  ),
];

/// Answers every isolate's load from the application's first isolate
/// (`isolates.loads` of [PrimaryIsolate.ask]): the rows of [IsolateLoads]
/// as JSON, the isolates of the server's pool asked just before. So a
/// request that reaches any isolate can show them all.
final class IsolateLoadsHandler implements PrimaryIsolateHandler {
  /// The handler of [loads], brought up to date through [reports].
  const IsolateLoadsHandler(this.loads, this.reports);

  /// The name it answers under.
  static const handlerId = 'isolates.loads';

  /// Every isolate's load, in the first isolate.
  final IsolateLoads loads;

  /// Asks the other isolates.
  final IsolateReports reports;

  @override
  String get id => handlerId;

  @override
  Future<Object?> handle(Object? request) async {
    // The first read starts the measuring; the pool's isolates answer it.
    loads.all();
    await reports.refresh();
    return [for (final load in loads.all()) load.toJson()];
  }
}
