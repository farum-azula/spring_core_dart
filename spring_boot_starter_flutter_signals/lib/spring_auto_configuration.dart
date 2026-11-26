/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_signals`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:flutter/widgets.dart' show ChangeNotifier, Listenable;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_errors.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_buffer.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart'
    show debugGraphPaneDefinitions, debugGraphSectionDefinitions;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show
        ConsolePane,
        ConsoleSegment,
        DebugConsolePane,
        DebugConsoleSegment,
        DebugGraphBuilders,
        DebugGraphLayer,
        DebugGraphPane,
        DebugGraphSection,
        DebugGraphWidgets,
        DebugGraphRoutes,
        DebugPanelSection,
        WidgetsGraphLayer,
        WidgetBuildTracker;
import 'package:spring_boot_starter_flutter_signals/src/debug/graph/signals_graph_layer.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signal_widget_names.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_debug_log.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_debug_recorder.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_console.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_pane.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_section.dart';
import 'package:spring_boot_starter_flutter_signals/src/properties/properties_beans.dart';
import 'package:spring_boot_starter_flutter_signals/src/properties/signals_properties.dart';
import 'package:spring_boot_starter_flutter_signals/src/signals_processors.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';

// The auto-configurations this starter builds on (the Flutter starter's,
// and through it logging and spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';

// One for the application: the state of its beans, and the names of
// those that have any.
SignalBeans _beansOf(DependencyResolver r) => r.dependency<SignalBeans>();

/// The beans the starter adds to a Flutter application:
///
/// - `signalBeans`: the followed state of every bean on signals;
/// - `signalRuntime`: their queues, buffers and error handling;
/// - `signalEffects`: starts their `@Effect` and watch methods when they
///   are made and ends their state when they are destroyed;
/// - `signalBuildTracker`: builds a Spring widget again when followed
///   state its `build` read has changed; it names the widgets for the
///   Signals tab only with `signalWidgetNames`, a bean of the debug module.
@AutoConfigurationModule()
final BeanModule springBootStarterFlutterSignalsAutoConfiguration = BeanModule(
  'springBootStarterFlutterSignalsAutoConfiguration',
  [
    BeanDefinition<SignalBeans>(
      name: 'signalBeans',
      types: const [SignalBeans, ChangeNotifier, Listenable],
      source: _source,
      preDestroy: (beans) => beans.dispose(),
      create: (_) => SignalBeans(),
    ),
    BeanDefinition<SignalRuntime>(
      name: 'signalRuntime',
      types: const [SignalRuntime],
      source: _source,
      preDestroy: (runtime) => runtime.close(),
      create: _runtimeOf,
    ),
    BeanDefinition<SignalEffects>(
      name: 'signalEffects',
      types: const [
        SignalEffects,
        DestructionAwareBeanPostProcessor,
        BeanPostProcessor,
        Ordered,
      ],
      source: _source,
      // Its beans looked up on first use, not when it is made: they would be
      // made before the other post-processors, which would skip them.
      create: (r) => SignalEffects(
        r.lazyDependency<SignalBeans>(),
        r.lazyDependency<SignalRuntime>(),
      ),
    ),
    BeanDefinition<SignalBuildTracker>(
      name: 'signalBuildTracker',
      types: const [SignalBuildTracker, WidgetBuildTracker],
      source: _source,
      // Without the signals' debug tools in the build there is no such
      // bean, and no name is kept for any widget.
      create: (r) =>
          SignalBuildTracker(r.optionalDependency<SignalWidgetNames>()),
    ),
  ],
  imports: [signalsConfigBeans],
);

// The queue [name] by [properties] (`null`: the defaults) and by the
// qualified schedule bean [bean]; both a bean and a `flush:` fail.
SignalQueueSettings _queueSettings(
  String name,
  SignalsQueueProperties? properties,
  SignalFlushSchedule? bean,
) {
  final flush = properties?.flush;
  if (bean != null && flush != null) {
    throw StateError(
      "The signal queue '$name' has both a SignalFlushSchedule bean with "
      "@Qualifier('$name') and spring.flutter.signals."
      "${name == 'default' ? 'queue' : 'queues.$name'}.flush: ${flush.name}. "
      'Keep one of them.',
    );
  }
  final settings = properties ?? const SignalsQueueProperties();
  return SignalQueueSettings(
    schedule:
        bean ??
        SignalFlushSchedules.named(
          flush ?? SignalFlush.microtask,
          settings.interval,
        ),
    capacity: settings.capacity,
    onOverflow: settings.onOverflow,
  );
}

// The SignalFlushSchedule beans by the queue their @Qualifier names.
Map<String, SignalFlushSchedule> _schedules(DependencyResolver r) {
  final factory = r.dependency<ListableBeanFactory>();
  final schedules = <String, SignalFlushSchedule>{};
  for (final name in factory.getBeanNamesForType(SignalFlushSchedule)) {
    final qualifiers = factory is BeanDefinitionRegistry
        ? (factory as BeanDefinitionRegistry).getBeanDefinition(name).qualifiers
        : const <String>{};
    final bean = r.dependency<SignalFlushSchedule>(name: name);
    for (final queue in qualifiers.isEmpty ? {name} : qualifiers) {
      schedules[queue] = bean;
    }
  }
  return schedules;
}

// What the properties say, with the schedules of the beans and the
// transactions of the TransactionLifecycleRegistry bean when the
// application has one (the data starter's).
SignalRuntime _runtimeOf(DependencyResolver r) {
  final properties = r.dependency<SignalsProperties>();
  final registry = r.provider<TransactionLifecycleRegistry>().getIfUnique();
  final handlers = r.provider<TypedErrorHandler<SignalExecutionException>>();
  final schedules = _schedules(r);
  final transactions =
      registry == null ||
          properties.transaction.mode == SignalTransactionMode.direct
      ? null
      : SignalTransactionBuffers(registry);
  final publishOnError =
      properties.buffer.onError == SignalBufferOnError.publish;
  return SignalRuntime(
    queues: SignalQueues(
      _queueSettings('default', properties.queue, schedules['default']),
      {
        for (final name in {...properties.queues.keys, ...schedules.keys})
          if (name != 'default')
            name: _queueSettings(
              name,
              properties.queues[name],
              schedules[name],
            ),
      },
    ),
    errors: SignalErrorReporter(handlers.getIfUnique),
    transactions: transactions,
    callerBound: properties.callerBound,
    eager: properties.eager,
    onScopeEnd: properties.onScopeEnd,
    deferTimeout: properties.deferTimeout,
    allowAdvice: properties.allowAdvice,
    bufferPublishOnError: publishOnError,
  );
}

// The Signals tab in a running app.
const _debugOn = ConditionalOnProperty(
  'spring.flutter.signals.debug.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

// The console's segment in a running app.
const _consoleOn = ConditionalOnProperty(
  'spring.flutter.debug.console.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

// What the tab and the console show, in each module that has one of them:
// the first makes it.
final BeanDefinition<SignalsDebugRecorder> _recorder =
    BeanDefinition<SignalsDebugRecorder>(
      name: 'signalsDebugRecorder',
      types: const [SignalsDebugRecorder, SignalProbe],
      source: _source,
      conditions: const [
        ConditionGroup('$_source#signalsDebugRecorder', [
          ConditionalOnMissingBean(SignalsDebugRecorder),
        ]),
      ],
      create: (r) {
        final debug = r.dependency<SignalsProperties>().debug;
        return SignalsDebugRecorder(
          readWindow: debug.readWindow,
          countReads: debug.reads,
          // Named only while a tool collects; what the widgets on the
          // screen read is heard when one starts.
          names: r.optionalDependency<SignalWidgetNames>(),
        );
      },
    );

// The names of the widgets that read state, in each module whose view
// shows them (the tab, the console's pane, the Graph tab, the console's
// `graph` pane), only when that view is in the running app ([viewer]):
// the first makes it. Without one no widget's tracking keeps anything.
BeanDefinition<SignalWidgetNames> _widgetNamesFor(Condition viewer) =>
    BeanDefinition<SignalWidgetNames>(
      name: 'signalWidgetNames',
      types: const [SignalWidgetNames],
      source: _source,
      conditions: [
        viewer,
        const ConditionGroup('$_source#signalWidgetNames', [
          ConditionalOnMissingBean(SignalWidgetNames),
        ]),
      ],
      postConstruct: (names) => names.install(),
      preDestroy: (names) => names.uninstall(),
      create: (_) => SignalWidgetNames(),
    );

// `Watch` and `AsyncView` are builders, not what a reader is named after
// (`DebugGraphWidgets.builders`), in each module whose view names widgets:
// the first registers them.
BeanDefinition<DebugGraphBuilders> _graphBuildersFor(Condition viewer) =>
    BeanDefinition<DebugGraphBuilders>(
      name: 'signalsGraphBuilders',
      types: const [DebugGraphBuilders],
      source: _source,
      conditions: [
        viewer,
        const ConditionGroup('$_source#signalsGraphBuilders', [
          ConditionalOnMissingBean(DebugGraphBuilders),
        ]),
      ],
      postConstruct: DebugGraphWidgets.addBuilders,
      preDestroy: DebugGraphWidgets.removeBuilders,
      create: (_) => const DebugGraphBuilders({'Watch', 'AsyncView'}),
    );

// The signals as a layer of the application graph, in each module whose
// view shows it (the Graph tab, the `graph` and `signals` panes): the
// first makes it.
final BeanDefinition<SignalsGraphLayer> _graphLayer =
    BeanDefinition<SignalsGraphLayer>(
      name: 'signalsGraphLayer',
      types: const [SignalsGraphLayer, DebugGraphLayer],
      source: _source,
      conditions: const [
        ConditionGroup('$_source#signalsGraphLayer', [
          ConditionalOnMissingBean(SignalsGraphLayer),
        ]),
      ],
      preDestroy: (layer) => layer.dispose(),
      create: (r) => SignalsGraphLayer(
        _beansOf(r),
        r.dependency<SignalsDebugRecorder>(),
        widgets: r.optionalDependency<WidgetsGraphLayer>(),
        routes: r.optionalDependency<DebugGraphRoutes>(),
      ),
    );

/// The Signals tab of the debug panel (`signalsDebugSection`): every bean
/// with followed state in columns, the dependencies as a graph or a list
/// (the widgets by name, `signalWidgetNames`), the times, counts, queues
/// and buffers; and the DEBUG log of signal
/// activity (`signalsDebugLog`, with
/// `spring.flutter.signals.debug.log.enabled: true`). The generator puts
/// this module into the app by `spring.flutter.signals.debug.enabled`:
/// `true` always, `false` never (no code), not set in debug builds only; and
/// only as far as the debug panel's switch
/// (`spring.flutter.debug.enabled`, its parent) lets it in, so a build
/// without the panel has none of its code.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.signals.debug.enabled',
    parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')],
  ),
)
final BeanModule springBootStarterFlutterSignalsDebugAutoConfiguration =
    BeanModule('springBootStarterFlutterSignalsDebugAutoConfiguration', [
      BeanDefinition<SignalsDebugSection>(
        name: 'signalsDebugSection',
        types: const [SignalsDebugSection, DebugPanelSection, Ordered],
        source: _source,
        conditions: const [_debugOn],
        create: (r) => SignalsDebugSection(
          _beansOf(r),
          recorder: r.optionalDependency<SignalsDebugRecorder>(),
          queues: r.dependency<SignalRuntime>().queues,
          graph: r.optionalDependency<SignalsGraphLayer>(),
        ),
      ),
      _recorder,
      _widgetNamesFor(const ConditionalOnBean(SignalsDebugSection)),
      _graphBuildersFor(const ConditionalOnBean(SignalsDebugSection)),
      BeanDefinition<SignalsDebugLog>(
        name: 'signalsDebugLog',
        types: const [SignalsDebugLog, SignalProbe],
        source: _source,
        conditions: const [
          _debugOn,
          ConditionalOnProperty(
            'spring.flutter.signals.debug.log.enabled',
            havingValue: 'true',
          ),
        ],
        postConstruct: (log) => log.start(),
        preDestroy: (log) => log.stop(),
        create: (r) => SignalsDebugLog(
          reads: r.dependency<SignalsProperties>().debug.log.reads,
        ),
      ),
    ]);

/// The debug console's `signals` segment (`signalsSegment`: ticks,
/// flushes and effect runs per frame, collected only while the console
/// shows). The generator puts this module into the app only with the
/// console (`spring.flutter.debug.console.enabled: true`, its parent) and
/// when `spring.flutter.debug.console.segments` names `signals` or holds
/// `*`: otherwise there is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'signals',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule springBootStarterFlutterSignalsDebugConsoleAutoConfiguration =
    BeanModule('springBootStarterFlutterSignalsDebugConsoleAutoConfiguration', [
      BeanDefinition<SignalsSegment>(
        name: 'signalsSegment',
        types: const [SignalsSegment, DebugConsoleSegment],
        source: _source,
        conditions: const [_consoleOn],
        annotations: const [ConsoleSegment('signals')],
        create: (r) => SignalsSegment(r.dependency<SignalsDebugRecorder>()),
      ),
      _recorder,
    ]);

/// The debug console's `signals` pane (`signalsPane`): the application
/// graph preset to the signals layer (`signalsGraphLayer`), compact,
/// collected only while the pane shows. The generator
/// puts this module into the app only with the console
/// (`spring.flutter.debug.console.enabled: true`, its parent) and when
/// `spring.flutter.debug.console.panes` names `signals` or holds `*`:
/// otherwise there is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'signals',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterSignalsDebugConsolePaneAutoConfiguration = BeanModule(
  'springBootStarterFlutterSignalsDebugConsolePaneAutoConfiguration',
  [
    BeanDefinition<SignalsPane>(
      name: 'signalsPane',
      types: const [SignalsPane, DebugConsolePane],
      source: _source,
      conditions: const [_consoleOn],
      order: 20,
      annotations: const [ConsolePane('signals', order: 20)],
      create: (r) => SignalsPane(r.dependency<SignalsGraphLayer>()),
    ),
    _graphLayer,
    _recorder,
    _widgetNamesFor(const ConditionalOnBean(SignalsPane)),
    _graphBuildersFor(const ConditionalOnBean(SignalsPane)),
  ],
);

/// The signals layer of the application graph (`signalsGraphLayer`) and
/// the debug panel's Graph tab with it (`debugGraphSection`): the fields,
/// computed values and effects of the beans, a lane each, and the widgets
/// that read them. With it the Signals tab has its Graph sub-tab. The
/// generator puts this module into the app when
/// `spring.flutter.debug.graph.layers` names `signals`, holds `*` or is not
/// set, and only as far as `spring.flutter.debug.graph.enabled`, the
/// Signals tab's switch and the panel's (its parents) let it in: otherwise
/// there is no code of the layer, and none of the graph's engine unless
/// another layer brings it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.graph.layers',
    'signals',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),
      AutoConfigurationBuild('spring.flutter.signals.debug.enabled'),
      AutoConfigurationBuild('spring.flutter.debug.enabled'),
    ],
  ),
)
final BeanModule springBootStarterFlutterSignalsDebugGraphAutoConfiguration =
    BeanModule('springBootStarterFlutterSignalsDebugGraphAutoConfiguration', [
      _graphLayer,
      _recorder,
      ...debugGraphSectionDefinitions,
      _widgetNamesFor(const ConditionalOnBean(DebugGraphSection)),
      _graphBuildersFor(const ConditionalOnBean(DebugGraphSection)),
    ]);

/// The debug console's `graph` pane (`debugGraphPane`) with the signals
/// layer in it. The generator puts this module into the app only with the
/// console (`spring.flutter.debug.console.enabled: true`), when
/// `spring.flutter.debug.console.panes` names `graph` or holds `*`, and
/// when `spring.flutter.debug.graph.layers` lets `signals` in (not set: it
/// does): otherwise there is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'graph',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild.named(
        'spring.flutter.debug.graph.layers',
        'signals',
        whenMissing: BuildInclusion.always,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterSignalsDebugGraphPaneAutoConfiguration = BeanModule(
  'springBootStarterFlutterSignalsDebugGraphPaneAutoConfiguration',
  [
    _graphLayer,
    _recorder,
    ...debugGraphPaneDefinitions,
    _widgetNamesFor(const ConditionalOnBean(DebugGraphPane)),
    _graphBuildersFor(const ConditionalOnBean(DebugGraphPane)),
  ],
);
