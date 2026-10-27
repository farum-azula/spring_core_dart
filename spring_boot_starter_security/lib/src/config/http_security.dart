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

/// Configures one part of [HttpSecurity], like Spring's `Customizer`.
typedef Customizer<T> = void Function(T configurer);

/// How sessions are used, like Spring's `SessionCreationPolicy`.
enum SessionCreationPolicy {
  /// A session is created when needed (the default): form logins.
  ifRequired,

  /// No session is ever used by security (APIs with Basic or tokens): no
  /// context, saved request or fixation handling through sessions.
  stateless,
}

/// The order of the built-in filters in a chain, like Spring's
/// `FilterOrderRegistration`; [HttpSecurity.addFilterBefore] and
/// [HttpSecurity.addFilterAfter] place filters relative to them.
abstract final class SecurityFilterOrder {
  /// `SecurityContextHolderFilter`.
  static const securityContextHolder = 100;

  /// `HeaderWriterFilter`.
  static const headerWriter = 200;

  /// `CorsFilter`.
  static const cors = 300;

  /// `CsrfFilter`.
  static const csrf = 400;

  /// `LogoutFilter`.
  static const logout = 500;

  /// `UsernamePasswordAuthenticationFilter`.
  static const formLogin = 600;

  /// `DefaultLoginPageGeneratingFilter`.
  static const loginPage = 700;

  /// `DefaultLogoutPageGeneratingFilter`.
  static const logoutPage = 800;

  /// `BearerTokenAuthenticationFilter`.
  static const bearerToken = 900;

  /// `BasicAuthenticationFilter`.
  static const basic = 1000;

  /// `SecurityContextHolderAwareRequestFilter`.
  static const servletApi = 1100;

  /// `AnonymousAuthenticationFilter`.
  static const anonymous = 1200;

  /// `ExceptionTranslationFilter`.
  static const exceptionTranslation = 1300;

  /// `AuthorizationFilter`.
  static const authorization = 1400;

  /// The order of a built-in filter type.
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

/// Builds a [SecurityFilterChain], like Spring's `HttpSecurity`. Declare a
/// `SecurityFilterChain` bean taking it (each bean gets a fresh one):
///
/// ```dart
/// @Configuration()
/// class SecurityConfig {
///   @Bean()
///   SecurityFilterChain api(HttpSecurity http) => http
///       .authorizeHttpRequests((auth) => auth
///           .requestMatchers('/api/admin/**').hasRole('ADMIN')
///           .requestMatchers('/api/books/**', method: HttpMethod.get)
///           .permitAll()
///           .anyRequest().authenticated())
///       .httpBasic()
///       .build();
/// }
/// ```
///
/// On by default, like Spring: CSRF protection, security headers, the
/// session-stored security context, the saved request, anonymous users,
/// logout at `POST /logout`, exception handling — and here also CORS with
/// the router's configuration. Login methods (`httpBasic`, `formLogin`,
/// `oauth2ResourceServer`) and the rules (`authorizeHttpRequests`) are
/// added by calling them.
final class HttpSecurity {
  /// A builder taking optional beans from [beanFactory]; [contextPath] is
  /// `server.servlet.context-path`.
  HttpSecurity(this.beanFactory, {this.contextPath = ''});

  /// Gives the optional beans (users, password encoder, JWT decoder, CORS
  /// configuration, role hierarchy, event publishers).
  final BeanFactory? beanFactory;

  /// The application's context path (redirects).
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

  /// Limits the chain to requests matching [pattern] (and the others):
  /// path patterns of the router (`/api/**`).
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

  /// Limits the chain to requests [matcher] matches.
  HttpSecurity securityMatcherOf(RequestMatcher matcher) {
    _securityMatcher = matcher;
    return this;
  }

