package dev.farumazula.reference;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.SecurityFilterChain;

/**
 * The Spring twin of the static resources of spring_boot_starter_web for
 * spring_boot_starter_web/test/static_resources_differential_test.dart
 * (profile {@code static}): Spring Boot's own {@code ResourceHttpRequestHandler}
 * serving the directory the test passes in
 * {@code spring.web.resources.static-locations}, with the same other
 * {@code spring.web.resources.*} keys. Every request is permitted and Spring
 * Security's headers are off, so the answers are the resource handler's;
 * Spring Security's firewall still refuses what it refuses (as in any Boot
 * application with Security).
 */
@Configuration
@Profile("static")
class StaticResourcesReference {

  @Bean
  SecurityFilterChain staticFilterChain(HttpSecurity http) throws Exception {
    http.authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
        .headers(AbstractHttpConfigurer::disable)
        .csrf(AbstractHttpConfigurer::disable)
        .requestCache(AbstractHttpConfigurer::disable);
    return http.build();
  }
}
