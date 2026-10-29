package dev.farumazula.reference;

import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpMethod;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.authorization.AuthorizationResult;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.annotation.CurrentSecurityContext;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * The Spring twin of spring_boot_starter_security/test/app (the shared
 * controllers and test/app/rules): same endpoints, users, rules, CORS
 * configuration and method security. The differential test sends the same
 * requests to both.
 */
@SpringBootApplication
@EnableMethodSecurity
public class ReferenceApplication {

  public static void main(String[] args) {
    SpringApplication.run(ReferenceApplication.class, args);
  }

  /**
   * The rules chain; the oauth2 profile has OAuth2LoginReference's instead,
   * the dpop profile DPoPResourceServerReference's.
   */
  @Bean
  @Profile("!oauth2 & !dpop")
  SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.authorizeHttpRequests(auth -> auth
            .requestMatchers("/public/**", "/form").permitAll()
            .requestMatchers("/api/admin", "/api/admin/**").hasRole("ADMIN")
            .requestMatchers(HttpMethod.GET, "/api/reports/**").authenticated()
            .requestMatchers("/api/users/{id}").access(new SelfOrAdmin())
            .anyRequest().authenticated())
        .formLogin(Customizer.withDefaults())
        .httpBasic(Customizer.withDefaults())
        .cors(Customizer.withDefaults());
    return http.build();
  }

  @Bean
  UserDetailsService users() {
    return new InMemoryUserDetailsManager(
        User.withUsername("ada").password("{noop}ada-pw").roles("USER").build(),
        User.withUsername("root").password("{noop}root-pw").roles("ADMIN").build());
  }

  @Bean
  CorsConfigurationSource corsConfigurationSource() {
    var config = new CorsConfiguration();
    config.setAllowedOrigins(List.of("https://trusted.example"));
    config.setAllowedMethods(List.of("GET", "POST"));
    config.setAllowCredentials(true);
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
  }

  /** /api/users/{id}: the user themself or an admin. */
  static final class SelfOrAdmin implements AuthorizationManager<RequestAuthorizationContext> {
    @Override
    public AuthorizationResult authorize(
        Supplier<? extends Authentication> authentication, RequestAuthorizationContext context) {
      var user = authentication.get();
      var admin = user != null
          && user.getAuthorities().stream().anyMatch(a -> "ROLE_ADMIN".equals(a.getAuthority()));
      var self = user != null && user.isAuthenticated()
          && !(user instanceof org.springframework.security.authentication.AnonymousAuthenticationToken)
          && user.getName().equals(context.getVariables().get("id"));
      return new AuthorizationDecision(admin || self);
    }
  }

  @RestController
  static class PublicController {
    @GetMapping("/public/hello")
    String hello() { return "hello"; }

    @GetMapping("/")
    String home() { return "home"; }
  }

  @Service
  public static class Reports {
    @PreAuthorize("hasRole('ADMIN')")
    public String report(String id) { return "report " + id; }
  }

  @RestController
  @RequestMapping("/api")
  static class ApiController {
    private final Reports reports;

    ApiController(Reports reports) { this.reports = reports; }

    @GetMapping("/me")
    Map<String, Object> me(Authentication authentication) {
      return Map.of(
          "name", authentication.getName(),
          "authorities", authentication.getAuthorities().stream().map(GrantedAuthority::getAuthority).toList());
    }

    @GetMapping("/principal")
    String principal(java.security.Principal principal) {
      return principal == null ? "none" : principal.getName();
    }

    @GetMapping("/user")
    String user(@AuthenticationPrincipal UserDetails user) {
      return user == null ? "none" : user.getUsername();
    }

    @GetMapping("/context")
    String context(@CurrentSecurityContext SecurityContext context) {
      return context.getAuthentication() == null ? "none" : context.getAuthentication().getName();
    }

    @GetMapping("/admin")
    String admin() { return "admin"; }

    @PostMapping("/data")
    String data(@RequestBody String body) { return "got " + body; }

    @GetMapping("/users/{id}")
    String userById(@PathVariable String id) { return "user " + id; }

    @GetMapping("/reports/{id}")
    String report(@PathVariable String id) { return reports.report(id); }

    @GetMapping("/cors")
    @CrossOrigin(origins = "https://app.example")
    String cors() { return "cors"; }

    @GetMapping("/cached")
    String cached(HttpServletResponse response) {
      response.setHeader("Cache-Control", "max-age=60");
      return "cached";
    }
  }

  @RestController
  static class FormController {
    @GetMapping("/form")
    String form(HttpServletRequest request) {
      var token = (CsrfToken) request.getAttribute(CsrfToken.class.getName());
      return token.getParameterName() + "=" + token.getToken();
    }

    @PostMapping("/form")
    String submit(@RequestParam String text) { return "submitted " + text; }
  }
}
