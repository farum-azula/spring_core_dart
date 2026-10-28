import 'package:spring_core_dart/src/core/env/property_source.dart';

/// The property source over the program's command-line arguments, so that
/// `--server.port=9090` sets the property `server.port`.
///
/// It is why a setting can be overridden at launch without touching the
/// config files: placed first in the environment, it wins over every other
/// source. `SpringApplication` adds it for you from the `args` of `main`,
/// so an application only writes the arguments; it creates one itself only
/// when it builds a `StandardEnvironment` without `SpringApplication`.
/// Arguments are parsed like this:
///
/// - `--key=value` sets `key`; only the first `=` separates.
/// - `--flag` alone sets `flag` to an empty string.
/// - A repeated option keeps all its values, joined with commas when read.
/// - Other arguments are non-option arguments, readable as [nonOptionArgs]
///   or as the comma-joined property [nonOptionArgsPropertyName].
/// - A lone `--` ends the options: everything after it is a non-option
///   argument, as in Spring.
///
/// ```dart
/// // A tool without SpringApplication that still takes `--key=value`.
/// Future<void> main(List<String> args) async {
///   // args: --server.port=9090 --debug input.txt
///   final environment = StandardEnvironment()
///     ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
///   environment.getPropertyAs<int>('server.port'); // 9090
///   environment.containsProperty('debug'); // true
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// public static void main(String[] args) {
///   var environment = new StandardEnvironment();
///   environment.getPropertySources()
///       .addFirst(new SimpleCommandLinePropertySource(args));
///   Integer port = environment.getProperty("server.port", Integer.class);
/// }
/// ```
///
/// Spring Boot's `SpringApplication.run` adds this source automatically,
/// and so does `SpringApplication` here.
class SimpleCommandLinePropertySource
    extends EnumerablePropertySource<Map<String, List<String>>> {
  /// Parses [args] into a source called [name] (`commandLineArgs` unless
  /// given). Throws [ArgumentError] for an option without a name
  /// (`--=value`).
  SimpleCommandLinePropertySource(
    List<String> args, {
    String name = defaultName,
  }) : this._(name, _parse(args));

  SimpleCommandLinePropertySource._(String name, _Parsed parsed)
    : nonOptionArgs = List.unmodifiable(parsed.nonOptions),
      super(name, parsed.options);

  /// The name the source has unless another is given: `commandLineArgs`.
  static const defaultName = 'commandLineArgs';

  /// The property that holds the non-option arguments, comma-joined:
  /// `nonOptionArgs`.
  static const nonOptionArgsPropertyName = 'nonOptionArgs';

  /// The arguments that are not `--options` (file names, sub-commands), in
  /// order.
  final List<String> nonOptionArgs;

  /// Every value given for the option [name], in order, or `null` when it
  /// was not given. Use it for options that may repeat; reading the
  /// property gives them comma-joined instead.
  ///
  /// A flag without a value (`--debug`) gives an empty list.
  ///
  /// ```dart
  /// // args: --tag=a --tag=b
  /// source.getOptionValues('tag'); // ['a', 'b']
  /// ```
  List<String>? getOptionValues(String name) => source[name];

  @override
  Object? getProperty(String name) {
    if (name == nonOptionArgsPropertyName) {
      return nonOptionArgs.isEmpty ? null : nonOptionArgs.join(',');
    }
    return source[name]?.join(',');
  }

  @override
  bool containsProperty(String name) => name == nonOptionArgsPropertyName
      ? nonOptionArgs.isNotEmpty
      : source.containsKey(name);

  @override
  List<String> get propertyNames => List.unmodifiable(source.keys);

  // Splits arguments into `--name[=value]` options (values collected per
  // name, in order) and everything else. Only the first `=` separates; a
  // lone `--` ends the options (Spring's SimpleCommandLineArgsParser).
  static _Parsed _parse(List<String> args) {
    final options = <String, List<String>>{};
    final nonOptions = <String>[];
    var endOfOptions = false;
    for (final arg in args) {
      if (endOfOptions || !arg.startsWith('--')) {
        nonOptions.add(arg);
        continue;
      }
      if (arg == '--') {
        endOfOptions = true;
        continue;
      }
      final body = arg.substring(2);
      final separator = body.indexOf('=');
      final name = separator < 0 ? body : body.substring(0, separator);
      if (name.isEmpty) {
        throw ArgumentError.value(arg, 'args', 'Invalid argument syntax');
      }
      final values = options.putIfAbsent(name, () => []);
      if (separator >= 0) {
        values.add(body.substring(separator + 1));
      }
    }
    return _Parsed(options, nonOptions);
  }
}

// Result of [SimpleCommandLinePropertySource._parse]; a class so the
// redirecting constructor can pass both parts through one argument.
final class _Parsed {
  _Parsed(this.options, this.nonOptions);

  final Map<String, List<String>> options;
  final List<String> nonOptions;
}
