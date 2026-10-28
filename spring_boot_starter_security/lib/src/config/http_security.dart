import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_security/src/jwt/jwt_decoder.dart';
import 'package:spring_boot_starter_security/src/web/access.dart';
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_security/src/web/csrf.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/filter_chain.dart';
import 'package:spring_boot_starter_security/src/web/headers.dart';
import 'package:spring_boot_starter_security/src/web/request_cache.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.config');

/// A function that configures one part of [HttpSecurity]; each part's
/// method takes one, such as `csrf((c) => c.disable())`.
///
/// Spring (Java): `Customizer`, the same lambda style.
typedef Customizer<T> = void Function(T configurer);

/// Whether a chain keeps logins in the HTTP session.
///
/// Browser applications log in once and stay logged in through the
/// session cookie ([ifRequired]). APIs whose clients send credentials or
/// a token with every request should use no session at all
/// ([stateless]): no cookie, nothing kept on the server.
///
/// Spring (Java): `SessionCreationPolicy` (here without `always` and
/// `never`).
enum SessionCreationPolicy {
  /// A session is created when needed, for example at a form login, and
  /// keeps the user logged in; the default.
  ifRequired,

  /// Security never uses a session: the user is kept for the current
  /// request only, no page is saved for after a login, and there is no
  /// session fixation handling. For APIs with Basic or bearer tokens.
  stateless,
}

/// The positions of the built-in filters in a chain, in the order they
/// run; [HttpSecurity.addFilterBefore], [HttpSecurity.addFilterAfter] and
/// [HttpSecurity.addFilterAt] place your filters relative to them.
///
/// A lower number runs first: the security context is loaded, headers and
/// CORS come next, then CSRF, logout and the login methods, then the
/// anonymous user, the error translation and finally the access rules.
///
/// Spring (Java): `FilterOrderRegistration`.
abstract final class SecurityFilterOrder {
  /// [SecurityContextHolderFilter]: loads the stored user.
  static const securityContextHolder = 100;

  /// [HeaderWriterFilter]: the security headers.
  static const headerWriter = 200;

  /// [CorsFilter]: answers CORS pre-flights.
  static const cors = 300;

  /// [CsrfFilter]: refuses state-changing requests without a token.
  static const csrf = 400;

  /// [LogoutFilter]: `POST /logout`.
  static const logout = 500;

  /// [UsernamePasswordAuthenticationFilter]: the form login.
  static const formLogin = 600;

  /// [DefaultLoginPageGeneratingFilter]: the generated login page.
  static const loginPage = 700;

  /// [DefaultLogoutPageGeneratingFilter]: the logout confirmation page.
  static const logoutPage = 800;

  /// [BearerTokenAuthenticationFilter]: bearer-token logins.
  static const bearerToken = 900;

  /// [BasicAuthenticationFilter]: HTTP Basic logins.
  static const basic = 1000;

  /// [SecurityContextHolderAwareRequestFilter]: `request.principal`.
  static const servletApi = 1100;

  /// [AnonymousAuthenticationFilter]: the anonymous user.
  static const anonymous = 1200;

  /// [ExceptionTranslationFilter]: turns security errors into 401 or
  /// 403.
  static const exceptionTranslation = 1300;

  /// [AuthorizationFilter]: the access rules, last.
  static const authorization = 1400;

  /// The position of the built-in filter class [type], or `null` for any
  /// other class, subclasses of built-in filters included.
  // The exact type: a subclass of a built-in filter is not that filter.
  // ignore: switch_on_type
  static int? of(Type type) => switch (type) {
    const (SecurityContextHolderFilter) => securityContextHolder,
    const (HeaderWriterFilter) => headerWriter,
    const (CorsFilter) => cors,
    const (CsrfFilter) => csrf,
    const (LogoutFilter) => logout,
    const (UsernamePasswordAuthenticationFilter) => formLogin,
    const (DefaultLoginPageGeneratingFilter) => loginPage,
    const (DefaultLogoutPageGeneratingFilter) => logoutPage,
    const (BearerTokenAuthenticationFilter) => bearerToken,
    const (BasicAuthenticationFilter) => basic,
    const (SecurityContextHolderAwareRequestFilter) => servletApi,
    const (AnonymousAuthenticationFilter) => anonymous,
    const (ExceptionTranslationFilter) => exceptionTranslation,
    const (AuthorizationFilter) => authorization,
    _ => null,
  };
}

/// The builder of a [SecurityFilterChain]: you say which requests need
/// which login and which rights, and [build] turns that into the filters.
///
/// Declare a `SecurityFilterChain` bean method that takes an
/// `HttpSecurity`; each such method gets a fresh one. Declaring one
/// replaces the starter's default chain.
///
/// ```dart
/// @Configuration()
/// class SecurityConfig {
///   @Bean()
///   SecurityFilterChain api(HttpSecurity http) => http
///       .authorizeHttpRequests((auth) => auth
///           .requestMatchers('/api/admin/**').hasRole('ADMIN')
///           // Anyone may read the catalogue.
///           .requestMatchersFor(HttpMethod.get, ['/api/books/**'])
///           .permitAll()
///           .anyRequest().authenticated())
///       .httpBasic()
///       .build();
/// }
/// ```
///
/// On by default, as in Spring: CSRF protection, security headers, the
/// user kept in the session, the page saved for after a login, anonymous
/// users, logout at `POST /logout` and the translation of security errors
/// into 401 and 403; here CORS with the router's configuration too. Login
/// methods (`httpBasic`, `formLogin`, `oauth2ResourceServer`) and the
/// access rules (`authorizeHttpRequests`) are added by calling them.
/// Without `authorizeHttpRequests` the chain lets every request through
/// (a warning is logged); with it, a request no rule matches is denied.
///
/// Spring (Java):
/// ```java
/// @Bean
/// SecurityFilterChain api(HttpSecurity http) throws Exception {
///   return http
///       .authorizeHttpRequests(auth -> auth
///           .requestMatchers("/api/admin/**").hasRole("ADMIN")
///           .requestMatchers(HttpMethod.GET, "/api/books/**").permitAll()
///           .anyRequest().authenticated())
///       .httpBasic(Customizer.withDefaults())
///       .build();
/// }
/// ```
final class HttpSecurity {
  /// A builder taking the application's optional beans from
  /// [beanFactory]; [contextPath] is `server.servlet.context-path`.
  ///
  /// The starter creates it for each `SecurityFilterChain` bean method;
  /// create one yourself only in tests.
  HttpSecurity(this.beanFactory, {this.contextPath = ''});

  /// Where the optional beans come from: users, password encoder, JWT
  /// decoder, CORS configuration, role hierarchy, event publishers. A type
  /// with no bean, or with more than one, counts as absent.
  final BeanFactory? beanFactory;

  /// The application's context path, put in front of the redirects to the
  /// login page and after login or logout; `''` for none.
  final String contextPath;

