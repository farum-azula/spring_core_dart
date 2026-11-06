package dev.farumazula.reference;

import org.springframework.boot.security.autoconfigure.actuate.web.servlet.EndpointRequest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.util.matcher.OrRequestMatcher;

/**
 * The Spring twin of spring_boot_starter_actuator for
 * spring_boot_starter_actuator/test/actuator_differential_test.dart
 * (profile {@code actuator}, application-actuator.properties): Spring Boot
 * Actuator's health and info endpoints, the probes at /livez and /readyz,
 * all permitted through a chain matched with {@link EndpointRequest}, the
 * way the Dart starter's chains are.
 */
@Configuration
@Profile("actuator")
class ActuatorReference {

  @Bean
  @Order(Ordered.HIGHEST_PRECEDENCE)
  SecurityFilterChain actuatorFilterChain(HttpSecurity http) throws Exception {
    http.securityMatcher(new OrRequestMatcher(EndpointRequest.toAnyEndpoint(),
            request -> request.getRequestURI().equals("/livez")
                || request.getRequestURI().equals("/readyz")))
        .authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
        .csrf(AbstractHttpConfigurer::disable)
        .requestCache(AbstractHttpConfigurer::disable);
    return http.build();
  }
}