  /// The access rules: the first matching rule decides; a request no rule
  /// matches is denied.
  HttpSecurity authorizeHttpRequests(
    Customizer<AuthorizeHttpRequestsConfigurer> customizer,
  ) {
    customizer(_authorize ??= AuthorizeHttpRequestsConfigurer._(this));
    return this;
  }

  /// HTTP Basic: `Authorization: Basic` headers, a 401 challenge.
  HttpSecurity httpBasic([Customizer<HttpBasicConfigurer>? customizer]) {
    final configurer =
        _mechanisms.whereType<HttpBasicConfigurer>().firstOrNull ??
        (HttpBasicConfigurer._()..let(_mechanisms.add));
    customizer?.call(configurer);
    return this;
  }

  /// Form login: a login page (generated unless [FormLoginConfigurer.loginPage]
  /// names yours), `POST /login`, a session.
  HttpSecurity formLogin([Customizer<FormLoginConfigurer>? customizer]) {
    final configurer =
        _mechanisms.whereType<FormLoginConfigurer>().firstOrNull ??
        (FormLoginConfigurer._()..let(_mechanisms.add));
    customizer?.call(configurer);
    return this;
  }

  /// An OAuth 2.0 resource server: `Authorization: Bearer` JWTs.
  HttpSecurity oauth2ResourceServer(
    Customizer<OAuth2ResourceServerConfigurer> customizer,
  ) {
    final configurer =
        _mechanisms.whereType<OAuth2ResourceServerConfigurer>().firstOrNull ??
        (OAuth2ResourceServerConfigurer._()..let(_mechanisms.add));
    customizer(configurer);
    return this;
  }

  /// CSRF protection (on by default).
  HttpSecurity csrf(Customizer<CsrfConfigurer> customizer) {
    customizer(_csrf);
    return this;
  }

  /// CORS (on by default, with the router's configuration).
  HttpSecurity cors([Customizer<CorsConfigurer>? customizer]) {
    customizer?.call(_cors);
    return this;
  }

  /// Security headers (on by default).
  HttpSecurity headers(Customizer<HeadersConfigurer> customizer) {
    customizer(_headers);
    return this;
  }

  /// Sessions: creation policy, fixation protection.
  HttpSecurity sessionManagement(
    Customizer<SessionManagementConfigurer> customizer,
  ) {
    customizer(_session);
    return this;
  }

  /// The entry point and the access denied handler.
  HttpSecurity exceptionHandling(
    Customizer<ExceptionHandlingConfigurer> customizer,
  ) {
    customizer(_exceptions);
    return this;
  }

  /// Anonymous users (on by default).
  HttpSecurity anonymous(Customizer<AnonymousConfigurer> customizer) {
    customizer(_anonymous);
    return this;
  }

  /// Logout (on by default at `POST /logout`).
  HttpSecurity logout(Customizer<LogoutConfigurer> customizer) {
    customizer(_logout);
    return this;
  }

  /// The saved request (in the session by default).
  HttpSecurity requestCache(Customizer<RequestCacheConfigurer> customizer) {
    customizer(_requestCache);
    return this;
  }

  /// Where the context is kept between requests.
  HttpSecurity securityContext(
    Customizer<SecurityContextConfigurer> customizer,
  ) {
    customizer(_context);
    return this;
  }

  /// The manager of the chain's logins (instead of the beans').
  HttpSecurity authenticationManager(AuthenticationManager manager) {
    _authenticationManager = manager;
    return this;
  }

  /// The users of the chain's logins (instead of the beans').
  HttpSecurity userDetailsService(UserDetailsService service) {
    _userDetailsService = service;
    return this;
  }

  /// Adds [filter] right before the built-in filter type [before].
  HttpSecurity addFilterBefore(WebFilter filter, Type before) =>
      _addAt(filter, _orderOf(before) - 0.5);

  /// Adds [filter] right after the built-in filter type [after].
  HttpSecurity addFilterAfter(WebFilter filter, Type after) =>
      _addAt(filter, _orderOf(after) + 0.5);

