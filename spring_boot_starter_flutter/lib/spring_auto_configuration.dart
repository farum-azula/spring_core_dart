/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/asset_resource.dart';
import 'package:spring_boot_starter_flutter/src/bean_reads.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/debug_flutter_tools.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/debug_flutter_tools_customizer.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/flutter_tools_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_host.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/debug_isolates.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_recorder.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_masking.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/web_socket_frame_labeler.dart';
import 'package:spring_boot_starter_flutter/src/isolates/flutter_engine_loads.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_motion.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_file_export.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_export.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_filter.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_format.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_text.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_logs_action.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/console_annotations.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_routes.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_fit_action.dart';
import 'package:spring_boot_starter_flutter/src/debug/graph/debug_graph_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/debug_widget_fields.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/widget_properties.dart';
import 'package:spring_boot_starter_flutter/src/debug/widgets_graph/widgets_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_command.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_commands.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_export_command.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_logs_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_commands_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_names.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segments.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_stats.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/beans_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/configuration_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/frames_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/motion_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/logs_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/start_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/theme_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/configured_debug_theme.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_theme.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_themes.dart';
import 'package:spring_boot_starter_flutter/src/files/file_cache_store.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/files/platform_file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/remote_cache.dart';
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';
import 'package:spring_boot_starter_flutter/src/properties/properties_beans.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueListenable, defaultTargetPlatform;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts_customizer.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_dock.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay_drag.dart';
import 'package:spring_boot_starter_flutter/src/debug/sections/overlays_section.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/beans_graph_layer.dart';
import 'package:spring_boot_starter_flutter/src/debug/beans_graph/debug_bean_graph.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/debug_timeline.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_observations.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_section.dart';
import 'package:spring_boot_starter_flutter/src/resource_prefetch.dart';
import 'package:spring_boot_starter_flutter/src/resources/resource_cache.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_trace.dart';
import 'package:spring_boot_starter_flutter/src/splash/startup_events.dart';
import 'package:spring_boot_starter_flutter/src/splash/text_warm_up.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_design.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_choice_store.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_source.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    show LogBuffer, LoggingSystem;
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
        order: AdvisorOrder.notifyListeners,
      ),
    ),
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'beanReadsAdvisor',
      types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
      source: _source,
      create: (_) => DefaultPointcutAdvisor(
        const BeanReadsPointcut(),
        const BeanReadsInterceptor(),
        order: AdvisorOrder.beanReads,
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
        addresses:
            r.optionalDependency<RemoteAddresses>() ?? const RemoteAddresses(),
        // The design libraries of the application's starters.
        designs: ThemeDesigns.of(
          r.optionalDependency<SpringFactories>() ?? const SpringFactories(),
          r.dependency<ConfigurableEnvironment>(),
        ),
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
    BeanDefinition<CacheStore>(
      name: 'fileCacheStore',
      types: const [CacheStore],
      source: _source,
      conditions: const [
        ConditionGroup('$_source.fileCacheStore', [
          ConditionalOnMissingBean(CacheStore),
        ]),
      ],
      create: (r) => FileCacheStore(r.dependency<FileStore>()),
    ),
    BeanDefinition<ResourceCache>(
      name: 'resourceCache',
      source: _source,
      preDestroy: (cache) => cache.close(),
      create: (r) {
        final properties = r.dependency<FlutterResourcesCacheProperties>();
        return ResourceCache(
          store: r.dependency<CacheStore>(),
          properties: properties,
          fetcher: RemoteFetcher(
            transport: r.optionalDependency<HttpTransport>(),
            timeout: const Duration(seconds: 30),
            maxBytes: properties.maxEntrySize?.toBytes() ?? 50 * 1024 * 1024,
            allowInsecure: RemoteAddressPolicy.of(
              r.dependency<ConfigurableEnvironment>(),
            ).allowInsecure,
          ),
        );
      },
    ),
    BeanDefinition<CachedResourceRegistrar>(
      name: 'cachedResourceRegistrar',
      types: const [
        CachedResourceRegistrar,
        BeanFactoryPostProcessor,
        ApplicationContextAware,
      ],
      source: _source,
      create: (_) => CachedResourceRegistrar(),
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
/// code), not set in debug builds only.
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
      create: (r) => DebugLogsSection(
        r.optionalDependency<LogBuffer>(),
        r.dependency<DebugLogFilter>(),
        logging: r.optionalDependency<LoggingSystem>(),
        actions: r.optionalDependencyList<DebugLogsActions>() ?? const [],
      ),
    ),
    ..._debugLogFilter,
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
        debugThemes: r.optionalDependency<DebugThemes>(),
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
      types: const [DebugPanelCustomizer, FlutterAppCustomizer, Ordered],
      source: _debugSource,
      conditions: const [_debugOn],
      create: (r) => DebugPanelCustomizer(
        r.dependency<DebugPanel>(),
        r.optionalDependencyList<DebugPanelSection>() ?? const [],
      ),
    ),
    ..._debugThemes(const ConditionalOnBean(DebugPanel)),
  ],
);

