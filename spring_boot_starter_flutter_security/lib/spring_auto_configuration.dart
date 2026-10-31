/// The package's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_security`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:spring_boot_starter_flutter_security/src/dpop/platform_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/login/apple_id_sign_in.dart';
import 'package:spring_boot_starter_flutter_security/src/login/native_oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_token_revocation_client.dart';
import 'package:spring_boot_starter_flutter_security/src/login/secret_store_oauth2_authorized_client_service.dart';
import 'package:spring_boot_starter_flutter_security/src/principal/principal_notifier.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/platform_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_template.dart';
import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/csrf_cookie_http_transport.dart';
import 'package:spring_boot_starter_flutter_security/src/web/flutter_web_security_properties.dart';
import 'package:spring_boot_starter_flutter_security/src/web/server_credentials_http_transport.dart';
import 'package:spring_boot_starter_flutter_security/src/web/server_oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/web/spa_browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/spa_oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/web/tab_oauth2_authorized_client_service.dart';
import 'package:spring_boot_starter_flutter_security/src/web/web_crypto_dpop_key.dart';
import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';
import 'package:spring_boot_starter_flutter_security/src/window/loopback_authorization_window.dart';
import 'package:spring_boot_starter_flutter_security/src/window/platform_authorization_window.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    hide Banner, Size;

// The auto-configurations this package builds on (the Flutter starter's,
// the OAuth2 client's and, through them, logging, Feign, the security
// core and spring_boot_dart's), so a test of an application that lists
// only this package can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
export 'package:spring_boot_starter_oauth2_client/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
const _log = SpringLog('spring.security.oauth2.client');

// Every bean of this module decides "a browser" the same way: the `web`
// platform profile, which the Flutter starter activates in a browser (and
// tests may activate on the VM). The platform beans below also need the
// platform itself, so with the profile on the VM none of them exists next
// to the web's.
bool _onWeb(ConditionContext context) =>
    context.environment.activeProfiles.contains('web');

// The platform has a secure storage (not the web).
final class _OnSecureStorage implements Condition {
  const _OnSecureStorage();

  @override
  bool matches(ConditionContext context) =>
      !_onWeb(context) && PlatformSecretStore.isSupported;
}

// The platform has a place for a DPoP key that survives a restart (not
// the web).
final class _OnPlatformDPoPKey implements Condition {
  const _OnPlatformDPoPKey();

  @override
  bool matches(ConditionContext context) =>
      !_onWeb(context) && PlatformDPoPKey.isSupported;
}

// The platform has its own login window (Android, iOS, macOS).
final class _OnPlatformWindow implements Condition {
  const _OnPlatformWindow();

  @override
  bool matches(ConditionContext context) =>
      !_onWeb(context) && PlatformAuthorizationWindow.isSupported;
}

// Sign in with Apple's sheet: iOS and macOS.
final class _OnAppleIdSheet implements Condition {
  const _OnAppleIdSheet();

  @override
  bool matches(ConditionContext context) =>
      !_onWeb(context) && PlatformAppleIdSignIn.isSupported;
}

// The login window of Windows and Linux.
final class _OnLoopbackWindow implements Condition {
  const _OnLoopbackWindow();

  @override
  bool matches(ConditionContext context) =>
      !_onWeb(context) && LoopbackAuthorizationWindow.isSupported;
}

// A browser: the `web` platform profile.
final class _OnWeb implements Condition {
  const _OnWeb();

  @override
  bool matches(ConditionContext context) => _onWeb(context);
}

// Not a browser.
final class _NotOnWeb implements Condition {
  const _NotOnWeb();

  @override
  bool matches(ConditionContext context) => !const _OnWeb().matches(context);
}

// The web login's server mode: spring.flutter.security.web.mode=server or
// unset. Another value fails when flutterWebSecurityProperties is created.
final class _OnServerMode implements Condition {
  const _OnServerMode();