  /// Adds [filter] at the place of the built-in filter type [at] (after
  /// it).
  HttpSecurity addFilterAt(WebFilter filter, Type at) =>
      _addAt(filter, _orderOf(at) + 0.1);

  int _orderOf(Type type) =>
      SecurityFilterOrder.of(type) ??
      (throw ArgumentError('$type is not a built-in security filter'));

  HttpSecurity _addAt(WebFilter filter, num order) {
    _added.add((filter, order));
    return this;
  }

  /// The chain. A builder builds once.
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

/// The rules of [HttpSecurity.authorizeHttpRequests], like Spring's
/// `AuthorizeHttpRequestsConfigurer.
/// AuthorizationManagerRequestMatcherRegistry`.
final class AuthorizeHttpRequestsConfigurer {
  AuthorizeHttpRequestsConfigurer._(this._http);

  final HttpSecurity _http;
  final _rules =
      <(RequestMatcher, AuthorizationManager<RequestAuthorizationContext>)>[];
  bool _anyRequest = false;

  /// Requests whose path matches [pattern] (or one of the others), with
  /// `method` when given: router path patterns, on the router's path.
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

  /// Requests with [method] whose path matches one of [patterns] (any
  /// method when `null`).
  AuthorizedUrl requestMatchersFor(HttpMethod? method, List<String> patterns) {
    if (patterns.isEmpty) {
      throw ArgumentError('requestMatchers needs at least one pattern');
    }
    return requestMatchersOf([
      for (final pattern in patterns)
        PathPatternRequestMatcher(pattern, method: method),
    ]);
  }

  /// Requests any of [matchers] match.
  AuthorizedUrl requestMatchersOf(List<RequestMatcher> matchers) {
    if (_anyRequest) {
      throw StateError("Can't configure requestMatchers after anyRequest");
    }
    return AuthorizedUrl._(
      this,
      matchers.length == 1 ? matchers.single : OrRequestMatcher(matchers),
    );
  }

  /// Every other request (the last rule).
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

/// What the matched requests need, like Spring's
/// `AuthorizeHttpRequestsConfigurer.AuthorizedUrl`.
final class AuthorizedUrl {
  AuthorizedUrl._(this._registry, this._matcher);

  final AuthorizeHttpRequestsConfigurer _registry;
  final RequestMatcher _matcher;

  AuthorizeHttpRequestsConfigurer _with(
    AuthorizationManager<RequestAuthorizationContext> manager,
  ) => _registry._add(_matcher, manager);

  RoleHierarchy get _hierarchy => _registry._http._roleHierarchy;

  /// Everyone, logged in or not.
  AuthorizeHttpRequestsConfigurer permitAll() =>
      _with(const SingleResultAuthorizationManager.permitAll());

  /// No one.
  AuthorizeHttpRequestsConfigurer denyAll() =>
      _with(const SingleResultAuthorizationManager.denyAll());

  /// Logged-in users (not anonymous).
  AuthorizeHttpRequestsConfigurer authenticated() =>
      _with(const AuthenticatedAuthorizationManager.authenticated());

  /// Users who logged in fully (not remembered).
  AuthorizeHttpRequestsConfigurer fullyAuthenticated() =>
      _with(const AuthenticatedAuthorizationManager.fullyAuthenticated());

  /// Only anonymous users (a login page).
  AuthorizeHttpRequestsConfigurer anonymous() =>
      _with(const AuthenticatedAuthorizationManager.anonymous());

  /// Users with [role] (`ADMIN` → `ROLE_ADMIN`).
  AuthorizeHttpRequestsConfigurer hasRole(String role) => _with(
    AuthorityAuthorizationManager.hasRole(
      role,
      rolePrefix: _registry._http._rolePrefix,
      roleHierarchy: _hierarchy,
    ),
  );

