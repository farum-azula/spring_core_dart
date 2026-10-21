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
  /// Parses [sourceArgs] (`--name=value`, `--flag`, plain arguments).
  ApplicationArguments(List<String> sourceArgs)
    : sourceArgs = List.unmodifiable(sourceArgs);

  /// The raw arguments.
  final List<String> sourceArgs;

  /// Names of the `--options`.
  Set<String> get optionNames => {
    for (final arg in sourceArgs)
      if (arg.startsWith('--') && arg.length > 2)
        arg.substring(2).split('=').first,
  };

  /// Whether `--name` was given.
  bool containsOption(String name) => optionNames.contains(name);

  /// Values of `--name=value` (empty for a bare `--name`), or `null`.
  List<String>? getOptionValues(String name) {
    final values = <String>[];
    var found = false;
    for (final arg in sourceArgs) {
      if (arg == '--$name') {
        found = true;
      } else if (arg.startsWith('--$name=')) {
        found = true;
        values.add(arg.substring(name.length + 3));
      }
    }
    return found ? values : null;
  }

  /// Arguments that are not `--options`.
  List<String> get nonOptionArgs => [
    for (final arg in sourceArgs)
      if (!arg.startsWith('--')) arg,
  ];
}

/// A bean run once the application has started, like Spring Boot's
/// `ApplicationRunner`. Runners are called in `@Order` / `Ordered` order.
abstract interface class ApplicationRunner {
  /// Called after the context is refreshed.
  void run(ApplicationArguments args);
}

/// Like [ApplicationRunner] with the raw arguments, like Spring Boot's
/// `CommandLineRunner`.
abstract interface class CommandLineRunner {
  /// Called after the context is refreshed.
  void run(List<String> args);
}
