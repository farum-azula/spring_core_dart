// NOT an example. The function the starter's own tests run: compiled for
// every platform (spring_boot_starter_edge/test/platform_*_test.dart) and called in the VM through
// FetchApplication (test/fetch_application_test.dart). Its endpoints
// exist to be checked, also the ones that fail on purpose and the parts
// that do not suit a function (a method on a timer, a cache in memory:
// what the starter must warn about). The starter's example is
// spring_boot_starter_edge/example.
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';

import 'spring_gen/main.spring.dart';

/// What the function is configured with on every platform. `GREETING`
/// and `JWT_SECRET` come from the platform's environment.
const functionProperties = <String, Object?>{
  'spring.main.banner-mode': 'off',
  'spring.application.name': 'edge-test',
  'spring.security.oauth2.resourceserver.jwt.secret-key':
      r'${JWT_SECRET:0123456789abcdef0123456789abcdef}',
  'spring.security.oauth2.resourceserver.jwt.require-expiry': 'true',
  'spring.security.oauth2.resourceserver.jwt.authorities-claim-name': 'roles',
  'spring.security.oauth2.resourceserver.jwt.authority-prefix': 'ROLE_',
  'greeting': r'${GREETING:none}',
  'server.max-http-request-body-size': '64KB',
  'spring.web.rate-limit.enabled': 'true',
};

@SpringBootApplication()
void main() => runFetchApplication(
  () => springApplication,
  properties: functionProperties,
);
