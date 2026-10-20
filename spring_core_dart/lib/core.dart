/// Core utilities: ordering, type conversion, environment, profiles, config
/// files and resources (Spring's `spring-core` plus Spring Boot's config
/// data).
///
/// ```dart
/// final environment = StandardEnvironment();
/// await ConfigDataEnvironment(environment).processAndApply();
/// final port = environment.getPropertyAs<int>('server.port') ?? 8080;
/// final dev = environment.matchesProfiles(['dev']);
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurableEnvironment environment = new StandardEnvironment();
/// // Spring Boot loads application.properties into it on startup.
/// int port = environment.getProperty("server.port", Integer.class, 8080);
/// boolean dev = environment.matchesProfiles("dev");
/// ```
library;

export 'package:spring_core_dart/src/core/convert/conversion_exceptions.dart';
export 'package:spring_core_dart/src/core/convert/conversion_service.dart';
export 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
export 'package:spring_core_dart/src/core/convert/duration_style.dart';
export 'package:spring_core_dart/src/core/convert/generic_conversion_service.dart';
export 'package:spring_core_dart/src/core/env/command_line_property_source.dart';
export 'package:spring_core_dart/src/core/env/config/config_data_environment.dart';
export 'package:spring_core_dart/src/core/env/config/config_data_exceptions.dart';
export 'package:spring_core_dart/src/core/env/config/property_source_factory.dart';
export 'package:spring_core_dart/src/core/env/config/property_source_loader.dart';
export 'package:spring_core_dart/src/core/env/env_exceptions.dart';
export 'package:spring_core_dart/src/core/env/environment.dart';
export 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
export 'package:spring_core_dart/src/core/env/profiles.dart';
export 'package:spring_core_dart/src/core/env/property_placeholder_helper.dart';
export 'package:spring_core_dart/src/core/env/property_resolver.dart';
export 'package:spring_core_dart/src/core/env/property_source.dart';
export 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';
export 'package:spring_core_dart/src/core/io/file_system_resource.dart';
export 'package:spring_core_dart/src/core/io/path_matcher.dart';
export 'package:spring_core_dart/src/core/io/properties_parser.dart';
export 'package:spring_core_dart/src/core/io/resource.dart';
export 'package:spring_core_dart/src/core/io/resource_loader.dart';
export 'package:spring_core_dart/src/core/io/resource_pattern_resolver.dart';
export 'package:spring_core_dart/src/core/io/resource_property_source.dart';
export 'package:spring_core_dart/src/core/order.dart';