/// The debug themes (`debugThemes`, `defaultDebugTheme`,
/// `debugThemeCustomizer`), in the debug panel's module and the
/// console's: the first makes them, so they are in the build only with
/// the panel or the console, and no code of them is without both. The
/// themes are the `DebugTheme` beans, those declared under
/// `spring.flutter.debug.themes` and the built-in `default`;
/// `spring.flutter.debug.theme` selects one. Each module passes its
/// [viewer], so a panel or a console turned off in a running app has no
/// themes either.
List<BeanDefinition<Object>> _debugThemes(Condition viewer) => [
  BeanDefinition<DefaultDebugTheme>(
    name: 'defaultDebugTheme',
    types: const [DefaultDebugTheme, DebugTheme, Ordered],
    source: _debugSource,
    conditions: [
      viewer,
      const ConditionGroup('$_debugSource#defaultDebugTheme', [
        ConditionalOnMissingBean(DefaultDebugTheme),
      ]),
    ],
    create: (_) => const DefaultDebugTheme(),
  ),
  BeanDefinition<DebugThemes>(
    name: 'debugThemes',
    types: const [
      DebugThemes,
      ValueListenable<DebugTheme>,
      ChangeNotifier,
      Listenable,
    ],
    source: _debugSource,
    conditions: [
      viewer,
      const ConditionGroup('$_debugSource#debugThemes', [
        ConditionalOnMissingBean(DebugThemes),
      ]),
    ],
    create: (r) {
      final debug = r.dependency<FlutterDebugProperties>();
      return DebugThemes([
        ...ConfiguredDebugTheme.declaredIn(
          r.dependency<ConfigurableEnvironment>(),
          debug.themes,
        ),
        ...?r.optionalDependencyList<DebugTheme>(),
      ], selected: debug.theme);
    },
  ),
  BeanDefinition<DebugThemeCustomizer>(
    name: 'debugThemeCustomizer',
    types: const [DebugThemeCustomizer, FlutterAppCustomizer, Ordered],
    source: _debugSource,
    conditions: [
      viewer,
      const ConditionGroup('$_debugSource#debugThemeCustomizer', [
        ConditionalOnMissingBean(DebugThemeCustomizer),
      ]),
    ],
    create: (r) => DebugThemeCustomizer(r.dependency<DebugThemes>()),
  ),
];

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
/// never (no code), not set debug builds only; apart from the
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
/// one (the frame meter, the console): the first makes
/// it, so it is in the build only with such a feature.
final List<BeanDefinition<Object>> _debugDock = [
  BeanDefinition<DebugDockCustomizer>(
    name: 'debugDock',
    types: const [DebugDockCustomizer, FlutterAppCustomizer, Ordered],
    source: _debugSource,
    conditions: const [
      ConditionalOnBean(DebugOverlay),
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

/// The filter of the logs (`debugLogFilter`), in the debug panel's module
/// and the console's: the first makes it, so the Logs tab and the console
/// show by one filter, which starts as
/// `spring.flutter.debug.console.filter.*` says.
final List<BeanDefinition<Object>> _debugLogFilter = [
  BeanDefinition<DebugLogFilter>(
    name: 'debugLogFilter',
    types: const [DebugLogFilter, ChangeNotifier, Listenable],
    source: _debugSource,
    conditions: const [
      ConditionGroup('$_debugSource#debugLogFilter', [
        ConditionalOnMissingBean(DebugLogFilter),
      ]),
    ],
    create: (r) {
      final filter = r.dependency<FlutterDebugProperties>().console.filter;
      return DebugLogFilter(level: filter.level, text: filter.text);
    },
  ),
];

/// The debug console over the app (`debugConsole`), on and off by the
/// action `debug.console` (⌘⇧O, or eight quick taps and a ninth held two
/// seconds) or the debug panel's Overlays tab (its segments and panes
/// switched in the Console tab): a header of segments
/// (every `DebugConsoleSegment` bean the build has, by the name of its
/// `@ConsoleSegment`, those of `spring.flutter.debug.console.header`
/// shown), and under it the panes of `shown-panes` (every
/// `DebugConsolePane` bean the build has, by the name of its
/// `@ConsolePane`; not set: `logs` when the build has it); with none shown,
/// the header alone. A name in `header` or `shown-panes` that `segments`
/// or `panes` does not have fails the start.
/// The generator puts this module into the app only with
/// `spring.flutter.debug.console.enabled: true`: not set or `false`, there
/// is no code of it, nor of its segments and panes, nor of the
/// application's `@ConsoleSegment`, `@ConsolePane` and `@ConsoleCommand`
/// classes. Each segment and pane is a module of its own, in the build
/// only when `spring.flutter.debug.console.segments` (`panes`) names it or
/// holds `*`.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.console.enabled',
    whenMissing: BuildInclusion.never,
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugConsoleAutoConfiguration', [
      BeanDefinition<DebugConsole>(
        name: 'debugConsole',
        types: const [
          DebugConsole,
          ChangeNotifier,
          Listenable,
          ShortcutHandler,
          KeyedShortcutHandler,
          DebugOverlay,
        ],
        source: _debugSource,
        conditions: [_debugFeatureOn('console')],
        create: (r) {
          final console = r.dependency<FlutterDebugProperties>().console;
          final segments = pickDebugConsoleNamed(
            consoleSegmentsByName(r),
            console.segments,
          );
          final header = console.header ?? console.segments;
          checkDebugConsoleNames(
            shownKey: 'spring.flutter.debug.console.header',
            shown: header,
            builtKey: 'spring.flutter.debug.console.segments',
            built: console.segments,
            available: segments.keys,
          );
          final panes = keepDebugConsoleNamed(
            consolePanesByName(r),
            console.panes,
          );
          final shownPanes = console.shownPanes;
          if (shownPanes != null) {
            checkDebugConsoleNames(
              shownKey: 'spring.flutter.debug.console.shown-panes',
              shown: shownPanes,
              builtKey: 'spring.flutter.debug.console.panes',
              built: console.panes,
              available: panes.keys,
            );
          }
          return DebugConsole(
            segments: segments,
            header: header,
            panes: panes,
            shownPanes: shownPanes ?? const ['logs'],
            position: console.position,
            opacity: console.opacity,
            interaction: console.interaction,
            passThroughOpacity: console.passThroughOpacity,
            width: console.width,
            slideDuration: console.slideDuration,
          );
        },
      ),
      ..._debugDock,
      ..._debugThemes(const ConditionalOnBean(DebugConsole)),
    ]);

/// The frames the `fps` and `frames-lost` segments read
/// (`debugConsoleFrames`), measured only while the console shows: in each
/// of their modules, the first makes it, so it is in the build only with
/// one of them.
final List<BeanDefinition<Object>> _debugConsoleFrames = [
  BeanDefinition<FrameStats>(
    name: 'debugConsoleFrames',
    types: const [FrameStats, ChangeNotifier, Listenable],
    source: _debugSource,
    conditions: [
      _debugFeatureOn('console'),
      const ConditionGroup('$_debugSource#debugConsoleFrames', [
        ConditionalOnMissingBean(FrameStats),
      ]),
    ],
    preDestroy: (frames) => frames.dispose(),
    create: (r) => FrameStats(
      targetRate: r.dependency<FlutterFrameMeterProperties>().targetRate,
    ),
  ),
];

/// The console's `fps` segment (`fpsSegment`): the frames a second Flutter
/// draws. In the build with the console when
/// `spring.flutter.debug.console.segments` names it or holds `*`, or is
/// not set (its default names it).
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'fps',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleFpsAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugConsoleFpsAutoConfiguration', [
      BeanDefinition<FpsSegment>(
        name: 'fpsSegment',
        types: const [FpsSegment, DebugConsoleSegment],
        source: _debugSource,
        conditions: [_debugFeatureOn('console')],
        annotations: const [ConsoleSegment('fps')],
        create: (r) => FpsSegment(r.dependency<FrameStats>()),
      ),
      ..._debugConsoleFrames,
    ]);

