import 'package:spring_core_dart/src/core/env/property_source.dart';

/// Command-line arguments, like Spring's `SimpleCommandLinePropertySource`.
///
/// `--key=value` defines `key`; `--flag` defines `flag` as an empty string;
/// a repeated option keeps all values joined with commas. Other arguments
/// are available as the comma-joined [nonOptionArgsPropertyName] property.
///
/// ```dart
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
/// Spring Boot adds this source automatically in `SpringApplication.run`;
/// here it is added by hand.
class SimpleCommandLinePropertySource
    extends EnumerablePropertySource<Map<String, List<String>>> {
  /// Parses [args]; throws [ArgumentError] for an option without a name
  /// (`--` or `--=value`).
  SimpleCommandLinePropertySource(
    List<String> args, {
    String name = defaultName,
  }) : this._(name, _parse(args));

  SimpleCommandLinePropertySource._(String name, _Parsed parsed)
    : nonOptionArgs = List.unmodifiable(parsed.nonOptions),
      super(name, parsed.options);

  /// Default name of the command-line source.
  static const defaultName = 'commandLineArgs';

  /// Property holding the non-option arguments.
  static const nonOptionArgsPropertyName = 'nonOptionArgs';

  /// Arguments that are not `--options`, in order.
  final List<String> nonOptionArgs;

  /// Values of option [name], or `null` if it was not given.
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
  // name, in order) and everything else. Only the first `=` separates.
  static _Parsed _parse(List<String> args) {
    final options = <String, List<String>>{};
    final nonOptions = <String>[];
    for (final arg in args) {
      if (!arg.startsWith('--')) {
        nonOptions.add(arg);
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
