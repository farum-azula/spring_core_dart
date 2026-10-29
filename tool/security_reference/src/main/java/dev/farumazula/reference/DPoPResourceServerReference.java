package dev.farumazula.reference;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

/**
 * The Spring twin of the starter's default resource server chain for the
 * DPoP comparison of spring_boot_starter_security/test/differential_test.dart
 * (profile {@code dpop}): Spring Boot's chain plus {@code dPoP()}, which
 * Spring Security 7.1 needs to accept DPoP-bound tokens (the starter accepts
 * them by default). The keys come from
 * {@code spring.security.oauth2.resourceserver.jwt.jwk-set-uri}, the test's.
 */
@Configuration
@Profile("dpop")
class DPoPResourceServerReference {

  @Bean
  SecurityFilterChain dPoPFilterChain(HttpSecurity http) throws Exception {
    http.authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
        .oauth2ResourceServer(server -> server
            .jwt(Customizer.withDefaults())
            .dPoP(Customizer.withDefaults()));
    return http.build();
  }
}
