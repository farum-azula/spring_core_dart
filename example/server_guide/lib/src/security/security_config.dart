// Who may call what (chapter 4): the filter chains, the role hierarchy,
// CORS from properties, the permission evaluator of `hasPermission`.
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/security/api_login.dart';
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
  /// The first matching rule decides; no rule matching is a denial.
  @Bean()
  @Order(2)
  SecurityFilterChain apiChain(HttpSecurity http) => http
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
      .csrf(
        (csrf) => csrf
            .csrfTokenRepository(
              const CookieCsrfTokenRepository.withHttpOnlyFalse(),
            )
            // The raw token of the cookie, as the app sends it (Spring's
            // default handler expects a masked one, as pages render it).
            .csrfTokenRequestHandler(const CsrfTokenRequestAttributeHandler()),
      )
      .addFilterAfter(CsrfCookieFilter(), CsrfFilter)
      // A request without a login gets a 401 (no redirect to a login page).
      .exceptionHandling(
        (exceptions) =>
            exceptions.authenticationEntryPoint(const HttpStatusEntryPoint()),
      )
      // On top of the default security headers (nosniff, frame options,
      // no caching, ...): JSON and images only, never framed.
      .headers(
        (headers) => headers.contentSecurityPolicy(
          "default-src 'none'; img-src 'self'; frame-ancestors 'none'",
        ),
      )
      .build();

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