  RequestMatcher _securityMatcher = AnyRequestMatcher.instance;
  AuthorizeHttpRequestsConfigurer? _authorize;
  final _mechanisms = <Object>[]; // in call order
  final _csrf = CsrfConfigurer._();
  final _cors = CorsConfigurer._();
  final _headers = HeadersConfigurer._();
  final _session = SessionManagementConfigurer._();
  final _exceptions = ExceptionHandlingConfigurer._();
  final _anonymous = AnonymousConfigurer._();
  final _logout = LogoutConfigurer._();
  final _requestCache = RequestCacheConfigurer._();
  final _context = SecurityContextConfigurer._();
  final _added = <(WebFilter, num)>[];
  AuthenticationManager? _authenticationManager;
  UserDetailsService? _userDetailsService;
  bool _built = false;

  // The application's bean, or null when there is none or more than one; a
  // bean that fails to be created fails the chain (and the startup), like
  // Spring, instead of being replaced by a default.
  T? _bean<T extends Object>() =>
      beanFactory?.getBeanProvider<T>().getIfUnique();

  List<T> _beans<T extends Object>() {
    final factory = beanFactory;
    return factory == null
        ? const []
        : factory.getBeanProvider<T>().orderedList();
  }

  /// Makes this chain handle only requests whose path matches [pattern]
  /// or one of the other patterns, router path patterns such as
  /// `/api/**`.
  ///
  /// Use it when the application has several chains, for example one for
  /// the API and one for the pages; order the beans with `@Order` so the
  /// chain without a security matcher comes last. Without it, the chain
  /// handles every request.
  HttpSecurity securityMatcher(
    String pattern, [
    String? pattern2,
    String? pattern3,
    String? pattern4,
  ]) {
    final patterns = [pattern, ?pattern2, ?pattern3, ?pattern4];
    _securityMatcher = patterns.length == 1
        ? PathPatternRequestMatcher(pattern)
        : OrRequestMatcher([
            for (final p in patterns) PathPatternRequestMatcher(p),
          ]);
    return this;
  }

  /// Makes this chain handle only requests [matcher] matches, for a test
  /// that is not a path pattern.
  HttpSecurity securityMatcherOf(RequestMatcher matcher) {
    _securityMatcher = matcher;
    return this;
  }

  /// Sets the access rules: which requests need which rights.
  ///
  /// The rules are tried in order and the first that matches decides, so
  /// put specific paths before general ones and end with `anyRequest()`.
  /// A request no rule matches is denied. [build] throws a [StateError]
  /// when [customizer] adds no rule.
  ///
  /// ```dart
  /// http.authorizeHttpRequests((auth) => auth
  ///     .requestMatchers('/', '/login', '/assets/**').permitAll()
  ///     .requestMatchers('/admin/**').hasRole('ADMIN')
  ///     .anyRequest().authenticated());
  /// ```
  HttpSecurity authorizeHttpRequests(
    Customizer<AuthorizeHttpRequestsConfigurer> customizer,
  ) {
    customizer(_authorize ??= AuthorizeHttpRequestsConfigurer._(this));
    return this;
  }

  /// Accepts HTTP Basic logins: the client sends its username and password
  /// in an `Authorization: Basic` header with every request.
  ///
  /// Programs that are not logged in get a 401 with a
  /// `WWW-Authenticate: Basic` challenge; scripts (`X-Requested-With:
  /// XMLHttpRequest`) get a plain 401, so no browser dialog appears. The
  /// passwords are checked against the application's users; [build] throws
  /// a [StateError] when there are none. Use it over HTTPS only.
  HttpSecurity httpBasic([Customizer<HttpBasicConfigurer>? customizer]) {
    final configurer =
        _mechanisms.whereType<HttpBasicConfigurer>().firstOrNull ??
        (HttpBasicConfigurer._()..let(_mechanisms.add));
    customizer?.call(configurer);
    return this;
  }

  /// Accepts logins through an HTML form: a login page, a `POST /login`
  /// that checks the password, and a session that keeps the user logged
  /// in.
  ///
  /// The page is generated unless [FormLoginConfigurer.loginPage] names
  /// yours. Browsers asking for a protected page are redirected to it, and
  /// come back to the page after the login. [build] throws a [StateError]
  /// when the application has no users.
  HttpSecurity formLogin([Customizer<FormLoginConfigurer>? customizer]) {
    final configurer =
        _mechanisms.whereType<FormLoginConfigurer>().firstOrNull ??
        (FormLoginConfigurer._()..let(_mechanisms.add));
    customizer?.call(configurer);
    return this;
  }

  /// Accepts `Authorization: Bearer` tokens, JWTs issued by an identity
  /// provider (Keycloak, Auth0, ...): the API is an OAuth 2.0 resource
  /// server.
  ///
  /// [customizer] must call `jwt()`; [build] throws a [StateError]
  /// otherwise, and when there is no `JwtDecoder`. Scopes become
  /// `SCOPE_x` authorities. Usually with a `stateless` session policy.
  ///
  /// ```dart
  /// http.oauth2ResourceServer((s) => s.jwt());
  /// ```
  HttpSecurity oauth2ResourceServer(
    Customizer<OAuth2ResourceServerConfigurer> customizer,
  ) {
    final configurer =
        _mechanisms.whereType<OAuth2ResourceServerConfigurer>().firstOrNull ??
        (OAuth2ResourceServerConfigurer._()..let(_mechanisms.add));
    customizer(configurer);
    return this;
  }

  /// Configures CSRF protection, which is on by default.
  ///
  /// Turn it off only for chains whose clients authenticate with headers
  /// (Basic, bearer tokens), never with cookies:
  /// `csrf((c) => c.disable())`.
  HttpSecurity csrf(Customizer<CsrfConfigurer> customizer) {
    customizer(_csrf);
    return this;
  }

  /// Configures CORS, which is on by default with the router's
  /// configuration (the `CorsConfigurationSource` bean and
  /// `@CrossOrigin`).
  HttpSecurity cors([Customizer<CorsConfigurer>? customizer]) {
    customizer?.call(_cors);
    return this;
  }

  /// Configures the security headers, which are on by default:
  /// `X-Content-Type-Options`, `X-XSS-Protection: 0`, no caching,
  /// `Strict-Transport-Security` on HTTPS, and `X-Frame-Options: DENY`.
  HttpSecurity headers(Customizer<HeadersConfigurer> customizer) {
    customizer(_headers);
    return this;
  }

  /// Configures how logins use the session: the creation policy and the
  /// session fixation protection.
  HttpSecurity sessionManagement(
    Customizer<SessionManagementConfigurer> customizer,
  ) {
    customizer(_session);
    return this;
  }

  /// Configures what clients get when they must log in first (the entry
  /// point) and when they are denied (the access denied handler), for
  /// every request of the chain.
  HttpSecurity exceptionHandling(
    Customizer<ExceptionHandlingConfigurer> customizer,
  ) {
    customizer(_exceptions);
    return this;
  }

  /// Configures anonymous users, which are on by default: a request
  /// without a login gets the `anonymousUser`.
  HttpSecurity anonymous(Customizer<AnonymousConfigurer> customizer) {
    customizer(_anonymous);
    return this;
  }

  /// Configures the logout, which is on by default at `POST /logout`.
  HttpSecurity logout(Customizer<LogoutConfigurer> customizer) {
    customizer(_logout);
    return this;
  }

