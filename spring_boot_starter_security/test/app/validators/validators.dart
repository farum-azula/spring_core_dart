// An application's own token validators, as beans: a class found by the
// scan and a @Bean method. The auto-configured decoder adds both.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../../spring_gen/app/validators/validators.spring.dart';

@ComponentScan()
final BeanModule jwtValidatorBeans = $jwtValidatorBeans;

/// Only tokens of the `shop` tenant.
@Component()
class TenantValidator implements OAuth2TokenValidator<Jwt> {
  @override
  OAuth2TokenValidatorResult validate(Jwt token) =>
      token.claims['tenant'] == 'shop'
      ? OAuth2TokenValidatorResult.success
      : OAuth2TokenValidatorResult.failure(
          const OAuth2Error('invalid_token', 'The tenant is not shop'),
        );
}

bool _isTrue(Object? value) => value == true;

@Configuration()
class JwtValidatorConfig {
  /// Only users with a verified email.
  @Bean()
  OAuth2TokenValidator<Jwt> verifiedEmail() =>
      const JwtClaimValidator('email_verified', _isTrue);
}
