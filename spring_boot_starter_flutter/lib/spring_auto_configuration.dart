/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_flutter` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/asset_resource.dart';
import 'package:spring_boot_starter_flutter/src/bean_reads.dart';
import 'package:flutter/cupertino.dart' show CupertinoThemeData;
import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:flutter/material.dart' show ThemeData;
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

const _source =
    'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

/// `asset:` resources, the advice behind `@NotifyListeners` (and the one
/// telling Spring widgets which notifier beans they read), and the
/// app's themes (`SpringThemes`, `ThemeSelection`) of
/// `spring.flutter.theme.*`.
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
