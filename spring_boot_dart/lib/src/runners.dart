import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';

/// The command-line arguments of a `SpringApplication` run, like Spring
/// Boot's `ApplicationArguments`; injectable as a bean.
///
/// ```dart
/// @Component()
/// class Importer implements ApplicationRunner {
///   @override
///   void run(ApplicationArguments args) {
///     if (args.containsOption('dry-run')) { ... }
///   }
/// }
/// ```
class ApplicationArguments {
  /// Parses [sourceArgs] (`--name=value`, `--flag`, plain arguments; a
  /// lone `--` ends the options) like Spring Boot's
  /// `DefaultApplicationArguments`; throws an [ArgumentError] for an
  /// option without a name (`--=value`).
  ApplicationArguments(List<String> sourceArgs)
    : sourceArgs = List.unmodifiable(sourceArgs),
      _source = SimpleCommandLinePropertySource(sourceArgs);

  /// The raw arguments.
  final List<String> sourceArgs;

  final SimpleCommandLinePropertySource _source;

  /// Names of the `--options`.
  Set<String> get optionNames => {..._source.propertyNames};

  /// Whether `--name` was given.
  bool containsOption(String name) => _source.getOptionValues(name) != null;

  /// Values of `--name=value` (empty for a bare `--name`), or `null`.
  List<String>? getOptionValues(String name) {
    final values = _source.getOptionValues(name);
    return values == null ? null : List.unmodifiable(values);
  }

  /// Arguments that are not `--options` (everything after a lone `--`
  /// included, the `--` itself not).
  List<String> get nonOptionArgs => _source.nonOptionArgs;
}

/// A bean run once the application has started, like Spring Boot's
/// `ApplicationRunner`.
///
/// Runners are called one after another in `@Order` / `Ordered` order,
/// like in Spring Boot: an asynchronous runner (returning a `Future`) is
/// finished before the next one starts. A runner that throws (or whose
/// `Future` fails) stops the start: the failure is reported and the
/// context is closed. `runApplicationAsync` (and `SpringApplication.runAsync`)
/// completes once every runner has finished.
///
/// ```dart
/// @Component()
/// @Order(1)
/// class Migrations implements ApplicationRunner {
///   Migrations(this.db);
///   final Database db;
///
///   @override
///   Future<void> run(ApplicationArguments args) => db.migrate(); // awaited
/// }
///
/// @Component()
/// @Order(2)
/// class Warmup implements ApplicationRunner {  // starts after Migrations
///   @override
///   void run(ApplicationArguments args) { ... }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component @Order(1)
/// class Migrations implements ApplicationRunner {
///   public void run(ApplicationArguments args) { db.migrate(); }
/// }
/// ```
abstract interface class ApplicationRunner {
  /// Called after the context is refreshed; a returned `Future` is awaited
  /// before the next runner.
  FutureOr<void> run(ApplicationArguments args);
}

/// Like [ApplicationRunner] with the raw arguments, like Spring Boot's
/// `CommandLineRunner` (called in the same order, also awaited).
abstract interface class CommandLineRunner {
  /// Called after the context is refreshed; a returned `Future` is awaited
  /// before the next runner.
  FutureOr<void> run(List<String> args);
}