/// The console's `frames-lost` segment (`framesLostSegment`): the frames
/// of the last second over the budget. In the build with the console when
/// `spring.flutter.debug.console.segments` names it or holds `*`, or is
/// not set (its default names it).
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'frames-lost',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleFramesLostAutoConfiguration = BeanModule(
  'springBootStarterFlutterDebugConsoleFramesLostAutoConfiguration',
  [
    BeanDefinition<FramesLostSegment>(
      name: 'framesLostSegment',
      types: const [FramesLostSegment, DebugConsoleSegment],
      source: _debugSource,
      conditions: [_debugFeatureOn('console')],
      annotations: const [ConsoleSegment('frames-lost')],
      create: (r) => FramesLostSegment(r.dependency<FrameStats>()),
    ),
    ..._debugConsoleFrames,
  ],
);

/// The console's `filter` segment (`filterSegment`): the filter the
/// records show by. In the build with the console when
/// `spring.flutter.debug.console.segments` names it or holds `*`, or is
/// not set (its default names it).
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'filter',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleFilterAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugConsoleFilterAutoConfiguration', [
      BeanDefinition<FilterSegment>(
        name: 'filterSegment',
        types: const [FilterSegment, DebugConsoleSegment],
        source: _debugSource,
        conditions: [_debugFeatureOn('console')],
        annotations: const [ConsoleSegment('filter')],
        create: (r) => FilterSegment(r.dependency<DebugLogFilter>()),
      ),
      ..._debugLogFilter,
    ]);

/// The console's `isolates` segment (`isolatesSegment`): the isolates and
/// engine threads, and how busy the busiest is, from the task manager.
/// The generator puts this module into the app only when
/// `spring.flutter.debug.console.segments` names `isolates` or holds `*`,
/// with the console and the task manager
/// (`spring.flutter.debug.isolates.enabled`) in the build.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'isolates',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild('spring.flutter.debug.isolates.enabled'),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleIsolatesAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleIsolatesAutoConfiguration',
      [
        BeanDefinition<IsolatesSegment>(
          name: 'isolatesSegment',
          types: const [IsolatesSegment, DebugConsoleSegment],
          source: _debugSource,
          conditions: [
            _debugFeatureOn('console'),
            _debugFeatureOn('isolates'),
          ],
          annotations: const [ConsoleSegment('isolates')],
          create: (r) => IsolatesSegment(r.dependency<DebugIsolates>()),
        ),
      ],
    );

/// The console's `memory` segment (`memorySegment`): the process's
/// resident memory natively, the JavaScript heap on the web, and Flutter's
/// image cache (`mem 182 MB · img 34 MB`), from the task manager's memory.
/// The generator puts this module into the app only when
/// `spring.flutter.debug.console.segments` names `memory` or holds `*`,
/// with the console and the task manager
/// (`spring.flutter.debug.isolates.enabled`) in the build.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'memory',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild('spring.flutter.debug.isolates.enabled'),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleMemoryAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugConsoleMemoryAutoConfiguration', [
      BeanDefinition<MemoryConsoleSegment>(
        name: 'memorySegment',
        types: const [MemoryConsoleSegment, DebugConsoleSegment],
        source: _debugSource,
        conditions: [_debugFeatureOn('console'), _debugFeatureOn('isolates')],
        annotations: const [ConsoleSegment('memory')],
        create: (r) => MemoryConsoleSegment(r.dependency<DebugIsolates>()),
      ),
    ]);

/// The console's `timeline` segment (`timelineSegment`): how long the
/// start took, from the timeline. The generator puts this module into the
/// app only when `spring.flutter.debug.console.segments` names `timeline`
/// or holds `*`, with the console and the timeline
/// (`spring.flutter.debug.timeline.enabled`) in the build.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'timeline',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild('spring.flutter.debug.timeline.enabled'),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleTimelineAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleTimelineAutoConfiguration',
      [
        BeanDefinition<TimelineSegment>(
          name: 'timelineSegment',
          types: const [TimelineSegment, DebugConsoleSegment],
          source: _debugSource,
          conditions: [
            _debugFeatureOn('console'),
            _debugFeatureOn('timeline'),
          ],
          annotations: const [ConsoleSegment('timeline')],
          create: (r) => TimelineSegment(r.dependency<DebugTimeline>()),
        ),
      ],
    );

/// The debug console's `logs` pane (`logsPane`, order 0, on top): the
/// newest records, coloured as the console colours them, wrapped and
/// scrolling back through the buffer, by the filter of the panel's Logs tab
/// (`debugLogFilter`), or by `spring.flutter.debug.console.filter.*`
/// without the panel, `spring.flutter.debug.console.max-lines` high at the
/// start; with its selection (`Select`) in the console's header while it
/// shows. The generator puts this module into the app when
/// `spring.flutter.debug.console.panes` names `logs`, holds `*` or is not
/// set (its default is `[logs]`), in a build with the console
/// (`spring.flutter.debug.console.enabled: true`, its parent): otherwise
/// there is no code of the pane, its selection or the `export` command.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'logs',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleLogsAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugConsoleLogsAutoConfiguration', [
      BeanDefinition<LogsPane>(
        name: 'logsPane',
        types: const [LogsPane, DebugConsolePane],
        source: _debugSource,
        conditions: [_debugFeatureOn('console')],
        order: 0,
        annotations: const [ConsolePane('logs')],
        create: (r) => LogsPane(
          filter: r.dependency<DebugLogFilter>(),
          buffer: r.optionalDependency<LogBuffer>(),
          logging: r.optionalDependency<LoggingSystem>(),
          actions: r.optionalDependencyList<DebugLogsActions>() ?? const [],
          maxLines: r.dependency<FlutterDebugProperties>().console.maxLines,
        ),
      ),
      ..._debugLogFilter,
    ]);

