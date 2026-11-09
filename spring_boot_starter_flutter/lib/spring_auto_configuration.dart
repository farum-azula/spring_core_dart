/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:flutter/cupertino.dart' show CupertinoThemeData;
import 'package:flutter/material.dart' show ThemeData;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/asset_resource.dart';
import 'package:spring_boot_starter_flutter/src/bean_reads.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_host.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_motion.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/beans_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/configuration_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/frames_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/motion_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/logs_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/start_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/theme_section.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/files/platform_file_store.dart';
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';
import 'package:spring_boot_starter_flutter/src/properties/properties_beans.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts_customizer.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_dock.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay_drag.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/overlays_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/debug_timeline.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_observations.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_section.dart';
import 'package:spring_boot_starter_flutter/src/resource_prefetch.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_trace.dart';
import 'package:spring_boot_starter_flutter/src/splash/startup_events.dart';
import 'package:spring_boot_starter_flutter/src/splash/text_warm_up.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_choice_store.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_source.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    show LogBuffer;
import 'package:spring_web_dart/spring_web_dart.dart' show HttpTransport;

// The auto-configurations this starter builds on (logging, and through it spring_boot_dart's), so a test of an application that lists only this starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

// The theme the user chose, kept between runs unless turned off.
const _rememberTheme = ConditionalOnProperty(
  'spring.flutter.theme.remember',
  havingValue: 'true',
  matchIfMissing: true,
);

// The text warm-up: only when turned on.
const _textWarmUp = ConditionalOnProperty(
  'spring.flutter.splash.warm-up.text.enabled',
  havingValue: 'true',
);

