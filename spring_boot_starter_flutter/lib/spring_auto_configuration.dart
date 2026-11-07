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
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/files/platform_file_store.dart';
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';
import 'package:spring_boot_starter_flutter/src/properties/properties_beans.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/keyboard_shortcuts_customizer.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';
import 'package:spring_boot_starter_flutter/src/splash/text_warm_up.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_source.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show HttpTransport;

// The auto-configurations this starter builds on (logging, and through it spring_boot_dart's), so a test of an application that lists only this starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

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
      create: (r) => ThemeSelection(r.dependency<SpringThemes>()),
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
