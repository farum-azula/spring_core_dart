/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_signals`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signals_advice.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugPanelSection, WidgetBuildTracker;
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_section.dart';
import 'package:spring_boot_starter_flutter_signals/src/properties/properties_beans.dart';
import 'package:spring_boot_starter_flutter_signals/src/signals_processors.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';

// The auto-configurations this starter builds on (the Flutter starter's,
// and through it logging and spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

/// The order of the advice that follows state: one step before the
/// default (`Ordered.lowestPrecedence`), so it is outside every advice
/// that has no order of its own.
const int signalsAdvisorOrder = Ordered.lowestPrecedence - 1;

const _source =
    'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';

// One for the application: the state of its beans, and the names of
// those that have any.
SignalBeans _beansOf(DependencyResolver r) => r.dependency<SignalBeans>();

/// The beans the starter adds to a Flutter application:
///
/// - `signalBeans`: the followed state of every bean with a `@Signal`,
///   `@Computed` or `@Effect` member;
/// - `signalBeanNames`: finds those beans before any is made;
/// - `signalsAdvisor`: the advice on them (a read is followed, an
///   assignment tells its readers, a method is one batch);
/// - `signalEffects`: starts their `@Effect` methods when they are made
///   and ends their state when they are destroyed;
/// - `signalBuildTracker`: builds a Spring widget again when followed
///   state its `build` read has changed.
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
    BeanDefinition<SignalBeanNames>(
      name: 'signalBeanNames',
      types: const [SignalBeanNames, BeanFactoryPostProcessor],
      source: _source,
      create: (r) => SignalBeanNames(_beansOf(r)),
    ),
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'signalsAdvisor',
      types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
      source: _source,
      // Outside the advice of the default order (a transaction, a cache,
      // an aspect without @Order): on a computed value that advice then
      // runs when the value is computed, not for every read of the kept
      // one, and a method's readers are told after it. Advice with an
      // order of its own is outside this one.
      create: (r) => DefaultPointcutAdvisor(
        SignalsPointcut(_beansOf(r)),
        SignalsInterceptor(_beansOf(r)),
        order: signalsAdvisorOrder,
      ),
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
      create: (r) => SignalEffects(_beansOf(r)),
    ),
    BeanDefinition<SignalBuildTracker>(
      name: 'signalBuildTracker',
      types: const [SignalBuildTracker, WidgetBuildTracker],
      source: _source,
      create: (_) => const SignalBuildTracker(),
    ),
  ],
  imports: [signalsConfigBeans],
);

// The state's tab in a running app.
const _debugOn = ConditionalOnProperty(
  'spring.flutter.signals.debug.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

/// The state's tab of the debug panel (`signalsDebugSection`): every bean
/// with followed state and its members by name. The generator puts this
/// module into the app by `spring.flutter.signals.debug.enabled`: `true`
/// always, `false` never (no code), not set in debug and profile builds
/// only. The tab shows where the debug panel is in the build
/// (`spring.flutter.debug.enabled`).
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.signals.debug.enabled'),
)
final BeanModule springBootStarterFlutterSignalsDebugAutoConfiguration =
    BeanModule('springBootStarterFlutterSignalsDebugAutoConfiguration', [
      BeanDefinition<SignalsDebugSection>(
        name: 'signalsDebugSection',
        types: const [SignalsDebugSection, DebugPanelSection, Ordered],
        source: _source,
        conditions: const [_debugOn],
        create: (r) => SignalsDebugSection(_beansOf(r)),
      ),
    ]);
