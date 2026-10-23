/// Spring Boot's own auto-configuration, discovered by the generator of
/// every application that depends on `spring_boot_dart` (see
/// `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_dart/src/autoconfigure/jackson_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/message_source_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/validation_auto_configuration.dart';

/// `MessageSourceAutoConfiguration` and future Boot defaults.
@AutoConfigurationModule()
final BeanModule springBootAutoConfiguration = BeanModule(
  'springBootAutoConfiguration',
  [
    ...messageSourceAutoConfiguration,
    ...jacksonAutoConfiguration,
    ...validationAutoConfiguration,
  ],
);
