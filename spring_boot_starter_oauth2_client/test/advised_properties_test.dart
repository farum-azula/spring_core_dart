import 'package:spring_boot_starter_oauth2_client/spring_gen/src/properties/properties_beans.spring.dart';

import 'advised_properties.dart';

// Advised properties beans (proxies) behave like the beans, and the
// generated property accessors read and write them.
void main() {
  expectAdvisedPropertiesDelegate($oauth2ClientConfigBeans);
  expectIntrospectedPropertiesRoundTrip($oauth2ClientConfigBeans);
}