/// The debug console's `commands` pane (`commandsPane`, order 10): a line
/// typed into its input and sent with Enter runs a `DebugConsoleCommand`
/// bean by the word of its `@ConsoleCommand` (the application's, and the
/// framework's `help`, which lists them all), its output printed into the
/// pane; up and down go back through the last
/// `spring.flutter.debug.console.history` lines. The generator puts this
/// module into the app only when `spring.flutter.debug.console.panes`
/// names `commands` or holds `*`, in a build with the console
/// (`spring.flutter.debug.console.enabled: true`, its parent): otherwise
/// there is no code of it, nor of any command.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'commands',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleCommandsAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleCommandsAutoConfiguration',
      [
        BeanDefinition<CommandsPane>(
          name: 'commandsPane',
          types: const [CommandsPane, DebugConsolePane],
          source: _debugSource,
          conditions: [_debugFeatureOn('console')],
          order: 10,
          annotations: const [ConsolePane('commands', order: 10)],
          create: (r) {
            final shortcuts = r.lazyDependency<KeyboardShortcuts>();
            final console = r.dependency<FlutterDebugProperties>().console;
            return CommandsPane(
              consoleCommandsByName(r),
              historySize: console.history,
              closeKeys: () => [
                for (final keys in shortcuts().keysOf(
                  'debug.console',
                  defaultTargetPlatform,
                ))
                  keys.activator,
              ],
            );
          },
        ),
        BeanDefinition<HelpCommand>(
          name: 'helpCommand',
          types: const [HelpCommand, DebugConsoleCommand],
          source: _debugSource,
          conditions: [_debugFeatureOn('console')],
          annotations: const [ConsoleCommand('help')],
          create: (_) => const HelpCommand(),
        ),
      ],
    );

/// The console's `export [log|jsonl]` command (`exportCommand`): the
/// records marked in the `logs` pane, else those its filter shows,
/// exported by `debugLogExport`, what it tells printed. The generator puts
/// this module into the app only with the `commands` pane (its own switch,
/// the console's inside it), the `logs` pane and the log export
/// (`spring.flutter.debug.logs.export.enabled`): without any of them there
/// is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'commands',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild.named(
        'spring.flutter.debug.console.panes',
        'logs',
        whenMissing: BuildInclusion.always,
      ),
      AutoConfigurationBuild('spring.flutter.debug.logs.export.enabled'),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleExportCommandAutoConfiguration = BeanModule(
  'springBootStarterFlutterDebugConsoleExportCommandAutoConfiguration',
  [
    BeanDefinition<ExportCommand>(
      name: 'exportCommand',
      types: const [ExportCommand, DebugConsoleCommand],
      source: _debugSource,
      conditions: [
        _debugFeatureOn('console'),
        _debugFeatureOn('logs.export'),
      ],
      annotations: const [ConsoleCommand('export')],
      create: (r) => ExportCommand(
        r.dependency<DebugLogExport>(),
        r.dependency<LogsPane>(),
      ),
    ),
  ],
);

/// The debug panel's Console tab (`debugConsoleSection`): each segment and
/// pane the build has shown or hidden, the header's order changed, live,
/// on the `debugConsole` bean. The generator puts this module into the app
/// only with the console (`spring.flutter.debug.console.enabled: true`)
/// and the panel (`spring.flutter.debug.enabled`, its parent): without
/// either there is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.console.enabled',
    whenMissing: BuildInclusion.never,
    parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')],
  ),
)
final BeanModule springBootStarterFlutterDebugConsoleSectionAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleSectionAutoConfiguration',
      [
        BeanDefinition<DebugConsoleSection>(
          name: 'debugConsoleSection',
          types: const [DebugConsoleSection, DebugPanelSection, Ordered],
          source: _debugSource,
          conditions: [
            _debugFeatureOn('console'),
            const ConditionalOnBean(DebugPanel),
          ],
          create: (r) => DebugConsoleSection(r.dependency<DebugConsole>()),
        ),
      ],
    );

/// Every animation of the app on or off by the action `debug.motion`
/// (⌘⇧M) or the debug panel's Motion tab (`debugMotion`). The generator
/// puts this module into the app by `spring.flutter.debug.motion.enabled`:
/// `true` always, `false` never (no code), not set debug builds only.
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

/// The timeline of the start and the observations (`debugTimeline`): its
/// tab in the debug panel, and how long the start took in the debug
/// console's `timeline` segment. The `timelineObservations` bean is an
/// `ObservationHandler`, so it gets every observation. The generator puts
/// this module into the app by `spring.flutter.debug.timeline.enabled`:
/// `true` always, `false` never (no code), not set debug builds
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
        source: _debugSource,
        conditions: [_debugFeatureOn('timeline')],
        create: (r) => DebugTimeline(
          // The SpringApplicationWidget's; an app without it has no stages.
          trace:
              r.optionalDependency<SplashTrace>() ??
              SplashTrace(SplashStages(), log: false),
          observations: r.dependency<TimelineObservations>(),
        ),
      ),
      BeanDefinition<DebugTimelineSection>(
        name: 'debugTimelineSection',
        types: const [DebugTimelineSection, DebugPanelSection, Ordered],
        source: _debugSource,
        conditions: [_debugFeatureOn('timeline')],
        create: (r) => DebugTimelineSection(r.dependency<DebugTimeline>()),
      ),
    ]);

/// The beans layer of the application graph (`beansGraphLayer`, on the
/// data of `debugBeanGraph`) and the debug panel's Graph tab with it
/// (`debugGraphSection`): the application's beans by module, the
/// framework's behind the layer's `framework` chip, an edge from a bean to
/// each bean that injects it, a flash when one is created or destroyed,
/// followed only while a view shows the layer. The generator puts this
/// module into the app when `spring.flutter.debug.graph.layers` names
/// `beans`, holds `*` or is not set, and only as far as the graph's
/// switch (`spring.flutter.debug.graph.enabled`) and the panel's (its
/// parents) let it in: otherwise there is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.graph.layers',
    'beans',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),
      AutoConfigurationBuild('spring.flutter.debug.enabled'),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugBeansGraphAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugBeansGraphAutoConfiguration', [
      ..._debugBeanGraph(_inGraphTab),
      ...debugGraphSectionDefinitions,
    ]);

