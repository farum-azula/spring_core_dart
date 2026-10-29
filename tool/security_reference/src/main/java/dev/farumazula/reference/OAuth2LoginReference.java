package dev.farumazula.reference;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.oauth2.client.oidc.web.logout.OidcClientInitiatedLogoutSuccessHandler;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.web.SecurityFilterChain;

/**
 * The Spring twin of the oauth2Login() application of
 * spring_boot_starter_security/test/differential_test.dart (profile
 * {@code oauth2}): one registration, {@code fake}, discovered from the
 * {@code issuer-uri} the test passes (its fake OpenID Connect provider), the
 * registration itself in application-oauth2.properties. Public
 * {@code /public/**}, everything else logged in, and the logout ends the
 * provider's session too.
 */
@Configuration
@Profile("oauth2")
class OAuth2LoginReference {

  @Bean
  SecurityFilterChain oauth2FilterChain(HttpSecurity http, ClientRegistrationRepository registrations)
      throws Exception {
    var logout = new OidcClientInitiatedLogoutSuccessHandler(registrations);
    logout.setPostLogoutRedirectUri("{baseUrl}/public/hello");
    http.authorizeHttpRequests(auth -> auth
            .requestMatchers("/public/**").permitAll()
            .anyRequest().authenticated())
        .oauth2Login(Customizer.withDefaults())
        .logout(l -> l.logoutSuccessHandler(logout));
    return http.build();
  }
}
