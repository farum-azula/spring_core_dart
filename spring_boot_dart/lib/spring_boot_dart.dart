/// The application layer on top of `spring_core_dart`: it turns a set of
/// beans into a running program.
///
/// Import it in `main()`. An application marks `main` with
/// `@SpringBootApplication()`, and the generator writes `runApplication`,
/// which reads the config files, applies log levels, creates the beans and
/// runs the startup tasks. The library also holds what an application
/// configures that process with: `@ConfigurationProperties` classes,
/// `ApplicationRunner` / `CommandLineRunner` beans, application events,
/// the `@ConditionalOn...` annotations of auto-configuration (what a
/// library uses to add beans by itself) and the startup failure report.
///
/// It re-exports `spring_core_dart`, so this one import is enough.
library;

export 'package:spring_boot_dart/src/annotations.dart';
export 'package:spring_boot_dart/src/auto_configuration_sorter.dart'
    show selectAutoConfigurations;
export 'package:spring_boot_dart/src/autoconfigure/jackson_auto_configuration.dart'
    show
        JsonMapperBuilderCustomizer,
        jsonMapperBuilderFromProperties,
        objectMapperFromProperties;
export 'package:spring_boot_dart/src/autoconfigure/message_source_auto_configuration.dart'
    show MessagesBundleCondition;
export 'package:spring_boot_dart/src/banner.dart';
export 'package:spring_boot_dart/src/binder.dart'
    show BindHandler, BindResult, Binder;
export 'package:spring_boot_dart/src/condition_evaluation_report.dart';
export 'package:spring_boot_dart/src/conditions.dart';
export 'package:spring_boot_dart/src/configuration_properties.dart';
export 'package:spring_boot_dart/src/deferred_logs.dart';
export 'package:spring_boot_dart/src/environment_post_processor.dart';
export 'package:spring_boot_dart/src/events.dart';
export 'package:spring_boot_dart/src/exit_code.dart'
    show ExitCodeEvent, ExitCodeExceptionMapper, ExitCodeGenerator;
export 'package:spring_boot_dart/src/failure_analyzer.dart';
export 'package:spring_boot_dart/src/hot_reload.dart';
export 'package:spring_boot_dart/src/runners.dart';
export 'package:spring_boot_dart/src/spring_application.dart';
export 'package:spring_boot_dart/src/version.dart';
export 'package:spring_core_dart/spring_core_dart.dart';