/// The debug console's `graph` pane (`debugGraphPane`) with the beans
/// layer in it. The generator puts this module into the app only with the
/// console (`spring.flutter.debug.console.enabled: true`), when
/// `spring.flutter.debug.console.panes` names `graph` or holds `*`, when
/// and when `spring.flutter.debug.graph.layers` lets `beans` in (not set:
/// it does).
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
        'beans',
        whenMissing: BuildInclusion.always,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleBeansGraphPaneAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleBeansGraphPaneAutoConfiguration',
      [
        ..._debugBeanGraph(_inGraphPane),
        ...debugGraphPaneDefinitions,
      ],
    );

// The view of the graph a layer is made for, in a running app: the
// panel's Graph tab (the panel and the tab on) or the console's `graph`
// pane (the console on).
const List<Condition> _inGraphTab = [
  ConditionalOnBean(DebugPanel),
  ConditionalOnProperty(
    'spring.flutter.debug.graph.enabled',
    havingValue: 'true',
    matchIfMissing: true,
  ),
];
const List<Condition> _inGraphPane = [ConditionalOnBean(DebugConsole)];

// The beans' data and their layer, made by the first module of the two.
List<BeanDefinition<Object>> _debugBeanGraph(List<Condition> viewer) => [
  BeanDefinition<DebugBeanGraph>(
    name: 'debugBeanGraph',
    types: const [DebugBeanGraph, ChangeNotifier, Listenable],
    source: _debugSource,
    conditions: [
      ...viewer,
      const ConditionGroup('$_debugSource#debugBeanGraph', [
        ConditionalOnMissingBean(DebugBeanGraph),
      ]),
    ],
    eventListeners: [
      EventListenerMethod.of<DebugBeanGraph, ApplicationStartedEvent>(
        'DebugBeanGraph.useApplication',
        (graph, event) {
          graph.useApplication(event.springApplication);
          return null;
        },
      ),
    ],
    preDestroy: (graph) => graph.dispose(),
    create: (r) =>
        DebugBeanGraph(r.dependency<ConfigurableApplicationContext>()),
  ),
  BeanDefinition<BeansGraphLayer>(
    name: 'beansGraphLayer',
    types: const [BeansGraphLayer, DebugGraphLayer],
    source: _debugSource,
    conditions: [
      ...viewer,
      const ConditionGroup('$_debugSource#beansGraphLayer', [
        ConditionalOnMissingBean(BeansGraphLayer),
      ]),
    ],
    preDestroy: (layer) => layer.dispose(),
    create: (r) => BeansGraphLayer(
      r.dependency<DebugBeanGraph>(),
      routes: r.optionalDependency<DebugGraphRoutes>(),
    ),
  ),
];

/// The task manager of the app's isolates and the engine's threads
/// (`debugIsolates`): its tab in the debug panel with every value, and the
/// debug console's `isolates` and `memory` segments; the tab's memory
/// block (the process's or the JavaScript heap, the Dart heap from the VM
/// service, the image cache) and, on the web, what the page downloaded.
/// The `flutterEngineLoads` bean is an
/// `IsolateLoadSource`, so `isolateLoads` (and what else reads it: the
/// actuator) has the engine's threads beside the isolates: `raster`,
/// `platform`, `io`, and the frames' build times in `main`. Nothing is
/// read or measured while neither the tab nor a segment shows. The
/// generator puts this module into the app by
/// `spring.flutter.debug.isolates.enabled`: `true` always, `false` never
/// (no code), not set debug builds only.
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.debug.isolates.enabled'),
)
final BeanModule springBootStarterFlutterDebugIsolatesAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugIsolatesAutoConfiguration', [
      BeanDefinition<FlutterEngineLoads>(
        name: 'flutterEngineLoads',
        types: const [FlutterEngineLoads, IsolateLoadSource],
        source: _debugSource,
        conditions: [_debugFeatureOn('isolates')],
        preDestroy: (loads) => loads.stop(),
        create: (_) => FlutterEngineLoads(),
      ),
      BeanDefinition<DebugIsolates>(
        name: 'debugIsolates',
        source: _debugSource,
        conditions: [_debugFeatureOn('isolates')],
        preDestroy: (isolates) => isolates.dispose(),
        create: (r) => DebugIsolates(
          loads: r.dependency<IsolateLoads>(),
          interval: r.dependency<FlutterDebugProperties>().isolates.interval,
        ),
      ),
      BeanDefinition<DebugIsolatesSection>(
        name: 'debugIsolatesSection',
        types: const [DebugIsolatesSection, DebugPanelSection, Ordered],
        source: _debugSource,
        conditions: [_debugFeatureOn('isolates')],
        create: (r) => DebugIsolatesSection(r.dependency<DebugIsolates>()),
      ),
    ]);

/// Flutter's own debug tools in the debug panel's Flutter tab
/// (`debugFlutterTools`): the widget inspector, the performance overlay,
/// the semantics debugger, the `debugPaint*` flags, slow animations and
/// the address DevTools connects to. A tab of the panel, so its beans are
/// there only with the panel (`debugPanel`). The generator puts this
/// module into the app by `spring.flutter.debug.flutter-tools.enabled`:
/// `true` always, `false` never (no code), not set debug builds only; and only
/// as far as the panel's own switch
/// (`spring.flutter.debug.enabled`, its parent) lets it in, so a build
/// without the panel has none of its code whatever its own switch says.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.flutter-tools.enabled',
    parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')],
  ),
)
final BeanModule springBootStarterFlutterDebugFlutterToolsAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugFlutterToolsAutoConfiguration', [
      BeanDefinition<DebugFlutterTools>(
        name: 'debugFlutterTools',
        types: const [DebugFlutterTools, ChangeNotifier, Listenable],
        source: _debugSource,
        conditions: _flutterToolsOn,
        create: (_) => DebugFlutterTools(),
        preDestroy: (tools) => tools.reset(),
      ),
      BeanDefinition<DebugFlutterToolsCustomizer>(
        name: 'debugFlutterToolsCustomizer',
        types: const [
          DebugFlutterToolsCustomizer,
          FlutterAppCustomizer,
          Ordered,
        ],
        source: _debugSource,
        conditions: _flutterToolsOn,
        create: (r) =>
            DebugFlutterToolsCustomizer(r.dependency<DebugFlutterTools>()),
      ),
      BeanDefinition<DebugFlutterToolsSection>(
        name: 'debugFlutterToolsSection',
        types: const [DebugFlutterToolsSection, DebugPanelSection, Ordered],
        source: _debugSource,
        conditions: _flutterToolsOn,
        create: (r) =>
            DebugFlutterToolsSection(r.dependency<DebugFlutterTools>()),
      ),
    ]);

