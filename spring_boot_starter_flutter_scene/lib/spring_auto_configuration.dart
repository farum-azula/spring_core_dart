/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_scene`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the modules below are marked `@AutoConfigurationModule()`). A test
/// that builds a context by hand imports it to name the modules.
library;

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugPanelSection, FlutterAppCustomizer, HttpTransport, SplashTask;
import 'package:spring_boot_starter_flutter_scene/src/app/application_scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/app/application_scene_background.dart';
import 'package:spring_boot_starter_flutter_scene/src/app/scene_customizer.dart';
import 'package:spring_boot_starter_flutter_scene/src/debug/scene_debug.dart';
import 'package:spring_boot_starter_flutter_scene/src/debug/scene_section.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_availability.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_backend.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine_log.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_model_importer.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_models.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/properties_beans.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_start.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_status.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_view_observer.dart';

// The auto-configurations this starter builds on (the Flutter starter's,
// and through it logging and spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter_scene/spring_auto_configuration.dart';

// Scenes in a running app: off with spring.flutter.scene.enabled=false in
// a profile, though the build has them. No scene bean exists then.
const _scenesOn = ConditionalOnProperty(
  'spring.flutter.scene.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

// The engine's messages in the application's log, unless left alone.
const _engineLogOn = ConditionalOnProperty(
  'spring.flutter.scene.engine-log',
  havingValue: 'true',
  matchIfMissing: true,
);

// The scene of the whole application: only when asked for.
const _applicationSceneOn = ConditionalOnProperty(
  'spring.flutter.scene.app.enabled',
  havingValue: 'true',
);

// Under every screen, unless the app places its views itself.
const _backgroundOn = ConditionalOnProperty(
  'spring.flutter.scene.app.placement',
  havingValue: 'background',
  matchIfMissing: true,
);

// The scenes' tab in a running app.
const _debugOn = ConditionalOnProperty(
  'spring.flutter.scene.debug.enabled',
  havingValue: 'true',
  matchIfMissing: true,
);

/// The beans the starter adds to a Flutter application with scenes
/// (`spring.flutter.scene.enabled`, on unless set to `false`):
///
/// - the engine's own messages as records of the application's log
///   (`sceneEngineLog`, the logger `flutter_scene`; off with
///   `spring.flutter.scene.engine-log: false`);
/// - the engine's one start (`sceneEngine`) on the `sceneBackend`
///   (`flutter_scene`; a bean of the app's own replaces it);
/// - whether scenes draw here (`sceneAvailability`), what every scene
///   widget reads;
/// - the models of `spring.flutter.scene.models.*` (`sceneModels`), read
///   with the `sceneModelImporter` (`.glb`; replaceable);
/// - the scenes' part of the start (`sceneStart`, a `SplashTask`): the
///   splash waits for what is eager;
/// - what the scenes are doing, in words (`sceneStatus`);
/// - with `spring.flutter.scene.app.enabled: true`, the application's
///   scene (`applicationScene`, changed by the `SceneCustomizer` beans)
///   and, unless `placement: none`, its place under every screen
///   (`applicationSceneBackground`).
///
/// With `spring.flutter.scene.enabled: false` in the application's
/// configuration the generator leaves the module out of the build, and in
/// a profile none of its beans is made: code that needs one takes an
/// `ObjectProvider` and checks. The scene widgets show their placeholders
/// either way.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.scene.enabled',
    whenMissing: BuildInclusion.always,
  ),
)
final BeanModule springBootStarterFlutterSceneAutoConfiguration = BeanModule(
  'springBootStarterFlutterSceneAutoConfiguration',
  [
    BeanDefinition<SceneBackend>(
      name: 'sceneBackend',
      source: _source,
      conditions: const [
        _scenesOn,
        ConditionGroup('$_source.sceneBackend', [
          ConditionalOnMissingBean(SceneBackend),
        ]),
      ],
      create: (_) => const FlutterSceneBackend(),
    ),
    BeanDefinition<SceneEngineLog>(
      name: 'sceneEngineLog',
      source: _source,
      conditions: const [_scenesOn, _engineLogOn],
      preDestroy: (log) => log.uninstall(),
      create: (_) => SceneEngineLog()..install(),
    ),
    BeanDefinition<SceneEngine>(
      name: 'sceneEngine',
      types: const [SceneEngine, ChangeNotifier, Listenable],
      source: _source,
      conditions: const [_scenesOn],
      preDestroy: (engine) => engine.dispose(),
      create: (r) => SceneEngine(
        backend: r.dependency<SceneBackend>(),
        events: r.dependency<ApplicationEventPublisher>(),
      ),
    ),
    BeanDefinition<SceneAvailability>(
      name: 'sceneAvailability',
      types: const [SceneAvailability, ChangeNotifier, Listenable],
      source: _source,
      conditions: const [_scenesOn],
      preDestroy: (availability) => availability.dispose(),
      create: (r) => SceneAvailability(
        properties: r.dependency<SceneProperties>(),
        engine: r.dependency<SceneEngine>(),
      ),
    ),
    BeanDefinition<SceneModelImporter>(
      name: 'sceneModelImporter',
      source: _source,
      conditions: const [
        _scenesOn,
        ConditionGroup('$_source.sceneModelImporter', [
          ConditionalOnMissingBean(SceneModelImporter),
        ]),
      ],
      create: (_) => const GlbModelImporter(),
    ),
    BeanDefinition<SceneModels>(
      name: 'sceneModels',
      source: _source,
      conditions: const [_scenesOn],
      preDestroy: (models) => models.dispose(),
      create: (r) => SceneModels(
        properties: r.dependency<SceneProperties>(),
        resources: r.dependency<ApplicationContext>(),
        engine: r.dependency<SceneEngine>(),
        importer: r.dependency<SceneModelImporter>(),
        events: r.dependency<ApplicationEventPublisher>(),
        transport: r.optionalDependency<HttpTransport>(),
        allowInsecure: RemoteAddressPolicy.of(
          r.dependency<ConfigurableEnvironment>(),
        ).allowInsecure,
      ),
    ),
    BeanDefinition<SceneStatus>(
      name: 'sceneStatus',
      types: const [SceneStatus, GenericApplicationListener],
      source: _source,
      conditions: const [_scenesOn],
      preDestroy: (status) => status.dispose(),
      create: (r) => SceneStatus(r.dependency<ApplicationContext>()),
    ),
    BeanDefinition<ApplicationScene>(
      name: 'applicationScene',
      types: const [ApplicationScene, ChangeNotifier, Listenable],
      source: _source,
      conditions: const [_scenesOn, _applicationSceneOn],
      preDestroy: (scene) => scene.dispose(),
      create: (r) => ApplicationScene(
        properties: r.dependency<SceneProperties>().app,
        engine: r.dependency<SceneEngine>(),
        events: r.dependency<ApplicationEventPublisher>(),
        customizers: r.optionalDependencyList<SceneCustomizer>() ?? const [],
      ),
    ),
    BeanDefinition<ApplicationSceneBackground>(
      name: 'applicationSceneBackground',
      types: const [
        ApplicationSceneBackground,
        FlutterAppCustomizer,
        Ordered,
      ],
      source: _source,
      conditions: const [_scenesOn, _applicationSceneOn, _backgroundOn],
      create: (_) => const ApplicationSceneBackground(),
    ),
    BeanDefinition<SceneStart>(
      name: 'sceneStart',
      types: const [SceneStart, SplashTask],
      source: _source,
      conditions: const [_scenesOn],
      create: (r) => SceneStart(
        properties: r.dependency<SceneProperties>(),
        engine: r.dependency<SceneEngine>(),
        models: r.dependency<SceneModels>(),
        events: r.dependency<ApplicationEventPublisher>(),
        scene: r.optionalDependency<ApplicationScene>(),
      ),
    ),
  ],
  imports: [sceneConfigBeans],
);

/// The scenes' tab of the debug panel (`sceneDebugSection`) and what it
/// measures by (`sceneDebug`, the observer of every scene view). The
/// generator puts this module into the app by
/// `spring.flutter.scene.debug.enabled`: `true` always, `false` never (no
/// code), not set in debug and profile builds only. The tab shows where
/// the debug panel is in the build (`spring.flutter.debug.enabled`).
@AutoConfigurationModule(
  build: AutoConfigurationBuild('spring.flutter.scene.debug.enabled'),
)
final BeanModule springBootStarterFlutterSceneDebugAutoConfiguration =
    BeanModule('springBootStarterFlutterSceneDebugAutoConfiguration', [
      BeanDefinition<SceneDebug>(
        name: 'sceneDebug',
        types: const [
          SceneDebug,
          SceneViewObserver,
          ChangeNotifier,
          Listenable,
        ],
        source: _source,
        conditions: const [_scenesOn, _debugOn],
        preDestroy: (debug) => debug.dispose(),
        create: (_) => SceneDebug(),
      ),
      BeanDefinition<SceneDebugSection>(
        name: 'sceneDebugSection',
        types: const [SceneDebugSection, DebugPanelSection, Ordered],
        source: _source,
        conditions: const [_scenesOn, _debugOn],
        create: (r) => SceneDebugSection(
          debug: r.dependency<SceneDebug>(),
          availability: r.dependency<SceneAvailability>(),
          models: r.dependency<SceneModels>(),
          status: r.dependency<SceneStatus>(),
        ),
      ),
    ]);
