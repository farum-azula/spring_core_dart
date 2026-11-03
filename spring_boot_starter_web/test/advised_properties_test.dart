import 'package:spring_boot_starter_web/spring_gen/src/config/config.spring.dart';

import 'advised_properties.dart';

// Advised properties beans (proxies) behave like the beans, and the
// generated property accessors read and write them.
void main() {
  expectAdvisedPropertiesDelegate($webConfigBeans);
  expectIntrospectedPropertiesRoundTrip($webConfigBeans);
}
