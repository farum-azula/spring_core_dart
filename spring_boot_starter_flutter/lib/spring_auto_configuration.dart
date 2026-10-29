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
import 'package:flutter/cupertino.dart' show CupertinoThemeData;
import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:flutter/material.dart' show ThemeData;
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

// The auto-configurations this starter builds on (logging, and through it spring_boot_dart's), so a test of an application that lists only this starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

/// The beans the starter adds to every Flutter application:
///
/// - support for `asset:` locations, so `@Value('asset:...')` injects
///   Flutter assets as resources;
/// - the advice that calls `notifyListeners()` for `@NotifyListeners` and
///   `@ChangeNotifierComponent` beans, and the one that tells Spring
///   widgets which of those beans their `build` read;
/// - the app's themes from `spring.flutter.theme.*` (`SpringThemes`) and
///   the choice of the theme shown (`ThemeSelection`).
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
      ),
    ),
    BeanDefinition<ThemeSelection>(
      name: 'themeSelection',
      types: const [ThemeSelection, ChangeNotifier, Listenable],
      source: _source,
      create: (r) => ThemeSelection(r.dependency<SpringThemes>()),
    ),
  ],
);
