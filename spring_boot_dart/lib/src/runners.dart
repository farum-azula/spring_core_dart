import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';

/// The arguments the program was started with, split into `--options`
/// and plain arguments.
///
/// `main(args)` receives the arguments as a plain list. A bean that needs
/// them later, such as an import job that takes a file name and a
/// `--dry-run` flag, would otherwise have to parse that list itself.
/// `SpringApplication` parses it once and registers the result as a bean,
/// so any bean can inject it, and every [ApplicationRunner] receives it.
///
/// Options are `--name=value` or a bare `--name`; an option may be given
/// more than once. Everything else (`-v` included) is a plain argument,
/// and so is everything after a lone `--`. Options are also properties:
/// `--server.port=8081` sets `server.port`, so most settings are read with
/// `@Value` or `@ConfigurationProperties` rather than from here.
///
/// ```dart
/// // dart run bin/main.dart --dry-run books.csv
/// @Component()
/// class Importer implements ApplicationRunner {
///   Importer(this.books);
///   final BookStore books;
///
///   @override
///   Future<void> run(ApplicationArguments args) async {
///     final dryRun = args.containsOption('dry-run');
///     for (final file in args.nonOptionArgs) {
///       await books.importCsv(file, save: !dryRun);
///     }
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Importer implements ApplicationRunner {
///   public void run(ApplicationArguments args) {
///     boolean dryRun = args.containsOption("dry-run");
///     for (String file : args.getNonOptionArgs()) { ... }
///   }
/// }
/// ```
class ApplicationArguments {
  /// Parses [sourceArgs]. `SpringApplication` does this for every run;
  /// create one yourself only in a test of a runner.
  ///
  /// Only the first `=` of an option separates the name from the value.
  /// Throws an [ArgumentError] for an option without a name (`--=value`).
  ApplicationArguments(List<String> sourceArgs)
    : sourceArgs = List.unmodifiable(sourceArgs),
      _source = SimpleCommandLinePropertySource(sourceArgs);

  /// The arguments exactly as `main` received them, in order. A
  /// [CommandLineRunner] receives this list.
  final List<String> sourceArgs;

  final SimpleCommandLinePropertySource _source;

  /// The names of the options given (`dry-run` for `--dry-run`), each
  /// once.
  Set<String> get optionNames => {..._source.propertyNames};

  /// Whether the option [name] was given, with or without a value. Pass
  /// the name without the dashes.
  bool containsOption(String name) => _source.getOptionValues(name) != null;

  /// The values of the option [name], in the order given: `['a', 'b']`
  /// for `--tag=a --tag=b`.
  ///
  /// A bare `--name` gives an empty list; an option that was not given
  /// gives `null`.
  List<String>? getOptionValues(String name) {
    final values = _source.getOptionValues(name);
    return values == null ? null : List.unmodifiable(values);
  }

  /// The plain arguments, in order: those that do not start with `--`,
  /// and everything after a lone `--` (the `--` itself is left out).
  List<String> get nonOptionArgs => _source.nonOptionArgs;
}

/// A bean with work to do once, right after the application has started.
///
/// Database migrations, filling a cache, an import job: work that needs
/// the beans ready, should run once per start, and should not hold up the
/// creation of other beans. Implement this interface on a `@Component()`
/// and `SpringApplication` calls [run] after every bean is created. A
/// program that is only a job (a command-line tool) does all its work
/// in a runner.
///
/// Runners, together with [CommandLineRunner]s, are called one after
/// another, sorted by `@Order` or `Ordered`. A runner that returns a
/// `Future` is finished before the next one starts. A runner that throws,
/// or whose `Future` fails, fails the start: the failure is reported, the
/// context is closed and the error is rethrown. The generated
/// `runApplication` returns before asynchronous runners are done;
/// `runApplicationAsync` completes after the last one. A bean that
/// implements both interfaces is called as both.
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
  /// Does the startup work. Called once, after every bean is created,
  /// with the parsed program arguments.
  ///
  /// Return a `Future` for asynchronous work: the next runner waits for
  /// it. Throw (or fail the `Future`) to fail the start.
  FutureOr<void> run(ApplicationArguments args);
}

/// A bean with work to do once after the application has started, which
/// receives the program arguments as the raw list.
///
/// It is an [ApplicationRunner] for code that parses the arguments itself,
/// for example with `package:args`. Both kinds are called in one sequence,
/// sorted by `@Order`, each waiting for the previous one; the same rules
/// for failures apply.
///
/// ```dart
/// // dart run bin/main.dart report --month=2026-09
/// @Component()
/// class ReportCommand implements CommandLineRunner {
///   ReportCommand(this.reports);
///   final Reports reports;
///
///   @override
///   Future<void> run(List<String> args) async {
///     final parsed = (ArgParser()..addOption('month')).parse(args);
///     await reports.print(parsed.option('month'));
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class ReportCommand implements CommandLineRunner {
///   public void run(String... args) { ... }
/// }
/// ```
abstract interface class CommandLineRunner {
  /// Does the startup work. Called once, after every bean is created,
  /// with the arguments exactly as `main` received them.
  ///
  /// Return a `Future` for asynchronous work: the next runner waits for
  /// it. Throw (or fail the `Future`) to fail the start.
  FutureOr<void> run(List<String> args);
}