  /// Users with one of [roles].
  AuthorizeHttpRequestsConfigurer hasAnyRole(List<String> roles) => _with(
    AuthorityAuthorizationManager.hasAnyRole(
      roles,
      rolePrefix: _registry._http._rolePrefix,
      roleHierarchy: _hierarchy,
    ),
  );

  /// Users with [authority] (`SCOPE_read`).
  AuthorizeHttpRequestsConfigurer hasAuthority(String authority) => _with(
    AuthorityAuthorizationManager.hasAuthority(
      authority,
      roleHierarchy: _hierarchy,
    ),
  );

  /// Users with one of [authorities].
  AuthorizeHttpRequestsConfigurer hasAnyAuthority(List<String> authorities) =>
      _with(
        AuthorityAuthorizationManager.hasAnyAuthority(
          authorities,
          roleHierarchy: _hierarchy,
        ),
      );

  /// Decided by [manager] (it sees the path variables:
  /// `/users/{id}` → `context.variables['id']`).
  AuthorizeHttpRequestsConfigurer access(
    AuthorizationManager<RequestAuthorizationContext> manager,
  ) => _with(manager);
}

/// HTTP Basic settings.
final class HttpBasicConfigurer {
  HttpBasicConfigurer._();

  String _realmName = 'Realm';
  AuthenticationEntryPoint? _entryPoint;

  /// The realm of the challenge.
  HttpBasicConfigurer realmName(String realm) {
    _realmName = realm;
    return this;
  }

  /// The entry point of failed or missing credentials.
  HttpBasicConfigurer authenticationEntryPoint(
    AuthenticationEntryPoint entryPoint,
  ) {
    _entryPoint = entryPoint;
    return this;
  }
}

/// Form login settings, like Spring's `FormLoginConfigurer`.
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

  /// Your login page (no page is generated then); permit it in the rules.
  FormLoginConfigurer loginPage(String url) {
    _loginPage = url;
    return this;
  }

  /// Where the form posts (the login page's URL by default).
  FormLoginConfigurer loginProcessingUrl(String url) {
    _processingUrl = url;
    return this;
  }

  /// The username field.
  FormLoginConfigurer usernameParameter(String name) {
    _usernameParameter = name;
    return this;
  }

  /// The password field.
  FormLoginConfigurer passwordParameter(String name) {
    _passwordParameter = name;
    return this;
  }

  /// Where to go after a login without a saved request ([alwaysUse]: in
  /// every case).
  FormLoginConfigurer defaultSuccessUrl(String url, {bool alwaysUse = false}) {
    _defaultSuccessUrl = url;
    _alwaysUseDefaultSuccessUrl = alwaysUse;
    return this;
  }

  /// Where to go after a failed login (`/login?error`).
  FormLoginConfigurer failureUrl(String url) {
    _failureUrl = url;
    return this;
  }

  /// Answers a successful login.
  FormLoginConfigurer successHandler(AuthenticationSuccessHandler handler) {
    _successHandler = handler;
    return this;
  }

  /// Answers a failed login.
  FormLoginConfigurer failureHandler(AuthenticationFailureHandler handler) {
    _failureHandler = handler;
    return this;
  }
}

/// Resource server settings, like Spring's `OAuth2ResourceServerConfigurer`.
final class OAuth2ResourceServerConfigurer {
  OAuth2ResourceServerConfigurer._();

  JwtConfigurer? _jwt;
  AuthenticationEntryPoint? _entryPoint;
  AccessDeniedHandler? _accessDeniedHandler;
  DefaultBearerTokenResolver _resolver = const DefaultBearerTokenResolver();

  /// JWT bearer tokens (the `JwtDecoder` bean unless set).
  OAuth2ResourceServerConfigurer jwt([Customizer<JwtConfigurer>? customizer]) {
    customizer?.call(_jwt ??= JwtConfigurer._());
    _jwt ??= JwtConfigurer._();
    return this;
  }

