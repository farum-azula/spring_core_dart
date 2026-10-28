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
import 'package:spring_boot_starter_flutter/src/browser/platform_authorization_browser.dart';
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/secure_token_store.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show AuthorizationBrowser, TokenStore;

// The auto-configurations this starter builds on (logging, and through it spring_boot_dart's), so a test of an application that lists only this starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';
// The OAuth2 client's, whose TokenStore and AuthorizationBrowser defaults
// the beans below replace.
export 'package:spring_boot_starter_oauth2_client/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

// The OAuth2 client's auto-configuration, which must see the platform's
// TokenStore and AuthorizationBrowser (its defaults yield to them). Unknown
// names are ignored.
const _oauth2ClientModules = [
  'springBootStarterOauth2ClientAutoConfiguration',
  'OAuth2ClientAutoConfiguration',
];

// The platform has a secure storage (not the web).
final class _OnSecureStorage implements Condition {
  const _OnSecureStorage();

  @override
  bool matches(ConditionContext context) => SecureTokenStore.isSupported;
}

// The platform has its own login browser (Android, iOS, macOS).
final class _OnPlatformBrowser implements Condition {
  const _OnPlatformBrowser();

  @override
  bool matches(ConditionContext context) =>
      PlatformAuthorizationBrowser.isSupported;
}

/// The beans the starter adds to every Flutter application:
///
/// - support for `asset:` locations, so `@Value('asset:...')` injects
///   Flutter assets as resources;
/// - the advice that calls `notifyListeners()` for `@NotifyListeners` and
///   `@ChangeNotifierComponent` beans, and the one that tells Spring
///   widgets which of those beans their `build` read;
/// - the app's themes from `spring.flutter.theme.*` (`SpringThemes`) and
///   the choice of the theme shown (`ThemeSelection`);
/// - the platform's secure storage as the `TokenStore`
///   (`SecureTokenStore`, not on the web) and its login browser as the
///   `AuthorizationBrowser` (`PlatformAuthorizationBrowser`, on Android,
///   iOS and macOS), unless the application declares its own. The module
///   is registered before the OAuth2 client's, so these replace its
///   defaults (the in-memory store, the loopback browser).
@AutoConfigurationModule(before: _oauth2ClientModules)
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
    BeanDefinition<SecureTokenStore>(
      name: 'secureTokenStore',
      types: const [SecureTokenStore, TokenStore],
      factoryMethodName: 'secureTokenStore',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.secureTokenStore', [
          _OnSecureStorage(),
          ConditionalOnMissingBean(TokenStore),
        ]),
      ],
      create: (_) => SecureTokenStore(),
    ),
    BeanDefinition<PlatformAuthorizationBrowser>(
      name: 'platformAuthorizationBrowser',
      types: const [PlatformAuthorizationBrowser, AuthorizationBrowser],
      factoryMethodName: 'platformAuthorizationBrowser',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.platformAuthorizationBrowser', [
          _OnPlatformBrowser(),
          ConditionalOnMissingBean(AuthorizationBrowser),
        ]),
      ],
      create: (_) => const PlatformAuthorizationBrowser(),
    ),
  ],
);