// The Flutter tab's beans: with the panel, and its feature on.
final List<Condition> _flutterToolsOn = [
  _debugFeatureOn('flutter-tools'),
  const ConditionalOnBean(DebugPanel),
];

/// The network recorder and the debug panel's Network tab
/// (`debugNetworkSection`): `debugNetworkRecorder`, a post-processor, puts
/// a recording decorator around every `HttpTransport` and
/// `WebSocketTransport` bean, so the requests of `RestClient`, the OAuth2
/// client, Supabase, the WebSocket starter and the app's own go into
/// `debugNetworkJournal` (the last `max-entries`, headers masked, bodies
/// only with `bodies`) while passing through unchanged. The generator puts
/// this module into the app only with
/// `spring.flutter.debug.network.enabled: true`, and only as far as the
/// panel's own switch (`spring.flutter.debug.enabled`, its parent) lets it
/// in: not set or `false`, there is no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.network.enabled',
    whenMissing: BuildInclusion.never,
    parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')],
  ),
)
final BeanModule springBootStarterFlutterDebugNetworkAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugNetworkAutoConfiguration', [
      ..._debugNetworkRecorder(const ConditionalOnBean(DebugPanel)),
      BeanDefinition<DebugNetworkSection>(
        name: 'debugNetworkSection',
        types: const [DebugNetworkSection, DebugPanelSection, Ordered],
        source: _debugSource,
        conditions: [
          _debugFeatureOn('network'),
          const ConditionalOnBean(DebugPanel),
        ],
        create: (r) => DebugNetworkSection(r.dependency<DebugNetworkJournal>()),
      ),
    ]);

/// The console's `network` pane (`networkPane`, order 30): a line per
/// request and WebSocket of the network recorder, newest at the bottom.
/// The generator puts this module into the app only when
/// `spring.flutter.debug.console.panes` names `network` or holds `*`, with
/// the console (`spring.flutter.debug.console.enabled: true`) and the
/// recorder (`spring.flutter.debug.network.enabled: true`) in the build;
/// it makes the recorder and its journal too when the panel's Network tab
/// has not.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'network',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild(
        'spring.flutter.debug.network.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleNetworkPaneAutoConfiguration = BeanModule(
  'springBootStarterFlutterDebugConsoleNetworkPaneAutoConfiguration',
  [
    ..._debugNetworkRecorder(const ConditionalOnBean(DebugConsole)),
    BeanDefinition<NetworkConsolePane>(
      name: 'networkPane',
      types: const [NetworkConsolePane, DebugConsolePane],
      source: _debugSource,
      conditions: [
        _debugFeatureOn('console'),
        _debugFeatureOn('network'),
        const ConditionalOnBean(DebugNetworkJournal),
      ],
      order: 30,
      annotations: const [ConsolePane('network', order: 30)],
      create: (r) => NetworkConsolePane(
        r.dependency<DebugNetworkJournal>(),
        hasNetworkTab: r.optionalDependency<DebugNetworkSection>() != null,
      ),
    ),
  ],
);

/// The console's `net` segment (`networkSegment`): the requests in
/// flight, the failed ones and the last WebSocket heartbeat round trip of
/// the network recorder. The generator puts this module into the app only
/// when `spring.flutter.debug.console.segments` names `net` or holds `*`,
/// with the console and the recorder in the build (as the `network`
/// pane); it makes the recorder and its journal too when nothing else has.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.segments',
    'net',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
      AutoConfigurationBuild(
        'spring.flutter.debug.network.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleNetworkSegmentAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleNetworkSegmentAutoConfiguration',
      [
        ..._debugNetworkRecorder(const ConditionalOnBean(DebugConsole)),
        BeanDefinition<NetworkConsoleSegment>(
          name: 'networkSegment',
          types: const [NetworkConsoleSegment, DebugConsoleSegment],
          source: _debugSource,
          conditions: [
            _debugFeatureOn('console'),
            _debugFeatureOn('network'),
            const ConditionalOnBean(DebugNetworkJournal),
          ],
          annotations: const [ConsoleSegment('net')],
          create: (r) =>
              NetworkConsoleSegment(r.dependency<DebugNetworkJournal>()),
        ),
      ],
    );

/// The recorder and its journal (`debugNetworkRecorder`,
/// `debugNetworkJournal`), for the module of each view of the traffic,
/// with the condition that the view is there ([viewer]): the first module
/// whose view is there makes them, so they are in the build only with a
/// view and record only while one is in the running app. The application's
/// `NetworkTransportDecorator`, `WebSocketFrameLabeler` and
/// `NetworkBodyMasker` beans come before the built-in ones.
List<BeanDefinition<Object>> _debugNetworkRecorder(Condition viewer) => [
  BeanDefinition<DebugNetworkJournal>(
    name: 'debugNetworkJournal',
    types: const [DebugNetworkJournal, ChangeNotifier, Listenable],
    source: _debugSource,
    conditions: [
      _debugFeatureOn('network'),
      viewer,
      const ConditionGroup('$_debugSource#debugNetworkJournal', [
        ConditionalOnMissingBean(DebugNetworkJournal),
      ]),
    ],
    create: (r) {
      final network = r.dependency<FlutterDebugProperties>().network;
      return DebugNetworkJournal(
        maxEntries: network.maxEntries,
        bodies: network.bodies,
        bodyLimit: network.bodyLimit.toBytes(),
        bodyBudget: network.bodyBudget.toBytes(),
        maxFrames: network.maxFrames,
        masking: NetworkMasking(
          bodyMaskers: [
            ...?r.optionalDependencyList<NetworkBodyMasker>(),
            ...NetworkMasking.defaultBodyMaskers,
          ],
        ),
      );
    },
  ),
  BeanDefinition<DebugNetworkRecorder>(
    name: 'debugNetworkRecorder',
    types: const [DebugNetworkRecorder, BeanPostProcessor, BeanFactoryAware],
    source: _debugSource,
    conditions: [
      _debugFeatureOn('network'),
      viewer,
      const ConditionGroup('$_debugSource#debugNetworkRecorder', [
        ConditionalOnMissingBean(DebugNetworkRecorder),
      ]),
    ],
    create: (r) => DebugNetworkRecorder(
      r.lazyDependency<DebugNetworkJournal>(),
      decorators: [
        ...?r.optionalDependencyList<NetworkTransportDecorator>(),
        ...DebugNetworkRecorder.defaultDecorators(
          labelers: [
            ...?r.optionalDependencyList<WebSocketFrameLabeler>(),
            const PhoenixFrameLabeler(),
          ],
        ),
      ],
    ),
  ),
];

