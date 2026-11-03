import 'package:spring_boot_starter_logging/spring_gen/src/properties/properties_beans.spring.dart';

import 'advised_properties.dart';

// Advised properties beans (proxies) behave like the beans, and the
// generated property accessors read and write them.
void main() {
  expectAdvisedPropertiesDelegate($loggingConfigBeans);
  expectIntrospectedPropertiesRoundTrip($loggingConfigBeans);
}