  /// The entry point (401 `WWW-Authenticate: Bearer`).
  OAuth2ResourceServerConfigurer authenticationEntryPoint(
    AuthenticationEntryPoint entryPoint,
  ) {
    _entryPoint = entryPoint;
    return this;
  }

  /// Answers denials of token requests (403 `insufficient_scope`).
  OAuth2ResourceServerConfigurer accessDeniedHandler(
    AccessDeniedHandler handler,
  ) {
    _accessDeniedHandler = handler;
    return this;
  }

  /// Finds tokens.
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

/// JWT settings of the resource server.
final class JwtConfigurer {
  JwtConfigurer._();

  JwtDecoder? _decoder;
  JwtAuthenticationConverter? _converter;
  AuthenticationManager? _manager;

  /// The decoder.
  JwtConfigurer decoder(JwtDecoder decoder) {
    _decoder = decoder;
    return this;
  }

  /// Turns a JWT into an authentication (authorities, name).
  JwtConfigurer jwtAuthenticationConverter(
    JwtAuthenticationConverter converter,
  ) {
    _converter = converter;
    return this;
  }

  /// A whole manager for bearer tokens.
  JwtConfigurer authenticationManager(AuthenticationManager manager) {
    _manager = manager;
    return this;
  }
}

/// CSRF settings, like Spring's `CsrfConfigurer`.
final class CsrfConfigurer {
  CsrfConfigurer._();

  bool _enabled = true;
  CsrfTokenRepository? _repository;
  CsrfTokenRequestHandler? _handler;
  final _ignoring = <RequestMatcher>[];

  /// No CSRF protection (APIs authenticated by headers, not cookies).
  void disable() => _enabled = false;

  /// Where tokens are kept (`CookieCsrfTokenRepository.withHttpOnlyFalse()`
  /// for single-page apps).
  CsrfConfigurer csrfTokenRepository(CsrfTokenRepository repository) {
    _repository = repository;
    return this;
  }

  /// How tokens are exposed and read.
  CsrfConfigurer csrfTokenRequestHandler(CsrfTokenRequestHandler handler) {
    _handler = handler;
    return this;
  }

  /// Requests that need no token (path patterns).
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

/// CORS settings.
final class CorsConfigurer {
  CorsConfigurer._();

  bool _enabled = true;
  CorsConfigurationSource? _source;

  /// No CORS handling in front of the security rules.
  void disable() => _enabled = false;

  /// The configuration (the router's — the `CorsConfigurationSource` bean
  /// and `@CrossOrigin` — by default).
  CorsConfigurer configurationSource(CorsConfigurationSource source) {
    _source = source;
    return this;
  }
}

/// Security header settings, like Spring's `HeadersConfigurer`.
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

  /// No security headers at all.
  void disable() => _enabled = false;

  /// Only the headers added explicitly.
  HeadersConfigurer defaultsDisabled() {
    _defaults = false;
    return this;
  }

  /// `X-Frame-Options` ([mode] `null`: not sent).
  HeadersConfigurer frameOptions(XFrameOptionsMode? mode) {
    _frame = mode;
    return this;
  }

  /// `Strict-Transport-Security` ([writer] `null`: not sent).
  HeadersConfigurer httpStrictTransportSecurity(HstsHeaderWriter? writer) {
    _hsts = writer;
    return this;
  }

  /// Whether `X-Content-Type-Options: nosniff` is sent.
  HeadersConfigurer contentTypeOptions({required bool enabled}) {
    _contentTypeOptions = enabled;
    return this;
  }

  /// Whether `X-XSS-Protection: 0` is sent.
  HeadersConfigurer xssProtection({required bool enabled}) {
    _xss = enabled;
    return this;
  }

  /// Whether the no-cache headers are sent.
  HeadersConfigurer cacheControl({required bool enabled}) {
    _cacheControl = enabled;
    return this;
  }

  /// `Content-Security-Policy`.
  HeadersConfigurer contentSecurityPolicy(String policy) {
    _csp = policy;
    return this;
  }

