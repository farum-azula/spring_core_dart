/// The beans `spring_boot_dart` adds to every application by itself: a
/// `messageSource`, a JSON `ObjectMapper` and a `Validator`.
///
/// Applications do not import this file. The generator of every
/// application that depends on `spring_boot_dart` finds it (a package's
/// `lib/spring_auto_configuration.dart` is where it looks for an
/// `@AutoConfigurationModule`) and passes the module to the generated
/// `springApplication`.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_dart/src/autoconfigure/jackson_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/message_source_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/validation_auto_configuration.dart';

/// The auto-configuration of `spring_boot_dart`:
/// `MessageSourceAutoConfiguration`, `JacksonAutoConfiguration` and
/// `ValidationAutoConfiguration`.
///
/// Each one backs off when the application declares its own bean, and
/// each can be switched off by name, for example
/// `spring.autoconfigure.exclude=JacksonAutoConfiguration`. The module as a
/// whole is excluded with `excludeName: ['springBootAutoConfiguration']`.
@AutoConfigurationModule()
final BeanModule springBootAutoConfiguration = BeanModule(
  'springBootAutoConfiguration',
  [
    ...messageSourceAutoConfiguration,
    ...jacksonAutoConfiguration,
    ...validationAutoConfiguration,
  ],
);
