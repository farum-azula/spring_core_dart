// Who may call what (chapter 4): the filter chains, the role hierarchy,
// CORS from properties, the permission evaluator of `hasPermission`.
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/security/api_login.dart';
import 'package:neon_books_server/src/security/sso_config.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

/// `neon.cors.*`: who may call the API from a browser page of another
/// origin (the Flutter web build).
@ConfigurationProperties('neon.cors')
class CorsProperties {
  List<String> allowedOriginPatterns = [];
}

@Configuration()
class SecurityConfig {
  /// With the supplier stub only: it (`/supplier/**`) stands for another
  /// service, called by this server's Feign clients without a session.
  /// `securityMatcher` limits this chain to those paths; `@Order(1)` puts
  /// it before the API chain, which matches every other request.
  @Bean()
  @Order(1)
  @Profile(['supplier-stub & !prod'])
  SecurityFilterChain supplierStubChain(HttpSecurity http) => http
      .securityMatcher('/supplier/**')
      .authorizeHttpRequests((auth) => auth.anyRequest().permitAll())
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .build();

  /// The API: sessions (the `JSESSIONID` cookie), a login form posted by
  /// the app, CSRF tokens in a cookie the app reads (`XSRF-TOKEN`) and
  /// sends back (`X-XSRF-TOKEN`), as Spring's single-page-app recipe.
  /// The rules, CSRF and headers are in [_api], shared with [ssoChain];
  /// this chain adds the form login. Not with the `sso` profile.
  @Bean()
  @Order(2)
  @Profile(['!sso'])
  SecurityFilterChain apiChain(HttpSecurity http) => _api(http)
      .formLogin(
        (form) => form
            .loginProcessingUrl('/api/login')
            .successHandler(const ApiLoginSuccessHandler())
            .failureHandler(const ApiLoginFailureHandler()),
      )
      .logout(
        (logout) => logout
            .logoutUrl('/api/logout')
            .logoutSuccessHandler(
              const HttpStatusReturningLogoutSuccessHandler(
                HttpStatus.noContent,
              ),
            ),
      )
      .build();

  /// The API with single sign-on (the `sso` profile, Keycloak of
  /// example/keycloak): the same rules, CSRF and headers, but the users
  /// log in at Keycloak instead of with a form. Two kinds of clients:
  ///
  /// - **Flutter web** (and any browser): `oauth2Login()`. The page goes
  ///   to `/oauth2/authorization/keycloak`, Keycloak logs the user in and
  ///   sends the browser back to `/login/oauth2/code/keycloak`; this
  ///   server exchanges the code with its client secret, keeps the tokens
  ///   in the session and sends the browser on to the app
  ///   (`neon.app.web-url`: configuration, never a request parameter, so
  ///   no open redirect). The browser holds only the `HttpOnly` session
  ///   cookie; a web page has no safe place for tokens.
  /// - **Native apps** log in themselves (PKCE, the system browser) and
  ///   send Keycloak's access token: `oauth2ResourceServer().jwt()`
  ///   checks its signature, issuer and audience (`neon-api`); the name
  ///   and roles come from its claims (`spring.security.oauth2.
  ///   resourceserver.jwt.*` in application-sso.properties).
  ///
  /// Logging out ends the Keycloak session too: see
  /// [SsoLogoutSuccessHandler] (the app logs out with a script request,
  /// which cannot follow a redirect to Keycloak).
  @Bean()
  @Order(2)
  @Profile(['sso'])
  SecurityFilterChain ssoChain(
    HttpSecurity http,
    ClientRegistrationRepository registrations,
    AppProperties app,
  ) => _api(http)
      .oauth2Login(
        (login) => login
            .defaultSuccessUrl(app.webUrl, alwaysUse: true)
            .failureUrl('${app.webUrl}?login=failed'),
      )
      .oauth2ResourceServer((server) => server.jwt())
      .logout(
        (logout) => logout
            .logoutUrl('/api/logout')
            .logoutSuccessHandler(
              SsoLogoutSuccessHandler(
                registrations,
                postLogoutRedirectUri: app.webUrl,
              ),
            ),
      )
      .build();