/// The beans the starter adds to every Flutter application:
///
/// - support for `asset:` locations, so `@Value('asset:...')` injects
///   Flutter assets as resources;
/// - the advice that calls `notifyListeners()` for `@NotifyListeners` and
///   `@ChangeNotifierComponent` beans, and the one that tells Spring
///   widgets which of those beans their `build` read;
/// - the app's themes from `spring.flutter.theme.*` (`SpringThemes`) and
///   the choice of the theme shown (`ThemeSelection`), and the loader of
///   the themes that come from a URL (`themes.<name>.source`);
/// - the app's files: a `FileStore` (`platformFileStore`: the device's
///   directories, IndexedDB in a browser) and the `FileTemplate` on it
///   (`fileTemplate`), each only when the app declares none;
/// - the keyboard shortcuts of `spring.flutter.shortcuts.*` and the
///   `@Shortcut` methods (`keyboardShortcuts`), around the app's navigator
///   (`keyboardShortcutsCustomizer`);
/// - the theme the user chooses, kept between runs (`fileThemeChoiceStore`,
///   unless the app declares a `ThemeChoiceStore`) and shown again while
///   the splash shows (`themeChoiceRestore`), unless
///   `spring.flutter.theme.remember` is `false`;
/// - with `spring.flutter.splash.warm-up.text.enabled`, the fonts of the
///   app's text downloaded while the splash shows (`textWarmUp`, a `SplashTask`, of the text of
///   `spring.flutter.splash.warm-up.text.resources` and the
///   `TextWarmUpSource` beans).
///
/// Logins and secrets (the platform's secure storage, the login window)
/// are `spring_boot_starter_flutter_security`'s.
@AutoConfigurationModule()
final BeanModule springBootStarterFlutterAutoConfiguration = BeanModule(
  'springBootStarterFlutterAutoConfiguration',
  [
    BeanDefinition<AssetProtocolResolverRegistrar>(
      name: 'assetProtocolResolverRegistrar',
      types: const [
        AssetProtocolResolverRegistrar,
        BeanFactoryPostProcessor,
        ApplicationContextAware,
      ],
      source: _source,
      create: (_) => AssetProtocolResolverRegistrar(),
    ),
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'notifyListenersAdvisor',
      types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
      source: _source,
      create: (_) => DefaultPointcutAdvisor(
        const NotifyListenersPointcut(),
        const NotifyListenersInterceptor(),
      ),
    ),
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'beanReadsAdvisor',
      types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
      source: _source,
      create: (_) => DefaultPointcutAdvisor(
        const BeanReadsPointcut(),
        const BeanReadsInterceptor(),
      ),
    ),
    BeanDefinition<KeyboardShortcuts>(
      name: 'keyboardShortcuts',
      types: const [
        KeyboardShortcuts,
        BeanPostProcessor,
        BeanFactoryAware,
        SmartInitializingSingleton,
      ],
      source: _source,
      create: (r) => KeyboardShortcuts(r.dependency<ConfigurableEnvironment>()),
    ),
    BeanDefinition<KeyboardShortcutsCustomizer>(
      name: 'keyboardShortcutsCustomizer',
      types: const [KeyboardShortcutsCustomizer, FlutterAppCustomizer],
      source: _source,
      create: (r) => KeyboardShortcutsCustomizer(
        r.dependency<KeyboardShortcuts>(),
      ),
    ),
    BeanDefinition<StartupEvents>(
      name: 'startupEvents',
      types: const [StartupEvents, GenericApplicationListener],
      source: _source,
      create: (r) => StartupEvents(r.optionalDependency<SplashTrace>()),
    ),
    BeanDefinition<ResourcePrefetch>(
      name: 'resourcePrefetch',
      types: const [
        ResourcePrefetch,
        SplashTask,
        GenericApplicationListener,
      ],
      source: _source,
      preDestroy: (bean) => bean.stop(),
      create: (r) =>
          ResourcePrefetch.of(r.dependency<ConfigurableEnvironment>()),
    ),
    BeanDefinition<ResourceTextWarmUpSource>(
      name: 'resourceTextWarmUpSource',
      types: const [ResourceTextWarmUpSource, TextWarmUpSource],
      source: _source,
      conditions: const [_textWarmUp],
      create: (r) => ResourceTextWarmUpSource(
        r.dependency<ApplicationContext>(),
        r.dependency<ConfigurableEnvironment>().getPropertyAs<List<String>>(
              'spring.flutter.splash.warm-up.text.resources',
            ) ??
            const ['resources:messages*.properties'],
      ),
    ),
    BeanDefinition<TextWarmUp>(
      name: 'textWarmUp',
      types: const [TextWarmUp, SplashTask],
      source: _source,
      conditions: const [_textWarmUp],
      create: (r) {
        final environment = r.dependency<ConfigurableEnvironment>();
        final themes = r.dependency<SpringThemes>();
        return TextWarmUp(
          r.optionalDependencyList<TextWarmUpSource>() ?? const [],
          fontFamilies: {
            for (final name in themes.names) ...themes.data(name).fontFamilies,
          },
          fontFamilyFallback: {
            for (final name in themes.names)
              ...?themes.data(name).fontFamilyFallback,
          }.toList(),
          firstFont:
              environment.getPropertyAs<Duration>(
                'spring.flutter.splash.warm-up.text.first-font',
              ) ??
              const Duration(milliseconds: 400),
          settle:
              environment.getPropertyAs<Duration>(
                'spring.flutter.splash.warm-up.text.settle',
              ) ??
              const Duration(milliseconds: 250),
          chunk:
              environment.getPropertyAs<int>(
                'spring.flutter.splash.warm-up.text.chunk',
              ) ??
              200,
        );
      },
    ),
    BeanDefinition<SpringThemes>(
      name: 'springThemes',
      types: const [SpringThemes, ChangeNotifier, Listenable],
      source: _source,
      create: (r) => SpringThemes.fromEnvironment(
        r.dependency<ConfigurableEnvironment>(),
        customizers: r.optionalDependencyList<ThemeCustomizer>() ?? const [],
        cupertinoCustomizers:
            r.optionalDependencyList<CupertinoThemeCustomizer>() ?? const [],
        light: r.optionalDependency<ThemeData>(qualifier: 'theme'),
        dark: r.optionalDependency<ThemeData>(qualifier: 'darkTheme'),
        cupertino: r.optionalDependency<CupertinoThemeData>(),
        addresses:
            r.optionalDependency<RemoteAddresses>() ?? const RemoteAddresses(),
      ),
    ),
    BeanDefinition<ThemeSelection>(
      name: 'themeSelection',
      types: const [ThemeSelection, ChangeNotifier, Listenable],
      source: _source,
      create: (r) => ThemeSelection(
        r.dependency<SpringThemes>(),
        store: r.optionalDependency<ThemeChoiceStore>(),
      ),
    ),
    BeanDefinition<ThemeChoiceStore>(
      name: 'fileThemeChoiceStore',
      types: const [ThemeChoiceStore, FileThemeChoiceStore],
      source: _source,
      conditions: const [
        _rememberTheme,
        ConditionGroup('$_source.fileThemeChoiceStore', [
          ConditionalOnMissingBean(ThemeChoiceStore),
        ]),
      ],
      create: (r) => FileThemeChoiceStore(r.dependency<FileTemplate>()),
    ),
    BeanDefinition<ThemeChoiceRestore>(
      name: 'themeChoiceRestore',
      types: const [ThemeChoiceRestore, SplashTask],
      source: _source,
      conditions: const [_rememberTheme],
      create: (r) => ThemeChoiceRestore(
        r.dependency<ThemeSelection>(),
        r.dependency<ThemeChoiceStore>(),
      ),
    ),
    BeanDefinition<FileStore>(
      name: 'platformFileStore',
      types: const [FileStore],
      source: _source,
      conditions: const [
        ConditionGroup('$_source.platformFileStore', [
          ConditionalOnMissingBean(FileStore),
        ]),
      ],
      create: (_) => createPlatformFileStore(),
    ),
    BeanDefinition<FileTemplate>(
      name: 'fileTemplate',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.fileTemplate', [
          ConditionalOnMissingBean(FileTemplate),
        ]),
      ],
      create: (r) => FileTemplate(
        r.dependency<FileStore>(),
        objectMapper: r.optionalDependency<ObjectMapper>(),
      ),
      preDestroy: (files) => files.close(),
    ),
    BeanDefinition<ThemeSourceLoader>(
      name: 'themeSourceLoader',
      types: const [ThemeSourceLoader, ApplicationRunner],
      source: _source,
      create: (r) => ThemeSourceLoader.fromEnvironment(
        r.dependency<ConfigurableEnvironment>(),
        themes: r.dependency<SpringThemes>(),
        files: r.dependency<FileTemplate>(),
        transport: r.optionalDependency<HttpTransport>(),
      ),
      preDestroy: (loader) => loader.dispose(),
    ),
    BeanDefinition<ThemeImageLoader>(
      name: 'themeImageLoader',
      types: const [ThemeImageLoader, ApplicationRunner],
      source: _source,
      create: (r) => ThemeImageLoader(
        themes: r.dependency<SpringThemes>(),
        files: r.dependency<FileTemplate>(),
        transport: r.optionalDependency<HttpTransport>(),
        allowInsecure: RemoteAddressPolicy.of(
          r.dependency<ConfigurableEnvironment>(),
        ).allowInsecure,
      ),
      preDestroy: (loader) => loader.dispose(),
    ),
  ],
  imports: [flutterConfigBeans],
);