  @override
  bool matches(ConditionContext context) => switch (context.environment
      .getProperty('${FlutterWebSecurityProperties.prefix}.mode')
      ?.trim()
      .toLowerCase()) {
    null || '' || 'server' => true,
    _ => false,
  };
}

// The web login's spa mode: spring.flutter.security.web.mode=spa, the
// browser logs in by itself.
final class _OnSpaMode implements Condition {
  const _OnSpaMode();

  @override
  bool matches(ConditionContext context) =>
      context.environment
          .getProperty('${FlutterWebSecurityProperties.prefix}.mode')
          ?.trim()
          .toLowerCase() ==
      'spa';
}

// OAuth2 clients: a spring.security.oauth2.client.registration.* property
// (Spring Boot's ClientsConfiguredCondition), or a
// ClientRegistrationRepository bean of the application. This module comes
// before the OAuth2 client's, so @ConditionalOnBean would not see the
// client's repository yet.
final class _OnClientRegistrations implements Condition {
  const _OnClientRegistrations();

  @override
  bool matches(ConditionContext context) =>
      OAuth2ClientProperties.hasRegistrations(context.environment) ||
      context.beanFactory
          .getBeanNamesForType(ClientRegistrationRepository)
          .isNotEmpty;
}

/// The beans the package adds to every Flutter application with it:
///
/// - the `SecretStore`: the platform's secure storage
///   (`platformSecretStore`, a [PlatformSecretStore]), or where there is
///   none (the web) an [InMemorySecretStore] (`inMemorySecretStore`);
/// - `secretTemplate`, a [SecretTemplate] on the `SecretStore` and the
///   application's `ObjectMapper`, for the app's own secrets;
/// - the `AuthorizationWindow`: the system's login window on Android,
///   iOS and macOS (`platformAuthorizationWindow`, a
///   [PlatformAuthorizationWindow]), the default browser and a loopback
///   redirect on Windows and Linux (`loopbackAuthorizationWindow`, a
///   [LoopbackAuthorizationWindow]); none on the web;
/// - the logged-in user as a `Listenable` (`principalNotifier`, a
///   [PrincipalNotifier]), for `context.principal`, `PrincipalBuilder`
///   and `PrincipalView`;
///
/// outside a browser, when a `spring.security.oauth2.client.registration.*`
/// property is set (or the application declares a
/// `ClientRegistrationRepository`):
///
/// - `platformDPoPKey`, the app's `DPoPKey`: a [PlatformDPoPKey] in the
///   Secure Enclave or the Keychain (iOS, macOS), the Android Keystore,
///   or the `SecretStore` (Windows, Linux), made at its first use and
///   kept, so DPoP-bound tokens survive a restart; it replaces the
///   OAuth2 client's key of one run;
/// - `authorizedClientService`, a
///   [SecretStoreOAuth2AuthorizedClientService] on the `SecretStore`, so
///   the tokens survive a restart (DPoP tokens bound to another key than
///   the `DPoPKey` are dropped);
/// - `appleIdSignIn`, Sign in with Apple's sheet on iOS and macOS (a
///   [PlatformAppleIdSignIn]), for the registrations with
///   `native-sign-in=apple` (the default of the `apple` provider);
/// - `oauth2LoginService`, the [NativeOAuth2LoginService] of the app, on
///   the OAuth2 client's registrations, authorization code token client,
///   user services, ID token decoder and authorized client manager, with
///   the `AuthorizationWindow` and the `GrantedAuthoritiesMapper` bean
///   when there is one, the `platformDPoPKey` (deleted at logout), the
///   `appleIdSignIn` and the `native-sign-in` properties, and a
///   `JwkSetOidcIdTokenDecoder` on the `httpTransport` for the sheet's
///   identity tokens;
///
/// in a browser (the `web` platform profile):
///
/// - `flutterWebSecurityProperties`, the
///   [FlutterWebSecurityProperties] of `spring.flutter.security.web.*`;
///
/// in a browser where the app's server logs the user in
/// (`spring.flutter.security.web.mode=server`, the default):
///
/// - `browserPage`, the [BrowserPage] the app runs in;
/// - `httpTransport`, the Feign clients' transport: a
///   [CsrfCookieHttpTransport] (the CSRF token of the `XSRF-TOKEN`
///   cookie on unsafe requests to the server) around the browser's
///   `fetch`; when the server is on another origin, a
///   [ServerCredentialsHttpTransport] sends the cookies with the requests
///   to the server only (`FetchCredentials.include`), every other request
///   without them; it comes before the Feign starter's, which then backs
///   off;
/// - `serverOAuth2LoginService`, the [ServerOAuth2LoginService] of the
///   app;
///
/// and in a browser that logs in by itself
/// (`spring.flutter.security.web.mode=spa`):
///
/// - `spaBrowserPage`, the [SpaBrowserPage] the app runs in (also its
///   `BrowserPage`);
/// - with a registration: `webCryptoDPoPKey`, the app's `DPoPKey`, a
///   [WebCryptoDPoPKey] that cannot be exported, kept in IndexedDB (it
///   replaces the OAuth2 client's key of one run), and
///   `tabAuthorizedClientService`, a [TabOAuth2AuthorizedClientService]
///   (the tokens in the tab's memory only);
/// - `spaOAuth2LoginService`, the [SpaOAuth2LoginService] of the app, on
///   the OAuth2 client's registrations, authorization code token client,
///   user services and ID token decoder, with the `DPoPKey` and the
///   `GrantedAuthoritiesMapper` bean when there is one (the start fails
///   without a registration).
///
/// Each backs off when the application declares a bean of its type. The
/// module is registered before the OAuth2 client's (`before`), so its
/// `OAuth2AuthorizedClientService` replaces the client's in-memory one
/// and its `DPoPKey` the client's key of one run,
/// and before Feign's, so its `httpTransport` replaces Feign's in a
/// browser.
@AutoConfigurationModule(
  before: [
    'springBootStarterOauth2ClientAutoConfiguration',
    'springBootStarterFeignAutoConfiguration',
  ],
)
final BeanModule springBootStarterFlutterSecurityAutoConfiguration = BeanModule(
  'springBootStarterFlutterSecurityAutoConfiguration',
  [
    BeanDefinition<PlatformSecretStore>(
      name: 'platformSecretStore',
      types: const [PlatformSecretStore, SecretStore],
      factoryMethodName: 'platformSecretStore',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.platformSecretStore', [
          _OnSecureStorage(),
          ConditionalOnMissingBean(SecretStore),
        ]),
      ],
      // spring.flutter.security.application-id: the name of the app's
      // values on Windows and Linux (the app's own id by default).
      create: (r) => PlatformSecretStore(
        applicationId: switch (r
            .dependency<Environment>()
            .getProperty('spring.flutter.security.application-id')
            ?.trim()) {
          null || '' => null,
          final id => id,
        },
      ),
    ),
    BeanDefinition<InMemorySecretStore>(
      name: 'inMemorySecretStore',
      types: const [InMemorySecretStore, SecretStore],
      factoryMethodName: 'inMemorySecretStore',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.inMemorySecretStore', [
          ConditionalOnMissingBean(SecretStore),
        ]),
      ],
      create: (_) {
        _log.debug(
          'No secure storage on this platform: the SecretStore keeps '
          'nothing beyond the running app',
        );
        return InMemorySecretStore();
      },
    ),
    BeanDefinition<SecretTemplate>(
      name: 'secretTemplate',
      factoryMethodName: 'secretTemplate',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.secretTemplate', [
          ConditionalOnMissingBean(SecretTemplate),
        ]),
      ],
      create: (r) => SecretTemplate(
        r.dependency<SecretStore>(),
        objectMapper: r.optionalDependency<ObjectMapper>(),
      ),
    ),
    BeanDefinition<PlatformAuthorizationWindow>(
      name: 'platformAuthorizationWindow',
      types: const [PlatformAuthorizationWindow, AuthorizationWindow],
      factoryMethodName: 'platformAuthorizationWindow',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.platformAuthorizationWindow', [
          _OnPlatformWindow(),
          ConditionalOnMissingBean(AuthorizationWindow),
        ]),
      ],
      // `spring.flutter.security.ephemeral-session=true`: a private
      // session, no cookies shared with the browser (no single sign-on,
      // no system prompt before the window on iOS and macOS).
      create: (r) => PlatformAuthorizationWindow(
        preferEphemeralSession:
            r
                .dependency<Environment>()
                .getProperty('spring.flutter.security.ephemeral-session')
                ?.trim()
                .toLowerCase() ==
            'true',
      ),
    ),
    BeanDefinition<LoopbackAuthorizationWindow>(
      name: 'loopbackAuthorizationWindow',
      types: const [LoopbackAuthorizationWindow, AuthorizationWindow],
      factoryMethodName: 'loopbackAuthorizationWindow',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.loopbackAuthorizationWindow', [
          _OnLoopbackWindow(),
          ConditionalOnMissingBean(AuthorizationWindow),
        ]),
      ],
      create: (_) => LoopbackAuthorizationWindow(),
    ),
    BeanDefinition<PrincipalNotifier>(
      name: 'principalNotifier',
      types: const [
        PrincipalNotifier,
        ChangeNotifier,
        Listenable,
        SecurityContextChangedListener,
        GenericApplicationListener,
        DisposableBean,
      ],
      factoryMethodName: 'principalNotifier',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.principalNotifier', [
          ConditionalOnMissingBean(PrincipalNotifier),
        ]),
      ],
      create: (_) => PrincipalNotifier(),
    ),
    BeanDefinition<PlatformDPoPKey>(
      name: 'platformDPoPKey',
      types: const [PlatformDPoPKey, LoadableDPoPKey, DPoPKey],
      factoryMethodName: 'platformDPoPKey',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.platformDPoPKey', [
          _NotOnWeb(),
          _OnPlatformDPoPKey(),
          _OnClientRegistrations(),
          ConditionalOnMissingBean(DPoPKey),
        ]),
      ],
      // Nothing is asked of the platform here: the key is made or read
      // at the first proof.
      create: (r) => PlatformDPoPKey(r.dependency<SecretStore>()),
    ),
    BeanDefinition<WebCryptoDPoPKey>(
      name: 'webCryptoDPoPKey',
      types: const [WebCryptoDPoPKey, LoadableDPoPKey, DPoPKey],
      factoryMethodName: 'webCryptoDPoPKey',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.webCryptoDPoPKey', [
          _OnWeb(),
          _OnSpaMode(),
          _OnClientRegistrations(),
          ConditionalOnMissingBean(DPoPKey),
        ]),
      ],
      // Nothing is asked of the browser here: the key is made or read at
      // the first proof.
      create: (_) => WebCryptoDPoPKey(),
    ),
    BeanDefinition<TabOAuth2AuthorizedClientService>(
      name: 'tabAuthorizedClientService',
      types: const [
        TabOAuth2AuthorizedClientService,
        OAuth2AuthorizedClientService,
      ],
      factoryMethodName: 'tabAuthorizedClientService',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.tabAuthorizedClientService', [
          _OnWeb(),
          _OnSpaMode(),
          _OnClientRegistrations(),
          ConditionalOnMissingBean(OAuth2AuthorizedClientService),
        ]),
      ],
      create: (r) => TabOAuth2AuthorizedClientService(
        r.dependency<ClientRegistrationRepository>(),
      ),
    ),
    BeanDefinition<OAuth2AuthorizedClientService>(
      name: 'authorizedClientService',
      factoryMethodName: 'authorizedClientService',
      types: const [
        OAuth2AuthorizedClientService,
        SecretStoreOAuth2AuthorizedClientService,
      ],
      source: _source,
      conditions: const [
        ConditionGroup('$_source.authorizedClientService', [
          _OnClientRegistrations(),
          ConditionalOnMissingBean(OAuth2AuthorizedClientService),
        ]),
      ],
      create: (r) => SecretStoreOAuth2AuthorizedClientService(
        r.dependency<SecretStore>(),
        r.dependency<ClientRegistrationRepository>(),
        dPoPKey: r.optionalDependency<DPoPKey>(),
      ),
    ),
    BeanDefinition<PlatformAppleIdSignIn>(
      name: 'appleIdSignIn',
      types: const [PlatformAppleIdSignIn, AppleIdSignIn],
      factoryMethodName: 'appleIdSignIn',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.appleIdSignIn', [
          _OnAppleIdSheet(),
          _OnClientRegistrations(),
          ConditionalOnMissingBean(AppleIdSignIn),
        ]),
      ],
      create: (_) => const PlatformAppleIdSignIn(),
    ),
    BeanDefinition<NativeOAuth2LoginService>(
      name: 'oauth2LoginService',
      types: const [NativeOAuth2LoginService, OAuth2LoginService],
      factoryMethodName: 'oauth2LoginService',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.oauth2LoginService', [
          _NotOnWeb(),
          _OnClientRegistrations(),
          ConditionalOnMissingBean(OAuth2LoginService),
        ]),
      ],
      create: (r) => NativeOAuth2LoginService(
        clientRegistrationRepository: r
            .dependency<ClientRegistrationRepository>(),
        authorizedClientService: r.dependency<OAuth2AuthorizedClientService>(),
        secretStore: r.dependency<SecretStore>(),
        accessTokenResponseClient: r
            .dependency<
              OAuth2AccessTokenResponseClient<
                OAuth2AuthorizationCodeGrantRequest
              >
            >(),
        userService: r
            .dependency<OAuth2UserService<OAuth2UserRequest, OAuth2User>>(),
        oidcUserService: r
            .dependency<OAuth2UserService<OidcUserRequest, OidcUser>>(),
        authorizationWindow: r.optionalDependency<AuthorizationWindow>(),
        authorizedClientManager: r
            .optionalDependency<OAuth2AuthorizedClientManager>(),
        revocationClient: OAuth2TokenRevocationClient(
          r.dependency<HttpTransport>(),
        ),
        dPoPKey: r.optionalDependency<PlatformDPoPKey>(),
        appleIdSignIn: r.optionalDependency<AppleIdSignIn>(),
        nativeSignIn: NativeSignIn.of(r.dependency<Environment>()),
        nativeIdTokenDecoder: JwkSetOidcIdTokenDecoder(
          r.dependency<HttpTransport>(),
        ),
        idTokenDecoder: r.dependency<OidcIdTokenDecoder>(),
        authoritiesMapper:
            r.optionalDependency<GrantedAuthoritiesMapper>() ??
            const NullAuthoritiesMapper(),
        eventPublisher: r.dependency<ApplicationEventPublisher>(),
      ),
    ),
    BeanDefinition<FlutterWebSecurityProperties>(
      name: 'flutterWebSecurityProperties',
      factoryMethodName: 'flutterWebSecurityProperties',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.flutterWebSecurityProperties', [_OnWeb()]),
      ],
      // Throws for unusable values: the start fails.
      create: (r) =>
          FlutterWebSecurityProperties.bind(r.dependency<Environment>()),
    ),
    BeanDefinition<SpaBrowserPage>(
      name: 'spaBrowserPage',
      types: const [SpaBrowserPage, BrowserPage],
      factoryMethodName: 'spaBrowserPage',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.spaBrowserPage', [
          _OnWeb(),
          _OnSpaMode(),
          ConditionalOnMissingBean(SpaBrowserPage),
        ]),
      ],
      create: (_) => SpaBrowserPage(),
    ),
    BeanDefinition<BrowserPage>(
      name: 'browserPage',
      factoryMethodName: 'browserPage',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.browserPage', [
          _OnWeb(),
          _OnServerMode(),
          ConditionalOnMissingBean(BrowserPage),
        ]),
      ],
      create: (_) => BrowserPage(),
    ),
    BeanDefinition<CsrfCookieHttpTransport>(
      name: 'httpTransport',
      types: const [CsrfCookieHttpTransport, HttpTransport],
      factoryMethodName: 'httpTransport',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.httpTransport', [
          _OnWeb(),
          _OnServerMode(),
          ConditionalOnMissingBean(HttpTransport),
        ]),
      ],
      create: (r) {
        final properties = r.dependency<FlutterWebSecurityProperties>();
        final page = r.dependency<BrowserPage>();
        final location = page.location;
        final server = properties.server(location);
        final connectTimeout = FeignClientConfig.connectTimeout(
          r.dependency<Environment>(),
        );
        return CsrfCookieHttpTransport(
          // fetch sends cookies to the page's own origin by itself; a
          // server on another origin needs them asked for, for its
          // requests only (never to another API).
          properties.credentials(location) == FetchCredentials.include
              ? ServerCredentialsHttpTransport.forPage(
                  page: page,
                  server: server,
                  connectTimeout: connectTimeout,
                )
              : platformHttpTransport(connectTimeout: connectTimeout),
          page: page,
          server: server,
        );
      },
      destroyMethod: (transport) => transport.close(),
    ),
    BeanDefinition<ServerOAuth2LoginService>(
      name: 'serverOAuth2LoginService',
      types: const [ServerOAuth2LoginService, OAuth2LoginService],
      factoryMethodName: 'serverOAuth2LoginService',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.serverOAuth2LoginService', [
          _OnWeb(),
          _OnServerMode(),
          ConditionalOnMissingBean(OAuth2LoginService),
        ]),
      ],
      create: (r) => ServerOAuth2LoginService(
        transport: r.dependency<HttpTransport>(),
        page: r.dependency<BrowserPage>(),
        properties: r.dependency<FlutterWebSecurityProperties>(),
        eventPublisher: r.dependency<ApplicationEventPublisher>(),
      ),
    ),
    BeanDefinition<SpaOAuth2LoginService>(
      name: 'spaOAuth2LoginService',
      types: const [SpaOAuth2LoginService, OAuth2LoginService],
      factoryMethodName: 'spaOAuth2LoginService',
      source: _source,
      conditions: const [
        ConditionGroup('$_source.spaOAuth2LoginService', [
          _OnWeb(),
          _OnSpaMode(),
          ConditionalOnMissingBean(OAuth2LoginService),
        ]),
      ],
      create: (r) => SpaOAuth2LoginService(
        clientRegistrationRepository:
            r.optionalDependency<ClientRegistrationRepository>() ??
            (throw StateError(
              '${FlutterWebSecurityProperties.prefix}.mode=spa: the browser '
              'logs in by itself, with a registration of its own; set '
              'spring.security.oauth2.client.registration.<id>.* (a public '
              'client) and spring.security.oauth2.client.provider.<id>.*',
            )),
        authorizedClientService: r.dependency<OAuth2AuthorizedClientService>(),
        accessTokenResponseClient: r
            .dependency<
              OAuth2AccessTokenResponseClient<
                OAuth2AuthorizationCodeGrantRequest
              >
            >(),
        userService: r
            .dependency<OAuth2UserService<OAuth2UserRequest, OAuth2User>>(),
        oidcUserService: r
            .dependency<OAuth2UserService<OidcUserRequest, OidcUser>>(),
        page: r.dependency<SpaBrowserPage>(),
        properties: r.dependency<FlutterWebSecurityProperties>(),
        revocationClient: OAuth2TokenRevocationClient(
          r.dependency<HttpTransport>(),
        ),
        idTokenDecoder: r.dependency<OidcIdTokenDecoder>(),
        authoritiesMapper:
            r.optionalDependency<GrantedAuthoritiesMapper>() ??
            const NullAuthoritiesMapper(),
        dPoPKey: r.optionalDependency<DPoPKey>(),
        eventPublisher: r.dependency<ApplicationEventPublisher>(),
      ),
    ),
  ],
);