/// The log export from the debug panel's Logs tab (its `Export .log` and
/// `Export .jsonl` buttons): `debugLogExport`, its formats (the
/// `DebugLogFormat` beans) and where a file goes (`debugFileExports`, the
/// first available `DebugFileExport` bean: the application's, a browser
/// download, the Downloads folder of a desktop; on a phone only the
/// application's, never the clipboard unless it registers
/// `ClipboardDebugFileExport`). The
/// generator puts this module into the app by
/// `spring.flutter.debug.logs.export.enabled` (`true` always, `false`
/// never, not set debug builds only), and only as far as the
/// panel's own switch (`spring.flutter.debug.enabled`, its parent) lets it
/// in.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.logs.export.enabled',
    parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')],
  ),
)
final BeanModule springBootStarterFlutterDebugLogsExportAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugLogsExportAutoConfiguration',
      _debugLogExport(const ConditionalOnBean(DebugPanel)),
    );

/// The log export with the debug console, for its commands: the same
/// beans as [springBootStarterFlutterDebugLogsExportAutoConfiguration],
/// by the same switch, inside the console's
/// (`spring.flutter.debug.console.enabled`, its parent). With both the
/// panel and the console, the first makes them.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.logs.export.enabled',
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration = BeanModule(
  'springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration',
  _debugLogExport(const ConditionalOnBean(DebugConsole)),
);

/// The beans of the log export, for the module of each view of the logs,
/// with the condition that the view is there ([viewer]): the first module
/// whose view is there makes them, so they are in the build only with the
/// panel or the console, and only while one is in the running app. The
/// application's `DebugLogFormat` and `DebugFileExport` beans join the
/// built-in ones, by `@Order`.
List<BeanDefinition<Object>> _debugLogExport(Condition viewer) {
  List<Condition> once(String bean, Type type) => [
    _debugFeatureOn('logs.export'),
    viewer,
    ConditionGroup('$_debugSource#$bean', [ConditionalOnMissingBean(type)]),
  ];
  return [
    BeanDefinition<PlainDebugLogFormat>(
      name: 'plainDebugLogFormat',
      types: const [PlainDebugLogFormat, DebugLogFormat, Ordered],
      source: _debugSource,
      conditions: once('plainDebugLogFormat', PlainDebugLogFormat),
      create: (r) {
        final logging = r.optionalDependency<LoggingSystem>();
        return PlainDebugLogFormat(
          () => logging?.console.pattern ?? debugLogFallbackPattern,
        );
      },
    ),
    BeanDefinition<JsonLinesDebugLogFormat>(
      name: 'jsonLinesDebugLogFormat',
      types: const [JsonLinesDebugLogFormat, DebugLogFormat, Ordered],
      source: _debugSource,
      conditions: once('jsonLinesDebugLogFormat', JsonLinesDebugLogFormat),
      create: (_) => const JsonLinesDebugLogFormat(),
    ),
    BeanDefinition<BrowserDebugFileExport>(
      name: 'browserDebugFileExport',
      types: const [BrowserDebugFileExport, DebugFileExport, Ordered],
      source: _debugSource,
      conditions: once('browserDebugFileExport', BrowserDebugFileExport),
      create: (_) => const BrowserDebugFileExport(),
    ),
    BeanDefinition<DownloadsDebugFileExport>(
      name: 'downloadsDebugFileExport',
      types: const [DownloadsDebugFileExport, DebugFileExport, Ordered],
      source: _debugSource,
      conditions: once('downloadsDebugFileExport', DownloadsDebugFileExport),
      create: (_) => const DownloadsDebugFileExport(),
    ),
    BeanDefinition<DebugFileExports>(
      name: 'debugFileExports',
      source: _debugSource,
      conditions: once('debugFileExports', DebugFileExports),
      create: (r) =>
          DebugFileExports(r.optionalDependencyList<DebugFileExport>() ?? []),
    ),
    BeanDefinition<DebugLogExport>(
      name: 'debugLogExport',
      types: const [DebugLogExport, DebugLogsActions],
      source: _debugSource,
      conditions: once('debugLogExport', DebugLogExport),
      create: (r) {
        final environment = r.dependency<ConfigurableEnvironment>();
        return DebugLogExport(
          formats: r.optionalDependencyList<DebugLogFormat>() ?? const [],
          files: r.dependency<DebugFileExports>(),
          appName:
              environment.getProperty('spring.application.name') ??
              environment.getProperty('spring.flutter.app.title') ??
              'app',
        );
      },
    ),
  ];
}

/// The debug panel's Graph tab (`debugGraphSection`, under `App`), for the
/// module of each layer of the application graph: the first module there
/// makes it, so the tab and the graph's engine are in the build only with
/// a layer. A layer's module lists these definitions beside its layer, with
/// the panel's switch and `spring.flutter.debug.graph.enabled` among its
/// parents:
///
/// ```dart
/// @AutoConfigurationModule(
///   build: AutoConfigurationBuild.named(
///     'spring.flutter.debug.graph.layers',
///     'routes',
///     whenMissing: BuildInclusion.always,
///     parents: [
///       AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),
///       AutoConfigurationBuild('spring.flutter.debug.enabled'),
///     ],
///   ),
/// )
/// final BeanModule routesGraphAutoConfiguration = BeanModule(
///   'routesGraphAutoConfiguration',
///   [routesGraphLayer, ...debugGraphSectionDefinitions],
/// );
/// ```
///
/// It shows every `DebugGraphLayer` bean, and is there only with the panel
/// (`debugPanel`) and while `spring.flutter.debug.graph.enabled` is not
/// `false`. With it comes `debugGraphRoutes`, the grouping the layers
/// share (`Group by: Route | Module`).
final List<BeanDefinition<Object>> debugGraphSectionDefinitions = [
  _debugGraphRoutes,
  _debugGraphFit,
  BeanDefinition<DebugGraphSection>(
    name: 'debugGraphSection',
    types: const [DebugGraphSection, DebugPanelSection, Ordered],
    source: _debugSource,
    conditions: [
      _debugFeatureOn('graph'),
      const ConditionalOnBean(DebugPanel),
      const ConditionalOnBean(DebugGraphLayer),
      const ConditionGroup('$_debugSource#debugGraphSection', [
        ConditionalOnMissingBean.named('debugGraphSection'),
      ]),
    ],
    create: (r) =>
        DebugGraphSection(r.optionalDependencyList<DebugGraphLayer>() ?? []),
  ),
];

