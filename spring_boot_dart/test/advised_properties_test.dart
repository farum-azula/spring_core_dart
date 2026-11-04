import 'package:spring_boot_dart/spring_gen/src/properties/properties.spring.dart';

import 'advised_properties.dart';

// Advised properties beans (proxies) behave like the beans, and the
// generated property accessors read and write them.
void main() {
  expectAdvisedPropertiesDelegate($bootPropertiesBeans);
  expectIntrospectedPropertiesRoundTrip($bootPropertiesBeans);
}
