// A Spring Boot application as a function: a small REST API that runs on
// Supabase Edge Functions, Cloudflare Workers and AWS Lambda unchanged.
//
//   dart run build_runner build
//   dart run example/main.dart        # an ordinary server on port 8080
//   dart run spring_boot_starter_edge:build --platform cloudflare \
//     --entry example/main.dart       # the function, in build/cloudflare
//
// Everything in it works in a function. What does not (timers, state kept
// in memory between requests) is in the README, "What a function does
// differently".
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runFetchApplication(
  () => springApplication,
  properties: const {
    // Who signs the tokens the API accepts: the address of the issuer's
    // public keys, from the platform's environment.
    'spring.security.oauth2.resourceserver.jwt.jwk-set-uri':
        r'${JWKS_URI:https://example.com/.well-known/jwks.json}',
  },
);