  /// Configures where the page wanted before a login is saved: in the
  /// session by default, nowhere with a `stateless` policy.
  HttpSecurity requestCache(Customizer<RequestCacheConfigurer> customizer) {
    customizer(_requestCache);
    return this;
  }

  /// Configures where the logged-in user is kept between requests: the
  /// request and the session by default, the request only with a
  /// `stateless` policy.
  HttpSecurity securityContext(
    Customizer<SecurityContextConfigurer> customizer,
  ) {
    customizer(_context);
    return this;
  }

  /// Makes the chain's Basic and form logins check credentials with
  /// [manager], instead of the one built from the application's beans.
  HttpSecurity authenticationManager(AuthenticationManager manager) {
    _authenticationManager = manager;
    return this;
  }

  /// Makes the chain's Basic and form logins check passwords against
  /// [service], instead of the application's user beans; the
  /// `PasswordEncoder` bean (or the delegating encoder) checks them, and
  /// old hashes are not upgraded.
  HttpSecurity userDetailsService(UserDetailsService service) {
    _userDetailsService = service;
    return this;
  }

  /// Adds [filter] to the chain right before the built-in filter class
  /// [before], such as `BasicAuthenticationFilter`.
  ///
  /// Throws an [ArgumentError] when [before] is not a built-in filter
  /// class.
  ///
  /// ```dart
  /// // An API-key login, tried before Basic.
  /// http.addFilterBefore(ApiKeyFilter(manager), BasicAuthenticationFilter);
  /// ```
  HttpSecurity addFilterBefore(WebFilter filter, Type before) =>
      _addAt(filter, _orderOf(before) - 0.5);

  /// Adds [filter] to the chain right after the built-in filter class
  /// [after].
  ///
  /// Throws an [ArgumentError] when [after] is not a built-in filter
  /// class.
  HttpSecurity addFilterAfter(WebFilter filter, Type after) =>
      _addAt(filter, _orderOf(after) + 0.5);

  /// Adds [filter] at the position of the built-in filter class [at],
  /// right after it; the built-in filter stays.
  ///
  /// Throws an [ArgumentError] when [at] is not a built-in filter class.
  HttpSecurity addFilterAt(WebFilter filter, Type at) =>
      _addAt(filter, _orderOf(at) + 0.1);

  int _orderOf(Type type) =>
      SecurityFilterOrder.of(type) ??
      (throw ArgumentError('$type is not a built-in security filter'));

  HttpSecurity _addAt(WebFilter filter, num order) {
    _added.add((filter, order));
    return this;
  }

