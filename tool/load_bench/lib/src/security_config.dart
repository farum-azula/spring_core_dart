// Scenario "secure": a bearer token on /secure/**, so a request goes
// through the security filter chain (the firewall, the headers, the
// token's signature and lifetime, the authorization rule) before the same
// handler as "text".
//
// Not HTTP Basic: a password is checked on every request, on another
// isolate and a few at a time (PasswordCheckLimiter), which measures the
// password checks and answers 503 past their limit, not the chain.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:load_bench/src/bench_properties.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@Configuration()
class SecurityConfig {
  /// Only `/secure/**`: the other scenarios match no chain, so they pay
  /// for the lookup of a chain and nothing else. No session and no CSRF
  /// token: the client sends its token with every request, as an API's
  /// does.
  @Bean()
  SecurityFilterChain secureChain(HttpSecurity http) => http
      .securityMatcher('/secure/**')
      .authorizeHttpRequests(
        (auth) => auth.anyRequest().hasAuthority('SCOPE_bench'),
      )
      .oauth2ResourceServer((server) => server.jwt())
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .build();

  /// Checks the tokens [BenchToken] signs: HS256 with the bench's secret.
  @Bean()
  JwtDecoder jwtDecoder(BenchProperties properties) =>
      NimbusJwtDecoder.withSecretKey(
        utf8.encode(properties.security.jwtSecret),
      );
}

/// The bearer token of the load tool: a JWT signed with
/// `bench.security.jwt-secret`, with the scope `bench`.
@Component()
class BenchToken {
  BenchToken(BenchProperties properties)
    : value = _sign(
        properties.security.jwtSecret,
        DateTime.now().add(properties.security.tokenLifetime),
      );

  /// The token, for `Authorization: Bearer <value>`.
  final String value;

  static String _sign(String secret, DateTime expires) {
    String part(Object json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final content = [
      part({'alg': 'HS256', 'typ': 'JWT'}),
      part({
        'sub': 'bench',
        'scope': 'bench',
        'exp': expires.millisecondsSinceEpoch ~/ 1000,
      }),
    ].join('.');
    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(content));
    return '$content.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
  }
}

@RestController()
class SecureController {
  /// `GET /secure/text`: 401 without the token.
  @GetMapping('/secure/text')
  String text(Principal principal) => 'Hello, ${principal.name}!';
}