const _debugSource =
    'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

// The panel in a running app: off with spring.flutter.debug.enabled=false
// in a profile, though the build has it.
const _debugOn = ConditionalOnProperty(
  'spring.flutter.debug.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

/// The debug panel (`debugPanel`) and its sections: logs, frames, the
/// configuration, the beans, the themes and the start, over the app
/// (`debugPanelCustomizer`). The generator puts this module into the app
/// by `spring.flutter.debug.enabled`: `true` always, `false` never (no
/// code), not set in debug and profile builds only.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.debug.enabled'),
)
final BeanModule springBootStarterFlutterDebugAutoConfiguration = BeanModule(
  'springBootStarterFlutterDebugAutoConfiguration',
  [
    BeanDefinition<DebugPanel>(
      name: 'debugPanel',
      types: const [
        DebugPanel,
        ChangeNotifier,
        Listenable,
        ShortcutHandler,
        KeyedShortcutHandler,
      ],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (_) => DebugPanel(),
    ),
    BeanDefinition<DebugLogsSection>(
      name: 'debugLogsSection',
      types: const [DebugLogsSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugLogsSection(r.optionalDependency<LogBuffer>()),
    ),
    BeanDefinition<DebugFramesSection>(
      name: 'debugFramesSection',
      types: const [DebugFramesSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) =>
          DebugFramesSection(r.optionalDependency<DebugFrameMeter>()),
    ),
    BeanDefinition<DebugOverlaysSection>(
      name: 'debugOverlaysSection',
      types: const [DebugOverlaysSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugOverlaysSection(
        r.optionalDependencyList<DebugOverlay>() ?? const [],
        placement: r.optionalDependency<DebugOverlayPlacement>(),
      ),
    ),
    BeanDefinition<DebugMotionSection>(
      name: 'debugMotionSection',
      types: const [DebugMotionSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugMotionSection(r.optionalDependency<DebugMotion>()),
    ),
    BeanDefinition<DebugConfigurationSection>(
      name: 'debugConfigurationSection',
      types: const [DebugConfigurationSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugConfigurationSection(
        r.dependency<ConfigurableEnvironment>(),
      ),
    ),
    BeanDefinition<DebugBeansSection>(
      name: 'debugBeansSection',
      types: const [DebugBeansSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugBeansSection(r.dependency<ApplicationContext>()),
    ),
    BeanDefinition<DebugThemeSection>(
      name: 'debugThemeSection',
      types: const [DebugThemeSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugThemeSection(
        r.dependency<SpringThemes>(),
        r.dependency<ThemeSelection>(),
      ),
    ),
    BeanDefinition<DebugStartSection>(
      name: 'debugStartSection',
      types: const [DebugStartSection, DebugPanelSection, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugStartSection(r.optionalDependency<SplashStages>()),
    ),
    BeanDefinition<DebugPanelCustomizer>(
      name: 'debugPanelCustomizer',
      types: const [DebugPanelCustomizer, FlutterAppCustomizer],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugPanelCustomizer(
        r.dependency<DebugPanel>(),
        r.optionalDependencyList<DebugPanelSection>() ?? const [],
      ),
    ),
  ],
);

// A debug feature in a running app: off with its enabled=false in a
// profile, though the build has it.
ConditionalOnProperty _debugFeatureOn(String feature) => ConditionalOnProperty(
  'spring.flutter.debug.$feature.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

/// The frame meter over the app, on and off by the action
/// `debug.frame-meter` (⌘⇧X, or five quick taps and a sixth held two
/// seconds) or the debug panel's Frames tab (`debugFrameMeter`). The
/// generator puts this module into the app by
/// `spring.flutter.debug.frame-meter.enabled`: `true` always, `false`
/// never (no code), not set debug and profile builds only; apart from the
/// panel, so a release can have the meter alone.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.debug.frame-meter.enabled'),
)
final BeanModule springBootStarterFlutterDebugFrameMeterAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugFrameMeterAutoConfiguration', [
      BeanDefinition<DebugFrameMeter>(
        name: 'debugFrameMeter',
        types: const [
          DebugFrameMeter,
          ChangeNotifier,
          Listenable,
          ShortcutHandler,
          KeyedShortcutHandler,
          DebugOverlay,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('frame-meter')],
        create: (r) => DebugFrameMeter(
          position: r.dependency<FlutterFrameMeterProperties>().position,
        ),
      ),
      ..._debugDock,
    ]);

/// The dock of the debug overlays, in every module of a feature that has
/// one (the frame meter, the timeline): the first makes it, so it is in the
/// build only with such a feature.
final List<BeanDefinition<Object>> _debugDock = [
  BeanDefinition<DebugDockCustomizer>(
    name: 'debugDock',
    types: const [DebugDockCustomizer, FlutterAppCustomizer, Ordered],
    source: _debugSource,
    conditions: const [
      ConditionGroup('$_debugSource#debugDock', [
        ConditionalOnMissingBean(DebugDockCustomizer),
      ]),
    ],
    create: (r) {
      final overlays = r.dependency<FlutterDebugProperties>().overlays;
      final panel = r.optionalDependency<DebugPanel>();
      return DebugDockCustomizer(
        r.optionalDependencyList<DebugOverlay>() ?? const [],
        settings: DebugDockSettings(
          layout: overlays.layout,
          maxHeight: overlays.maxHeight,
          margin: EdgeInsets.fromLTRB(
            overlays.margin.left,
            overlays.margin.top,
            overlays.margin.right,
            overlays.margin.bottom,
          ),
        ),
        placement: r.optionalDependency<DebugOverlayPlacement>(),
        hiddenWhile: panel == null ? null : DebugPanelOpen(panel),
      );
    },
  ),
];

/// Every animation of the app on or off by the action `debug.motion`
/// (⌘⇧M) or the debug panel's Motion tab (`debugMotion`). The generator
/// puts this module into the app by `spring.flutter.debug.motion.enabled`:
/// `true` always, `false` never (no code), not set debug and profile
/// builds only.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.debug.motion.enabled'),
)
final BeanModule springBootStarterFlutterDebugMotionAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugMotionAutoConfiguration', [
      BeanDefinition<DebugMotion>(
        name: 'debugMotion',
        types: const [
          DebugMotion,
          ChangeNotifier,
          Listenable,
          ShortcutHandler,
          KeyedShortcutHandler,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('motion')],
        create: (_) => DebugMotion(),
      ),
      BeanDefinition<DebugMotionCustomizer>(
        name: 'debugMotionCustomizer',
        types: const [DebugMotionCustomizer, FlutterAppCustomizer],
        source: _debugSource,
        conditions: [_debugFeatureOn('motion')],
        create: (r) => DebugMotionCustomizer(r.dependency<DebugMotion>()),
      ),
    ]);

/// Dragging the debug overlays (`debugOverlayDrag`): a mouse drags one at
/// once, a finger after a long press; dropped, it joins the nearest corner
/// or stays where it is (`spring.flutter.debug.overlays.drag.snap`), kept
/// for the next start with `remember`. The generator puts this module into
/// the app only with `spring.flutter.debug.drag.enabled: true`: without it
/// there is no code to drag.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.drag.enabled',
    whenMissing: BuildInclusion.never,
  ),
)
final BeanModule springBootStarterFlutterDebugDragAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugDragAutoConfiguration', [
      BeanDefinition<DebugOverlayDrag>(
        name: 'debugOverlayDrag',
        types: const [
          DebugOverlayDrag,
          DebugOverlayPlacement,
          ChangeNotifier,
          Listenable,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('drag')],
        create: (r) {
          final drag = r.dependency<FlutterDebugProperties>().overlays.drag;
          return DebugOverlayDrag(
            snap: drag.snap,
            places: drag.remember
                ? FileDebugOverlayPlaces(r.dependency<FileTemplate>())
                : null,
          );
        },
      ),
    ]);