  /// What both API chains share. The first matching rule decides; no
  /// rule matching is a denial.
  static HttpSecurity _api(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchersFor(HttpMethod.get, [
              '/api/books',
              '/api/books/**',
              '/api/stock/events',
            ])
            .permitAll()
            .requestMatchers('/api/admin/**')
            .hasRole('ADMIN')
            .requestMatchersFor(HttpMethod.post, ['/api/books'])
            .hasRole('ADMIN')
            .requestMatchersFor(HttpMethod.put, ['/api/books/{isbn}/cover'])
            .hasRole('ADMIN')
            // DELETE /api/books/{isbn}: any user here, the service's
            // @PreAuthorize decides.
            .requestMatchers('/api/**')
            .authenticated()
            .requestMatchers('/ws/**')
            .authenticated()
            .anyRequest()
            .denyAll(),
      )
      .csrf(
        (csrf) => csrf
            // SameSite=Lax like the session cookie: other sites' requests
            // do not carry it.
            .csrfTokenRepository(
              const CookieCsrfTokenRepository.withHttpOnlyFalse(
                sameSite: 'Lax',
              ),
            )
            // The raw token of the cookie, as the app sends it (Spring's
            // default handler expects a masked one, as pages render it).
            .csrfTokenRequestHandler(const CsrfTokenRequestAttributeHandler()),
      )
      .addFilterAfter(CsrfCookieFilter(), CsrfFilter)
      // An API has no page to come back to after a login: no saved
      // request, so anonymous requests start no session.
      .requestCache((cache) => cache.requestCache(const NullRequestCache()))
      // A request without a login gets a 401 (no redirect to a login page).
      .exceptionHandling(
        (exceptions) =>
            exceptions.authenticationEntryPoint(const HttpStatusEntryPoint()),
      )
      // On top of the default security headers (nosniff, frame options,
      // no caching, ...): JSON and images only, never framed; the login
      // and logout pages' forms post here only, and no <base> moves
      // their links (form-action and base-uri have no default-src
      // fallback).
      .headers(
        (headers) => headers.contentSecurityPolicy(
          "default-src 'none'; img-src 'self'; frame-ancestors 'none'; "
          "form-action 'self'; base-uri 'none'",
        ),
      );

  /// Admins can do whatever users can: `hasRole('USER')` lets them in.
  /// Static, as Spring advises for infrastructure beans: created without
  /// creating SecurityConfig.
  @Bean()
  static RoleHierarchy roleHierarchy() =>
      RoleHierarchyImpl.fromHierarchy('ROLE_ADMIN > ROLE_USER');

  /// Used by the web starter for the controllers and by the security
  /// chain for pre-flight requests.
  @Bean()
  CorsConfigurationSource corsConfigurationSource(CorsProperties cors) =>
      UrlBasedCorsConfigurationSource()..registerCorsConfiguration(
        '/api/**',
        CorsConfiguration(
          allowedOriginPatterns: cors.allowedOriginPatterns,
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE'],
          allowedHeaders: ['Content-Type', 'X-XSRF-TOKEN', 'Last-Event-ID'],
          exposedHeaders: ['Location', 'X-Request-Id'],
          allowCredentials: true,
          maxAge: const Duration(hours: 1),
        ),
      );
}

/// `hasPermission(returnObject, 'read')` in `OrderService.find`: the
/// customer reads their order, admins read every order.
@Component()
class OrderPermissionEvaluator implements PermissionEvaluator {
  @override
  bool hasPermission(
    Authentication authentication,
    Object? targetDomainObject,
    Object permission,
  ) =>
      targetDomainObject is CustomerOrder &&
      permission == 'read' &&
      (targetDomainObject.customer == authentication.name ||
          authentication.authorities.any((a) => a.authority == 'ROLE_ADMIN'));

  @override
  bool hasPermissionById(
    Authentication authentication,
    Object? targetId,
    String targetType,
    Object permission,
  ) => false;
}