  /// Builds the chain from everything configured so far.
  ///
  /// Call it once, at the end of the bean method; a second call throws a
  /// [StateError]. It also throws a [StateError] when a login method has
  /// no way to check credentials, when the resource server has no
  /// `jwt()` or no decoder, and when `authorizeHttpRequests` added no
  /// rule.
  SecurityFilterChain build() {
    if (_built) {
      throw StateError('This HttpSecurity has already been built');
    }
    _built = true;
    final stateless = _session._policy == SessionCreationPolicy.stateless;
    final repository =
        _context._repository ??
        (stateless
            ? const RequestAttributeSecurityContextRepository()
            : DelegatingSecurityContextRepository(const [
                RequestAttributeSecurityContextRepository(),
                HttpSessionSecurityContextRepository(),
              ]));
    final requestCache =
        _requestCache._cache ??
        (stateless ? const NullRequestCache() : HttpSessionRequestCache());
    final eventPublisher = _bean<ApplicationEventPublisher>();
    final csrfRepository =
        _csrf._repository ?? const HttpSessionCsrfTokenRepository();
    final sessionStrategy = CompositeSessionAuthenticationStrategy([
      if (!stateless && _session._fixation)
        const ChangeSessionIdAuthenticationStrategy(),
      if (_csrf._enabled) CsrfAuthenticationStrategy(csrfRepository),
    ]);

    final filters = <(WebFilter, num)>[
      (
        SecurityContextHolderFilter(repository),
        SecurityFilterOrder.securityContextHolder,
      ),
    ];
    if (_headers._enabled) {
      filters.add((
        HeaderWriterFilter(_headers._writers()),
        SecurityFilterOrder.headerWriter,
      ));
    }
    if (_cors._enabled) {
      final source = _cors._source;
      final mapping = _bean<RequestMappingHandlerMapping>();
      filters.add((
        CorsFilter(
          source != null
              ? source.getCorsConfiguration
              : mapping != null
              ? mapping.corsConfigurationFor
              : (_) => null,
        ),
        SecurityFilterOrder.cors,
      ));
    }
    final accessDenied = <(RequestMatcher, AccessDeniedHandler)>[];
    if (_csrf._enabled) {
      filters.add((
        CsrfFilter(
          csrfRepository,
          requestHandler:
              _csrf._handler ?? const XorCsrfTokenRequestAttributeHandler(),
          requireCsrfProtectionMatcher: _csrf._ignoring.isEmpty
              ? const DefaultRequiresCsrfMatcher()
              : AndRequestMatcher([
                  const DefaultRequiresCsrfMatcher(),
                  NegatedRequestMatcher(OrRequestMatcher(_csrf._ignoring)),
                ]),
          accessDeniedHandler:
              _exceptions._accessDeniedHandler ??
              const AccessDeniedHandlerImpl(),
        ),
        SecurityFilterOrder.csrf,
      ));
    }

    final formLogin = _mechanisms.whereType<FormLoginConfigurer>().firstOrNull;

    if (_logout._enabled) {
      final logoutUrl = _logout._url;
      filters.add((
        LogoutFilter(
          [
            ..._logout._handlers,
            if (_logout._deleteCookies.isNotEmpty)
              CookieClearingLogoutHandler(
                _logout._deleteCookies,
                path: contextPath.isEmpty ? '/' : contextPath,
              ),
            if (_csrf._enabled) CsrfLogoutHandler(csrfRepository),
            SecurityContextLogoutHandler(
              invalidateHttpSession: _logout._invalidateHttpSession,
              securityContextRepository: repository,
            ),
          ],
          logoutUrl: logoutUrl,
          successHandler:
              _logout._successHandler ??
              SimpleUrlLogoutSuccessHandler(
                _logout._successUrl ??
                    '${formLogin?._loginPage ?? '/login'}?logout',
                contextPath: contextPath,
              ),
          methods: _csrf._enabled
              ? const {HttpMethod.post}
              : const {
                  HttpMethod.get,
                  HttpMethod.post,
                  HttpMethod.put,
                  HttpMethod.delete,
                },
          eventPublisher: eventPublisher,
        ),
        SecurityFilterOrder.logout,
      ));
    }

    // Login methods, and the entry points they register (in call order).
    final entryPoints = <(RequestMatcher, AuthenticationEntryPoint)>[];
    AuthenticationManager? manager;
    AuthenticationManager requireManager() => manager ??=
        _resolveManager() ??
        (throw StateError(
          'No AuthenticationManager for httpBasic/formLogin: declare a '
          'UserDetailsService, AuthenticationProvider or '
          'AuthenticationManager bean, or call '
          'http.userDetailsService(...) / http.authenticationManager(...)',
        ));
    for (final mechanism in _mechanisms) {
      switch (mechanism) {
        case final FormLoginConfigurer form:
          final loginPage = form._loginPage ?? '/login';
          final processing = form._processingUrl ?? loginPage;
          final entryPoint = LoginUrlAuthenticationEntryPoint(
            loginPage,
            contextPath: contextPath,
          );
          entryPoints.add((_browserMatcher, entryPoint));
          filters.add((
            UsernamePasswordAuthenticationFilter(
              requireManager(),
              loginProcessingUrl: processing,
              usernameParameter: form._usernameParameter,
              passwordParameter: form._passwordParameter,
              successHandler:
                  form._successHandler ??
                  SavedRequestAwareAuthenticationSuccessHandler(
                    requestCache: requestCache,
                    defaultTargetUrl: form._defaultSuccessUrl ?? '/',
                    alwaysUseDefaultTargetUrl: form._alwaysUseDefaultSuccessUrl,
                    contextPath: contextPath,
                  ),
              failureHandler:
                  form._failureHandler ??
                  SimpleUrlAuthenticationFailureHandler(
                    form._failureUrl ?? '$loginPage?error',
                    contextPath: contextPath,
                  ),
              sessionStrategy: sessionStrategy,
              securityContextRepository: repository,
              eventPublisher: eventPublisher,
            ),
            SecurityFilterOrder.formLogin,
          ));
          if (form._loginPage == null) {
            filters.add((
              DefaultLoginPageGeneratingFilter(
                loginProcessingUrl: processing,
                usernameParameter: form._usernameParameter,
                passwordParameter: form._passwordParameter,
                contextPath: contextPath,
              ),
              SecurityFilterOrder.loginPage,
            ));
            if (_logout._enabled) {
              filters.add((
                DefaultLogoutPageGeneratingFilter(
                  logoutUrl: _logout._url,
                  contextPath: contextPath,
                ),
                SecurityFilterOrder.logoutPage,
              ));
            }
          }
        case final HttpBasicConfigurer httpBasic:
          final challenge =
              httpBasic._entryPoint ??
              BasicAuthenticationEntryPoint(httpBasic._realmName);
          // Like Spring: scripts (XMLHttpRequest) get a plain 401, without
          // the challenge that makes a browser show its password dialog.
          final entryPoint = httpBasic._entryPoint == null
              ? DelegatingAuthenticationEntryPoint(const [
                  (_xhrMatcher, HttpStatusEntryPoint()),
                ], defaultEntryPoint: challenge)
              : challenge;
          entryPoints.add((_apiMatcher, entryPoint));
          filters.add((
            BasicAuthenticationFilter(
              requireManager(),
              authenticationEntryPoint: entryPoint,
            ),
            SecurityFilterOrder.basic,
          ));
        case final OAuth2ResourceServerConfigurer server:
          final entryPoint =
              server._entryPoint ?? const BearerTokenAuthenticationEntryPoint();
          entryPoints.add((_apiMatcher, entryPoint));
          accessDenied.add((
            const _BearerTokenRequestMatcher(),
            server._accessDeniedHandler ??
                const BearerTokenAccessDeniedHandler(),
          ));
          filters.add((
            BearerTokenAuthenticationFilter(
              server._authenticationManager(this),
              bearerTokenResolver: server._resolver,
              authenticationEntryPoint: entryPoint,
            ),
            SecurityFilterOrder.bearerToken,
          ));
      }
    }

    filters.add((
      const SecurityContextHolderAwareRequestFilter(),
      SecurityFilterOrder.servletApi,
    ));
    if (_anonymous._enabled) {
      filters.add((
        AnonymousAuthenticationFilter(),
        SecurityFilterOrder.anonymous,
      ));
    }
    final entryPoint =
        _exceptions._entryPoint ??
        switch (entryPoints) {
          [] => const Http403ForbiddenEntryPoint(),
          [(_, final only)] => only,
          [(_, final first), ...] => DelegatingAuthenticationEntryPoint(
            entryPoints,
            defaultEntryPoint: first,
          ),
        };
    filters.add((
      ExceptionTranslationFilter(
        entryPoint,
        accessDeniedHandler:
            _exceptions._accessDeniedHandler ??
            (accessDenied.isEmpty
                ? const AccessDeniedHandlerImpl()
                : DelegatingAccessDeniedHandler(accessDenied)),
        requestCache: requestCache,
      ),
      SecurityFilterOrder.exceptionTranslation,
    ));
    final authorize = _authorize;
    if (authorize != null) {
      filters.add((
        AuthorizationFilter(authorize._manager()),
        SecurityFilterOrder.authorization,
      ));
    } else {
      _log.warning(
        'A SecurityFilterChain without authorizeHttpRequests permits every '
        'request it matches ($_securityMatcher)',
      );
    }
    filters.addAll(_added);
    // A stable sort: filters of one order keep their insertion order.
    final indexed = filters.indexed.toList()
      ..sort((a, b) {
        final byOrder = a.$2.$2.compareTo(b.$2.$2);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return DefaultSecurityFilterChain(_securityMatcher, [
      for (final (_, (filter, _)) in indexed) filter,
    ]);
  }

  AuthenticationManager? _resolveManager() {
    final explicit = _authenticationManager;
    if (explicit != null) {
      return explicit;
    }
    final publisher = _bean<AuthenticationEventPublisher>();
    final users = _userDetailsService;
    if (users != null) {
      return ProviderManager([
        DaoAuthenticationProvider(
          users,
          passwordEncoder: _bean<PasswordEncoder>(),
        ),
      ], eventPublisher: publisher);
    }
    final bean = _bean<AuthenticationManager>();
    if (bean != null) {
      return bean;
    }
    final providers = _beans<AuthenticationProvider>();
    if (providers.isNotEmpty) {
      return ProviderManager(providers, eventPublisher: publisher);
    }
    final service = _bean<UserDetailsService>();
    if (service != null) {
      return ProviderManager([
        DaoAuthenticationProvider(
          service,
          passwordEncoder: _bean<PasswordEncoder>(),
          userDetailsPasswordService:
              _bean<UserDetailsPasswordService>() ??
              (service is UserDetailsPasswordService
                  ? service as UserDetailsPasswordService
                  : null),
        ),
      ], eventPublisher: publisher);
    }
    return null;
  }

  RoleHierarchy get _roleHierarchy =>
      _bean<RoleHierarchy>() ?? const NullRoleHierarchy();

  String get _rolePrefix =>
      _bean<GrantedAuthorityDefaults>()?.rolePrefix ?? 'ROLE_';
}

// Browsers asking for pages, like Spring's form login entry point matcher.
final _browserMatcher = AndRequestMatcher([
  const NegatedRequestMatcher(
    RequestHeaderRequestMatcher('X-Requested-With', 'XMLHttpRequest'),
  ),
  const MediaTypeRequestMatcher(
    ['application/xhtml+xml', 'image/*', 'text/html', 'text/plain'],
    ignoredMediaTypes: ['*/*'],
  ),
]);

// Programs (XMLHttpRequest, JSON and other non-HTML types, `*/*` exactly),
// like Spring's HTTP Basic and resource server entry point matchers.
final _apiMatcher = OrRequestMatcher([
  const RequestHeaderRequestMatcher('X-Requested-With', 'XMLHttpRequest'),
  AndRequestMatcher([
    const NegatedRequestMatcher(MediaTypeRequestMatcher(['text/html'])),
    const MediaTypeRequestMatcher(
      [
        'application/atom+xml',
        'application/x-www-form-urlencoded',
        'application/json',
        'application/octet-stream',
        'application/xml',
        'multipart/form-data',
        'text/xml',
      ],
      ignoredMediaTypes: ['*/*'],
    ),
  ]),
  const MediaTypeRequestMatcher(['*/*'], useEquals: true),
]);

const _xhrMatcher = RequestHeaderRequestMatcher(
  'X-Requested-With',
  'XMLHttpRequest',
);

final class _BearerTokenRequestMatcher extends SimpleRequestMatcher {
  const _BearerTokenRequestMatcher();

  @override
  bool matches(ServerHttpRequest request) =>
      (request.headers[HttpHeaders.authorizationHeader] ?? '')
          .toLowerCase()
          .startsWith('bearer ');
}

extension<T> on T {
  // Runs [action] with this (used to register a new configurer).
  void let(void Function(T) action) => action(this);
}

/// The list of access rules being built in
/// [HttpSecurity.authorizeHttpRequests].
///
/// Each rule starts with the requests it covers (`requestMatchers`,
/// `anyRequest`) and ends with what they need (`permitAll`, `hasRole`, ...
/// on [AuthorizedUrl]). Rules are tried in the order they are added.
///
/// Spring (Java): `AuthorizeHttpRequestsConfigurer`'s
/// `AuthorizationManagerRequestMatcherRegistry`.
final class AuthorizeHttpRequestsConfigurer {
  AuthorizeHttpRequestsConfigurer._(this._http);

  final HttpSecurity _http;
  final _rules =
      <(RequestMatcher, AuthorizationManager<RequestAuthorizationContext>)>[];
  bool _anyRequest = false;

  /// Starts a rule for requests whose path matches [pattern] or one of the
  /// other patterns (up to six), whatever the method.
  ///
  /// The patterns are the router's (`/api/**`, `/users/{id}`), matched on
  /// the path the router sees, so a rule covers exactly what the
  /// controllers under it serve. Paths are case-sensitive and a trailing
  /// slash counts: protect `/admin` and `/admin/**` when both exist.
  /// Throws a [StateError] after [anyRequest].
  AuthorizedUrl requestMatchers(
    String pattern, [
    String? pattern2,
    String? pattern3,
    String? pattern4,
    String? pattern5,
    String? pattern6,
  ]) => requestMatchersFor(null, [
    pattern,
    ?pattern2,
    ?pattern3,
    ?pattern4,
    ?pattern5,
    ?pattern6,
  ]);

  /// Starts a rule for requests with [method] (any method when `null`)
  /// whose path matches one of [patterns].
  ///
  /// Throws an [ArgumentError] when [patterns] is empty, and a
  /// [StateError] after [anyRequest].
  AuthorizedUrl requestMatchersFor(HttpMethod? method, List<String> patterns) {
    if (patterns.isEmpty) {
      throw ArgumentError('requestMatchers needs at least one pattern');
    }
    return requestMatchersOf([
      for (final pattern in patterns)
        PathPatternRequestMatcher(pattern, method: method),
    ]);
  }

  /// Starts a rule for the requests any of [matchers] match, for tests
  /// that are not path patterns.
  ///
  /// Throws a [StateError] after [anyRequest].
  AuthorizedUrl requestMatchersOf(List<RequestMatcher> matchers) {
    if (_anyRequest) {
      throw StateError("Can't configure requestMatchers after anyRequest");
    }
    return AuthorizedUrl._(
      this,
      matchers.length == 1 ? matchers.single : OrRequestMatcher(matchers),
    );
  }

  /// Starts the rule for every request no earlier rule matched; it must
  /// be the last rule.
  ///
  /// Throws a [StateError] when called twice.
  AuthorizedUrl anyRequest() {
    if (_anyRequest) {
      throw StateError("Can't configure anyRequest after itself");
    }
    _anyRequest = true;
    return AuthorizedUrl._(this, AnyRequestMatcher.instance);
  }

  AuthorizeHttpRequestsConfigurer _add(
    RequestMatcher matcher,
    AuthorizationManager<RequestAuthorizationContext> manager,
  ) {
    _rules.add((matcher, manager));
    return this;
  }

  RequestMatcherDelegatingAuthorizationManager _manager() {
    if (_rules.isEmpty) {
      throw StateError(
        'At least one mapping is required (for example, '
        'anyRequest().authenticated())',
      );
    }
    return RequestMatcherDelegatingAuthorizationManager(_rules);
  }
}

/// The second half of an access rule: what the requests matched by the
/// first half need. Each method ends the rule and returns the list, to
/// start the next one.
///
/// Role and authority checks use the `RoleHierarchy` bean, and `hasRole`
/// the prefix of the `GrantedAuthorityDefaults` bean (`ROLE_` without
/// one).
///
/// Spring (Java): `AuthorizeHttpRequestsConfigurer.AuthorizedUrl`.
final class AuthorizedUrl {
  AuthorizedUrl._(this._registry, this._matcher);

  final AuthorizeHttpRequestsConfigurer _registry;
  final RequestMatcher _matcher;

  AuthorizeHttpRequestsConfigurer _with(
    AuthorizationManager<RequestAuthorizationContext> manager,
  ) => _registry._add(_matcher, manager);

  RoleHierarchy get _hierarchy => _registry._http._roleHierarchy;

  /// Lets everyone through, logged in or not: public pages, the login
  /// page, static assets.
  AuthorizeHttpRequestsConfigurer permitAll() =>
      _with(const SingleResultAuthorizationManager.permitAll());

  /// Denies everyone, even logged-in users.
  AuthorizeHttpRequestsConfigurer denyAll() =>
      _with(const SingleResultAuthorizationManager.denyAll());

  /// Lets through users who logged in; anonymous ones are asked to log
  /// in.
  AuthorizeHttpRequestsConfigurer authenticated() =>
      _with(const AuthenticatedAuthorizationManager.authenticated());

  /// Lets through users who logged in during this session, not through
  /// "remember me"; here the same as [authenticated].
  AuthorizeHttpRequestsConfigurer fullyAuthenticated() =>
      _with(const AuthenticatedAuthorizationManager.fullyAuthenticated());

  /// Lets through only users who have not logged in, for pages such as a
  /// sign-up form; logged-in users get 403.
  AuthorizeHttpRequestsConfigurer anonymous() =>
      _with(const AuthenticatedAuthorizationManager.anonymous());

  /// Lets through users with the role [role]: `hasRole('ADMIN')` needs
  /// the authority `ROLE_ADMIN`.
  ///
  /// Throws an [ArgumentError] when [role] already starts with the
  /// prefix.
  AuthorizeHttpRequestsConfigurer hasRole(String role) => _with(
    AuthorityAuthorizationManager.hasRole(
      role,
      rolePrefix: _registry._http._rolePrefix,
      roleHierarchy: _hierarchy,
    ),
  );

  /// Lets through users with one of [roles], each written without the
  /// prefix.
  ///
  /// Throws an [ArgumentError] when a role already starts with the
  /// prefix.
  AuthorizeHttpRequestsConfigurer hasAnyRole(List<String> roles) => _with(
    AuthorityAuthorizationManager.hasAnyRole(
      roles,
      rolePrefix: _registry._http._rolePrefix,
      roleHierarchy: _hierarchy,
    ),
  );

  /// Lets through users with [authority], written in full (`SCOPE_read`,
  /// `ROLE_ADMIN`).
  AuthorizeHttpRequestsConfigurer hasAuthority(String authority) => _with(
    AuthorityAuthorizationManager.hasAuthority(
      authority,
      roleHierarchy: _hierarchy,
    ),
  );

  /// Lets through users with one of [authorities], written in full.
  AuthorizeHttpRequestsConfigurer hasAnyAuthority(List<String> authorities) =>
      _with(
        AuthorityAuthorizationManager.hasAnyAuthority(
          authorities,
          roleHierarchy: _hierarchy,
        ),
      );

  /// Lets [manager] decide, for rules roles cannot express.
  ///
  /// It receives the request and the path variables of the rule's
  /// pattern: for `/users/{id}`, `context.variables['id']`. An abstention
  /// (`null`) denies.
  AuthorizeHttpRequestsConfigurer access(
    AuthorizationManager<RequestAuthorizationContext> manager,
  ) => _with(manager);
}

/// The settings of HTTP Basic logins, in [HttpSecurity.httpBasic].
///
/// Spring (Java): `HttpBasicConfigurer`.
final class HttpBasicConfigurer {
  HttpBasicConfigurer._();

  String _realmName = 'Realm';
  AuthenticationEntryPoint? _entryPoint;

  /// Sets the realm named in the `WWW-Authenticate` challenge, `Realm` by
  /// default; browsers may show it in their password dialog.
  HttpBasicConfigurer realmName(String realm) {
    _realmName = realm;
    return this;
  }

  /// Sets what clients get when their Basic credentials are wrong or
  /// missing, instead of the 401 challenge (scripts then get it too).
  HttpBasicConfigurer authenticationEntryPoint(
    AuthenticationEntryPoint entryPoint,
  ) {
    _entryPoint = entryPoint;
    return this;
  }
}

/// The settings of form logins, in [HttpSecurity.formLogin].
///
/// ```dart
/// http.formLogin((f) => f
///     .loginPage('/sign-in')
///     .defaultSuccessUrl('/dashboard'));
/// ```
///
/// Spring (Java): `FormLoginConfigurer`.
final class FormLoginConfigurer {
  FormLoginConfigurer._();

  String? _loginPage;
  String? _processingUrl;
  String _usernameParameter = 'username';
  String _passwordParameter = 'password';
  String? _defaultSuccessUrl;
  bool _alwaysUseDefaultSuccessUrl = false;
  String? _failureUrl;
  AuthenticationSuccessHandler? _successHandler;
  AuthenticationFailureHandler? _failureHandler;

  /// Uses your own login page at [url] instead of the generated one.
  ///
  /// Serve it from a controller and let everyone reach it
  /// (`requestMatchers('/sign-in').permitAll()`). The form posts to the
  /// same path unless [loginProcessingUrl] says otherwise, with the
  /// fields `username`, `password` and the CSRF token.
  FormLoginConfigurer loginPage(String url) {
    _loginPage = url;
    return this;
  }

  /// Sets the path the form posts to; the login page's path by default.
  FormLoginConfigurer loginProcessingUrl(String url) {
    _processingUrl = url;
    return this;
  }

  /// Sets the name of the username field, `username` by default.
  FormLoginConfigurer usernameParameter(String name) {
    _usernameParameter = name;
    return this;
  }

  /// Sets the name of the password field, `password` by default.
  FormLoginConfigurer passwordParameter(String name) {
    _passwordParameter = name;
    return this;
  }

  /// Sets where the browser goes after a login when no page was saved
  /// before it, `/` by default; with [alwaysUse], in every case.
  FormLoginConfigurer defaultSuccessUrl(String url, {bool alwaysUse = false}) {
    _defaultSuccessUrl = url;
    _alwaysUseDefaultSuccessUrl = alwaysUse;
    return this;
  }

  /// Sets where the browser goes after a failed login; the login page
  /// with `?error` by default.
  FormLoginConfigurer failureUrl(String url) {
    _failureUrl = url;
    return this;
  }

  /// Answers successful logins with [handler] instead of a redirect, for
  /// example with JSON for a script.
  FormLoginConfigurer successHandler(AuthenticationSuccessHandler handler) {
    _successHandler = handler;
    return this;
  }

  /// Answers failed logins with [handler] instead of a redirect.
  FormLoginConfigurer failureHandler(AuthenticationFailureHandler handler) {
    _failureHandler = handler;
    return this;
  }
}

/// The settings of bearer-token logins, in
/// [HttpSecurity.oauth2ResourceServer].
///
/// Spring (Java): `OAuth2ResourceServerConfigurer`.
final class OAuth2ResourceServerConfigurer {
  OAuth2ResourceServerConfigurer._();

  JwtConfigurer? _jwt;
  AuthenticationEntryPoint? _entryPoint;
  AccessDeniedHandler? _accessDeniedHandler;
  DefaultBearerTokenResolver _resolver = const DefaultBearerTokenResolver();

  /// Accepts JWT bearer tokens; required. They are checked by the
  /// `JwtDecoder` bean unless [customizer] sets a decoder.
  OAuth2ResourceServerConfigurer jwt([Customizer<JwtConfigurer>? customizer]) {
    customizer?.call(_jwt ??= JwtConfigurer._());
    _jwt ??= JwtConfigurer._();
    return this;
  }

  /// Sets what clients without a valid token get, instead of the 401 with
  /// `WWW-Authenticate: Bearer`.
  OAuth2ResourceServerConfigurer authenticationEntryPoint(
    AuthenticationEntryPoint entryPoint,
  ) {
    _entryPoint = entryPoint;
    return this;
  }

  /// Sets what token holders get when they are denied, instead of the 403
  /// with `error="insufficient_scope"`.
  OAuth2ResourceServerConfigurer accessDeniedHandler(
    AccessDeniedHandler handler,
  ) {
    _accessDeniedHandler = handler;
    return this;
  }

  /// Sets how the token is found in the request, for example to also read
  /// the `access_token` query parameter.
  OAuth2ResourceServerConfigurer bearerTokenResolver(
    DefaultBearerTokenResolver resolver,
  ) {
    _resolver = resolver;
    return this;
  }

  AuthenticationManager _authenticationManager(HttpSecurity http) {
    final jwt = _jwt;
    if (jwt == null) {
      throw StateError('oauth2ResourceServer needs jwt()');
    }
    final manager = jwt._manager;
    if (manager != null) {
      return manager;
    }
    final decoder =
        jwt._decoder ??
        http._bean<JwtDecoder>() ??
        (throw StateError(
          'oauth2ResourceServer.jwt() needs a JwtDecoder: declare a bean, set '
          'spring.security.oauth2.resourceserver.jwt.issuer-uri or '
          'jwk-set-uri, or call jwt((jwt) => jwt.decoder(...))',
        ));
    return ProviderManager([
      JwtAuthenticationProvider(
        decoder,
        converter:
            jwt._converter ??
            http._bean<JwtAuthenticationConverter>() ??
            const JwtAuthenticationConverter(),
      ),
    ], eventPublisher: http._bean<AuthenticationEventPublisher>());
  }
}

/// The JWT settings of bearer-token logins, in
/// `oauth2ResourceServer((s) => s.jwt((j) => ...))`.
///
/// Spring (Java): `OAuth2ResourceServerConfigurer.JwtConfigurer`.
final class JwtConfigurer {
  JwtConfigurer._();

  JwtDecoder? _decoder;
  JwtAuthenticationConverter? _converter;
  AuthenticationManager? _manager;

  /// Checks tokens with [decoder] instead of the `JwtDecoder` bean.
  JwtConfigurer decoder(JwtDecoder decoder) {
    _decoder = decoder;
    return this;
  }

  /// Turns verified tokens into users with [converter] (which claims give
  /// the name and the authorities), instead of the
  /// `JwtAuthenticationConverter` bean.
  JwtConfigurer jwtAuthenticationConverter(
    JwtAuthenticationConverter converter,
  ) {
    _converter = converter;
    return this;
  }

  /// Checks bearer tokens with [manager] alone; the decoder and converter
  /// are then not used.
  JwtConfigurer authenticationManager(AuthenticationManager manager) {
    _manager = manager;
    return this;
  }
}

/// The settings of CSRF protection, in [HttpSecurity.csrf].
///
/// Spring (Java): `CsrfConfigurer`.
final class CsrfConfigurer {
  CsrfConfigurer._();

  bool _enabled = true;
  CsrfTokenRepository? _repository;
  CsrfTokenRequestHandler? _handler;
  final _ignoring = <RequestMatcher>[];

  /// Turns CSRF protection off.
  ///
  /// Only for chains whose clients send their credentials in headers
  /// (Basic, bearer tokens), never in cookies: a browser session without
  /// CSRF protection can be used by any web page the user visits. It
  /// also lets `GET /logout` log out.
  void disable() => _enabled = false;

  /// Keeps the tokens in [repository] instead of the session.
  ///
  /// For single-page apps, use
  /// `CookieCsrfTokenRepository.withHttpOnlyFalse()` together with
  /// `csrfTokenRequestHandler(const CsrfTokenRequestAttributeHandler())`,
  /// so the script can send back the raw cookie value.
  CsrfConfigurer csrfTokenRepository(CsrfTokenRepository repository) {
    _repository = repository;
    return this;
  }

  /// Sets how tokens are handed to pages and read from requests; masked
  /// ([XorCsrfTokenRequestAttributeHandler]) by default.
  CsrfConfigurer csrfTokenRequestHandler(CsrfTokenRequestHandler handler) {
    _handler = handler;
    return this;
  }

  /// Exempts requests whose path matches [pattern] (or the others, up to
  /// three) from the CSRF check, for example a webhook that a third party
  /// posts to. Can be called several times.
  CsrfConfigurer ignoringRequestMatchers(
    String pattern, [
    String? pattern2,
    String? pattern3,
  ]) {
    _ignoring.addAll([
      for (final p in [pattern, ?pattern2, ?pattern3])
        PathPatternRequestMatcher(p),
    ]);
    return this;
  }
}

/// The settings of CORS handling, in [HttpSecurity.cors].
///
/// Spring (Java): `CorsConfigurer`; there CORS is off until `.cors()`.
final class CorsConfigurer {
  CorsConfigurer._();

  bool _enabled = true;
  CorsConfigurationSource? _source;

  /// Turns CORS handling in the chain off: pre-flight requests then reach
  /// the access rules, which usually refuse them.
  void disable() => _enabled = false;

  /// Takes the CORS rules from [source] instead of the router's
  /// configuration (the `CorsConfigurationSource` bean and
  /// `@CrossOrigin`).
  CorsConfigurer configurationSource(CorsConfigurationSource source) {
    _source = source;
    return this;
  }
}

/// The settings of the security headers, in [HttpSecurity.headers].
///
/// ```dart
/// // The app frames its own pages, and has a strict content policy.
/// http.headers((h) => h
///     .frameOptions(XFrameOptionsMode.sameOrigin)
///     .contentSecurityPolicy("default-src 'self'"));
/// ```
///
/// Spring (Java): `HeadersConfigurer`.
final class HeadersConfigurer {
  HeadersConfigurer._();

  bool _enabled = true;
  bool _defaults = true;
  XFrameOptionsMode? _frame = XFrameOptionsMode.deny;
  HstsHeaderWriter? _hsts = const HstsHeaderWriter();
  bool _contentTypeOptions = true;
  bool _xss = true;
  bool _cacheControl = true;
  String? _csp;
  String? _referrerPolicy;
  final _extra = <HeaderWriter>[];

  /// Sends no security headers at all.
  void disable() => _enabled = false;

  /// Drops the default headers: no `X-Content-Type-Options`,
  /// `X-XSS-Protection`, cache headers, HSTS or `X-Frame-Options`.
  ///
  /// Only [contentSecurityPolicy], [referrerPolicy] and [addHeaderWriter]
  /// still add headers: once the defaults are off, [frameOptions],
  /// [httpStrictTransportSecurity], [contentTypeOptions], [xssProtection]
  /// and [cacheControl] have no effect (unlike Spring).
  HeadersConfigurer defaultsDisabled() {
    _defaults = false;
    return this;
  }

  /// Sets `X-Frame-Options` to [mode], `DENY` by default; `null` does not
  /// send it.
  HeadersConfigurer frameOptions(XFrameOptionsMode? mode) {
    _frame = mode;
    return this;
  }

  /// Sets the `Strict-Transport-Security` header with [writer] (one year,
  /// subdomains included, by default); `null` does not send it.
  HeadersConfigurer httpStrictTransportSecurity(HstsHeaderWriter? writer) {
    _hsts = writer;
    return this;
  }

  /// Whether `X-Content-Type-Options: nosniff` is sent (by default), which
  /// stops browsers from guessing a response's type.
  HeadersConfigurer contentTypeOptions({required bool enabled}) {
    _contentTypeOptions = enabled;
    return this;
  }

  /// Whether `X-XSS-Protection: 0` is sent (by default), which turns off
  /// the old browser filters that could be abused.
  HeadersConfigurer xssProtection({required bool enabled}) {
    _xss = enabled;
    return this;
  }

  /// Whether the headers that forbid caching are sent (by default); turn
  /// them off for a chain serving only public, cacheable content.
  HeadersConfigurer cacheControl({required bool enabled}) {
    _cacheControl = enabled;
    return this;
  }

  /// Sends `Content-Security-Policy: <policy>`, which limits where a page
  /// may load scripts and other content from; not sent by default.
  HeadersConfigurer contentSecurityPolicy(String policy) {
    _csp = policy;
    return this;
  }

  /// Sends `Referrer-Policy: <policy>`; not sent by default.
  HeadersConfigurer referrerPolicy(String policy) {
    _referrerPolicy = policy;
    return this;
  }

  /// Adds [writer], for a header of your own.
  HeadersConfigurer addHeaderWriter(HeaderWriter writer) {
    _extra.add(writer);
    return this;
  }

  List<HeaderWriter> _writers() => [
    if (_defaults) ...[
      if (_contentTypeOptions)
        const StaticHeadersWriter('X-Content-Type-Options', 'nosniff'),
      if (_xss) const StaticHeadersWriter('X-XSS-Protection', '0'),
      if (_cacheControl) const CacheControlHeadersWriter(),
      ?_hsts,
      if (_frame case final mode?)
        StaticHeadersWriter('X-Frame-Options', mode.value),
    ],
    if (_csp case final policy?)
      StaticHeadersWriter('Content-Security-Policy', policy),
    if (_referrerPolicy case final policy?)
      StaticHeadersWriter('Referrer-Policy', policy),
    ..._extra,
  ];
}

/// The settings of how logins use the session, in
/// [HttpSecurity.sessionManagement].
///
/// ```dart
/// // An API: no session, every request carries its token.
/// http.sessionManagement(
///   (s) => s.sessionCreationPolicy(SessionCreationPolicy.stateless),
/// );
/// ```
///
/// Spring (Java): `SessionManagementConfigurer`.
final class SessionManagementConfigurer {
  SessionManagementConfigurer._();

  SessionCreationPolicy _policy = SessionCreationPolicy.ifRequired;
  bool _fixation = true;

  /// Sets whether logins are kept in the session;
  /// [SessionCreationPolicy.ifRequired] by default.
  SessionManagementConfigurer sessionCreationPolicy(
    SessionCreationPolicy policy,
  ) {
    _policy = policy;
    return this;
  }

  /// Whether a login gives the session a new id; on by default.
  ///
  /// Switching it off allows session fixation: an attacker who planted a
  /// session id before the login could use it afterwards.
  SessionManagementConfigurer sessionFixation({required bool changeSessionId}) {
    _fixation = changeSessionId;
    return this;
  }
}

/// The settings of what clients get on security errors, in
/// [HttpSecurity.exceptionHandling].
///
/// Spring (Java): `ExceptionHandlingConfigurer`.
final class ExceptionHandlingConfigurer {
  ExceptionHandlingConfigurer._();

  AuthenticationEntryPoint? _entryPoint;
  AccessDeniedHandler? _accessDeniedHandler;

  /// Answers every request that must log in first with [entryPoint],
  /// instead of the login methods' own (redirect, Basic or Bearer
  /// challenge).
  ExceptionHandlingConfigurer authenticationEntryPoint(
    AuthenticationEntryPoint entryPoint,
  ) {
    _entryPoint = entryPoint;
    return this;
  }

  /// Answers logged-in users who are denied, and refused CSRF checks,
  /// with [handler] instead of a plain 403.
  ExceptionHandlingConfigurer accessDeniedHandler(AccessDeniedHandler handler) {
    _accessDeniedHandler = handler;
    return this;
  }
}

/// The settings of anonymous users, in [HttpSecurity.anonymous].
///
/// Spring (Java): `AnonymousConfigurer`.
final class AnonymousConfigurer {
  AnonymousConfigurer._();

  bool _enabled = true;

  /// Turns anonymous users off: requests without credentials then have no
  /// authentication at all, so `isAnonymous()` and `anonymous()` never
  /// match and secured methods fail with
  /// `AuthenticationCredentialsNotFoundException`.
  void disable() => _enabled = false;
}

/// The settings of the logout, in [HttpSecurity.logout].
///
/// ```dart
/// // A single-page app: a 204 instead of a redirect, and the cookie gone.
/// http.logout((l) => l
///     .logoutSuccessHandler(
///         const HttpStatusReturningLogoutSuccessHandler(HttpStatus.noContent))
///     .deleteCookies('JSESSIONID'));
/// ```
///
/// Spring (Java): `LogoutConfigurer`.
final class LogoutConfigurer {
  LogoutConfigurer._();

  bool _enabled = true;
  String _url = '/logout';
  String? _successUrl;
  LogoutSuccessHandler? _successHandler;
  bool _invalidateHttpSession = true;
  final _deleteCookies = <String>[];
  final _handlers = <LogoutHandler>[];

  /// Removes the logout endpoint.
  void disable() => _enabled = false;

  /// Sets the logout path, `/logout` by default.
  LogoutConfigurer logoutUrl(String url) {
    _url = url;
    return this;
  }

  /// Sets where the browser goes after the logout; the login page with
  /// `?logout` by default.
  LogoutConfigurer logoutSuccessUrl(String url) {
    _successUrl = url;
    return this;
  }

  /// Answers logouts with [handler] instead of a redirect.
  LogoutConfigurer logoutSuccessHandler(LogoutSuccessHandler handler) {
    _successHandler = handler;
    return this;
  }

  /// Whether the logout ends the session, with everything stored in it;
  /// `true` by default.
  LogoutConfigurer invalidateHttpSession({required bool invalidate}) {
    _invalidateHttpSession = invalidate;
    return this;
  }

  /// Expires the cookies [name] (and up to two more) at logout, such as
  /// the session cookie `JSESSIONID`.
  LogoutConfigurer deleteCookies(String name, [String? name2, String? name3]) {
    _deleteCookies.addAll([name, ?name2, ?name3]);
    return this;
  }

  /// Adds [handler], run at logout before the built-in ones.
  LogoutConfigurer addLogoutHandler(LogoutHandler handler) {
    _handlers.add(handler);
    return this;
  }
}

/// The settings of where the page wanted before a login is saved, in
/// [HttpSecurity.requestCache].
///
/// Spring (Java): `RequestCacheConfigurer`.
final class RequestCacheConfigurer {
  RequestCacheConfigurer._();

  RequestCache? _cache;

  /// Saves the wanted page in [cache]; `const NullRequestCache()` saves
  /// nothing, so a login always goes to the default page.
  RequestCacheConfigurer requestCache(RequestCache cache) {
    _cache = cache;
    return this;
  }
}

/// The settings of where the logged-in user is kept between requests, in
/// [HttpSecurity.securityContext].
///
/// Spring (Java): `SecurityContextConfigurer`.
final class SecurityContextConfigurer {
  SecurityContextConfigurer._();

  SecurityContextRepository? _repository;

  /// Keeps the user in [repository]. Include a
  /// [RequestAttributeSecurityContextRepository] (in a
  /// [DelegatingSecurityContextRepository]) to keep the test helpers
  /// working.
  SecurityContextConfigurer securityContextRepository(
    SecurityContextRepository repository,
  ) {
    _repository = repository;
    return this;
  }
}