/// The timeline of the start and the observations (`debugTimeline`), on
/// and off by the action `debug.timeline` (⌘⇧L, or six quick taps and a
/// seventh held): a pill in the dock, the full view over the app when it is
/// tapped, and its tab in the debug panel. The `timelineObservations` bean
/// is an `ObservationHandler`, so it gets every observation. The generator
/// puts this module into the app by `spring.flutter.debug.timeline.enabled`:
/// `true` always, `false` never (no code), not set debug and profile builds
/// only. With it, each bean's creation is measured too.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.debug.timeline.enabled'),
)
final BeanModule springBootStarterFlutterDebugTimelineAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugTimelineAutoConfiguration', [
      BeanDefinition<TimelineObservations>(
        name: 'timelineObservations',
        types: const [
          TimelineObservations,
          ObservationHandler,
          ChangeNotifier,
          Listenable,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('timeline')],
        create: (_) => TimelineObservations(),
      ),
      BeanDefinition<DebugTimeline>(
        name: 'debugTimeline',
        types: const [
          DebugTimeline,
          ChangeNotifier,
          Listenable,
          ShortcutHandler,
          KeyedShortcutHandler,
          DebugOverlay,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('timeline')],
        create: (r) => DebugTimeline(
          // The SpringApplicationWidget's; an app without it has no stages.
          trace:
              r.optionalDependency<SplashTrace>() ??
              SplashTrace(SplashStages(), log: false),
          observations: r.dependency<TimelineObservations>(),
          position: r.dependency<FlutterDebugProperties>().timeline.position,
        ),
      ),
      BeanDefinition<DebugTimelineCustomizer>(
        name: 'debugTimelineCustomizer',
        types: const [
          DebugTimelineCustomizer,
          FlutterAppCustomizer,
          Ordered,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('timeline')],
        create: (r) => DebugTimelineCustomizer(r.dependency<DebugTimeline>()),
      ),
      BeanDefinition<DebugTimelineSection>(
        name: 'debugTimelineSection',
        types: const [DebugTimelineSection, DebugPanelSection, Ordered],
        source: _debugSource,
        conditions: [_debugFeatureOn('timeline')],
        create: (r) => DebugTimelineSection(r.dependency<DebugTimeline>()),
      ),
      ..._debugDock,
    ]);
