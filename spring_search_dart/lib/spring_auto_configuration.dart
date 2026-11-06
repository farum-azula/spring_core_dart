/// The package's auto-configuration. Applications never import it: the
/// generator finds this file in every dependency and adds its module to
/// the generated application, which is what makes the dependency alone
/// enough. A test that builds a context by hand can name it.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/config/config.dart';
import 'package:spring_search_dart/src/search_auto_configuration.dart';

/// The `searchService` bean and the `spring.search.*` properties.
@AutoConfigurationModule()
final BeanModule springSearchDartAutoConfiguration = BeanModule(
  'springSearchDartAutoConfiguration',
  [...searchAutoConfiguration],
  imports: [searchProperties],
);