  /// `Referrer-Policy`.
  HeadersConfigurer referrerPolicy(String policy) {
    _referrerPolicy = policy;
    return this;
  }

  /// Another header writer.
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

/// Session settings, like Spring's `SessionManagementConfigurer`.
final class SessionManagementConfigurer {
  SessionManagementConfigurer._();

  SessionCreationPolicy _policy = SessionCreationPolicy.ifRequired;
  bool _fixation = true;

  /// How sessions are used.
  SessionManagementConfigurer sessionCreationPolicy(
    SessionCreationPolicy policy,
  ) {
    _policy = policy;
    return this;
  }

  /// Whether a login changes the session id (on by default; switching it
  /// off allows session fixation).
  SessionManagementConfigurer sessionFixation({required bool changeSessionId}) {
    _fixation = changeSessionId;
    return this;
  }
}

/// Exception handling settings.
final class ExceptionHandlingConfigurer {
  ExceptionHandlingConfigurer._();

  AuthenticationEntryPoint? _entryPoint;
  AccessDeniedHandler? _accessDeniedHandler;

  /// The entry point for every request.
  ExceptionHandlingConfigurer authenticationEntryPoint(
    AuthenticationEntryPoint entryPoint,
  ) {
    _entryPoint = entryPoint;
    return this;
  }

  /// The handler of denials of logged-in users.
  ExceptionHandlingConfigurer accessDeniedHandler(AccessDeniedHandler handler) {
    _accessDeniedHandler = handler;
    return this;
  }
}

/// Anonymous user settings.
final class AnonymousConfigurer {
  AnonymousConfigurer._();

  bool _enabled = true;

  /// No anonymous users: requests without credentials have no
  /// authentication at all.
  void disable() => _enabled = false;
}

/// Logout settings, like Spring's `LogoutConfigurer`.
final class LogoutConfigurer {
  LogoutConfigurer._();

  bool _enabled = true;
  String _url = '/logout';
  String? _successUrl;
  LogoutSuccessHandler? _successHandler;
  bool _invalidateHttpSession = true;
  final _deleteCookies = <String>[];
  final _handlers = <LogoutHandler>[];

  /// No logout endpoint.
  void disable() => _enabled = false;

  /// The logout URL (`/logout`).
  LogoutConfigurer logoutUrl(String url) {
    _url = url;
    return this;
  }

  /// Where to go after logout (`/login?logout`).
  LogoutConfigurer logoutSuccessUrl(String url) {
    _successUrl = url;
    return this;
  }

  /// Answers a logout.
  LogoutConfigurer logoutSuccessHandler(LogoutSuccessHandler handler) {
    _successHandler = handler;
    return this;
  }

  /// Whether the session ends (yes).
  LogoutConfigurer invalidateHttpSession({required bool invalidate}) {
    _invalidateHttpSession = invalidate;
    return this;
  }

  /// Cookies to expire (`JSESSIONID`).
  LogoutConfigurer deleteCookies(String name, [String? name2, String? name3]) {
    _deleteCookies.addAll([name, ?name2, ?name3]);
    return this;
  }

  /// Another logout handler.
  LogoutConfigurer addLogoutHandler(LogoutHandler handler) {
    _handlers.add(handler);
    return this;
  }
}

/// Request cache settings.
final class RequestCacheConfigurer {
  RequestCacheConfigurer._();

  RequestCache? _cache;

  /// The cache (`const NullRequestCache()` to switch it off).
  RequestCacheConfigurer requestCache(RequestCache cache) {
    _cache = cache;
    return this;
  }
}

/// Security context settings.
final class SecurityContextConfigurer {
  SecurityContextConfigurer._();

  SecurityContextRepository? _repository;

  /// Where the context is kept between requests.
  SecurityContextConfigurer securityContextRepository(
    SecurityContextRepository repository,
  ) {
    _repository = repository;
    return this;
  }
}