/// The debug console's `graph` pane (`debugGraphPane`, order 25): the
/// application graph of every `DebugGraphLayer` bean, compact. For the
/// module of each layer whose switch lets the pane in (the layer's, under
/// `AutoConfigurationBuild.named('spring.flutter.debug.console.panes',
/// 'graph')` and the console's switch): the first makes it.
final List<BeanDefinition<Object>> debugGraphPaneDefinitions = [
  _debugGraphRoutes,
  _debugGraphFit,
  BeanDefinition<DebugGraphPane>(
    name: 'debugGraphPane',
    types: const [DebugGraphPane, DebugConsolePane],
    source: _debugSource,
    conditions: [
      _debugFeatureOn('console'),
      const ConditionalOnBean(DebugGraphLayer),
      const ConditionGroup('$_debugSource#debugGraphPane', [
        ConditionalOnMissingBean.named('debugGraphPane'),
      ]),
    ],
    order: 25,
    annotations: const [ConsolePane('graph', order: 25)],
    create: (r) =>
        DebugGraphPane(r.optionalDependencyList<DebugGraphLayer>() ?? []),
  ),
];

// The action `debug.graph.fit` (⌘⇧Z): fits the graphs on the screen; in
// the module of each view of the graph: the first makes it.
final BeanDefinition<DebugGraphFitAction> _debugGraphFit =
    BeanDefinition<DebugGraphFitAction>(
      name: 'debugGraphFit',
      types: const [
        DebugGraphFitAction,
        ShortcutHandler,
        KeyedShortcutHandler,
      ],
      source: _debugSource,
      conditions: [
        _debugFeatureOn('graph'),
        const ConditionGroup('$_debugSource#debugGraphFit', [
          ConditionalOnMissingBean(DebugGraphFitAction),
        ]),
      ],
      preDestroy: (action) => action.dispose(),
      create: (_) => DebugGraphFitAction(),
    );

// How the graph's layers group their nodes (the route grouping by default:
// the navigator stack, the routes' beans from each DebugGraphRouteBeans, as
// the navigation starter's route scopes), in the module of each view of it:
// the first makes it.
final BeanDefinition<DebugGraphRoutes> _debugGraphRoutes =
    BeanDefinition<DebugGraphRoutes>(
      name: 'debugGraphRoutes',
      types: const [DebugGraphRoutes, ChangeNotifier, Listenable],
      source: _debugSource,
      conditions: [
        _debugFeatureOn('graph'),
        const ConditionGroup('$_debugSource#debugGraphRoutes', [
          ConditionalOnMissingBean(DebugGraphRoutes),
        ]),
      ],
      preDestroy: (routes) => routes.dispose(),
      create: (r) => DebugGraphRoutes(
        beans: r.optionalDependencyList<DebugGraphRouteBeans>() ?? const [],
      ),
    );

// The widgets as a layer of the application graph, in the module of each
// view of it (the Graph tab, the `graph` pane): the first makes it.
BeanDefinition<WidgetsGraphLayer> _widgetsGraphLayer(
  List<Condition> viewer,
) => BeanDefinition<WidgetsGraphLayer>(
  name: 'widgetsGraphLayer',
  types: const [WidgetsGraphLayer, DebugGraphLayer],
  source: _debugSource,
  conditions: [
    ...viewer,
    const ConditionGroup('$_debugSource#widgetsGraphLayer', [
      ConditionalOnMissingBean(WidgetsGraphLayer),
    ]),
  ],
  preDestroy: (layer) => layer.dispose(),
  create: (r) {
    final hot = r.optionalDependency<FlutterDebugProperties>()?.graph.hot;
    return WidgetsGraphLayer(
      context: r.optionalDependency<ApplicationContext>(),
      routes: r.optionalDependency<DebugGraphRoutes>(),
      hotRebuilds: hot?.rebuilds ?? WidgetsGraphLayer.hotFrom,
      hotWindow: hot?.window ?? WidgetsGraphLayer.window,
      // The application's sources first, then Flutter's diagnostics and
      // the fields the generator reads (`debugWidgetFields`, a lazy
      // bean of the debug part, made when a card first needs it).
      properties: [
        ...?r.optionalDependencyList<WidgetProperties>(),
        const DiagnosticsWidgetProperties(),
        FieldWidgetProperties(
          r.provider<DebugWidgetFields>().getIfAvailable,
        ),
      ],
    );
  },
);

/// The widgets layer of the application graph (`widgetsGraphLayer`) and the
/// debug panel's Graph tab with it (`debugGraphSection`): the application's
/// widgets as a tree, a flash on each rebuild, the hot branches outlined.
/// The generator puts this module into the app when
/// `spring.flutter.debug.graph.layers` names `widgets`, holds `*` or is not
/// set, and only as far as `spring.flutter.debug.graph.enabled` and the
/// panel's switch (its parents) let it in: otherwise there is no code of
/// the layer.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.graph.layers',
    'widgets',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),
      AutoConfigurationBuild('spring.flutter.debug.enabled'),
    ],
  ),
)
final BeanModule springBootStarterFlutterDebugWidgetsGraphAutoConfiguration =
    BeanModule('springBootStarterFlutterDebugWidgetsGraphAutoConfiguration', [
      _widgetsGraphLayer(_inGraphTab),
      ...debugGraphSectionDefinitions,
    ]);

/// The debug console's `graph` pane (`debugGraphPane`) with the widgets
/// layer in it. The generator puts this module into the app only with the
/// console (`spring.flutter.debug.console.enabled: true`), when
/// `spring.flutter.debug.console.panes` names `graph` or holds `*`, and
/// when `spring.flutter.debug.graph.layers` lets `widgets` in (not set: it
/// does).
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
        'widgets',
        whenMissing: BuildInclusion.always,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterDebugConsoleWidgetsGraphPaneAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterDebugConsoleWidgetsGraphPaneAutoConfiguration',
      [_widgetsGraphLayer(_inGraphPane), ...debugGraphPaneDefinitions],
    );
