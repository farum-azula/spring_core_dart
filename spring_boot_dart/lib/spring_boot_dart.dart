/// Spring Boot for Dart: `@SpringBootApplication`, `SpringApplication`,
/// `@ConfigurationProperties`, auto-configuration conditions, runners and
/// startup failure reports, on top of `spring_core_dart` (re-exported, so
/// one import is enough).
library;

export 'package:spring_boot_dart/src/annotations.dart';
export 'package:spring_boot_dart/src/autoconfigure/message_source_auto_configuration.dart'
    show MessagesBundleCondition;
export 'package:spring_boot_dart/src/conditions.dart';
export 'package:spring_boot_dart/src/configuration_properties.dart';
export 'package:spring_boot_dart/src/failure_analyzer.dart';
export 'package:spring_boot_dart/src/runners.dart';
export 'package:spring_boot_dart/src/spring_application.dart';
export 'package:spring_boot_dart/src/version.dart';
export 'package:spring_core_dart/spring_core_dart.dart';
