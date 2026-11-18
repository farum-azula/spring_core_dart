import 'package:spring_core_dart/core.dart'
    show
        ConfigurationPropertyName,
        ConfigurationPropertyNameForm,
        ConfigurationPropertySources,
        ConfigurationPropertySourcesPropertySource,
        EnumerablePropertySource,
        StandardEnvironment;

/// `spring.flutter.web.page.wasm-allow-list`: the browser engines that run
/// the WebAssembly of a `--wasm` build, which the page passes to Flutter's
/// loader as `config.wasmAllowList` (see `WebPageLoader`).
///
/// Spring has no counterpart.
abstract final class WasmAllowList {
  /// The property, a map of engine to `true` or `false`.
  static const property = 'spring.flutter.web.page.wasm-allow-list';

  /// The engines Flutter's loader tells apart (`browser_environment.js`).
  static const engines = {'blink', 'gecko', 'webkit'};

  static final _name = ConfigurationPropertyName.of(property);

  /// The map of [environment], sorted by engine; `null` when it is not
  /// set, or when it has a problem: each goes to [problem].
  ///
  /// A source earlier in the environment wins per engine, as for every
  /// property (a profile's file over the file without one).
  static Map<String, bool>? read(
    StandardEnvironment environment, {
    required void Function(String message) problem,
  }) {
    final allowed = <String, bool>{};
    final problems = <String>[];
    for (final source in environment.propertySources) {
      if (source is! EnumerablePropertySource<Object> ||
          source is ConfigurationPropertySourcesPropertySource) {
        continue;
      }
      for (final MapEntry(key: name, value: keys)
          in ConfigurationPropertySources.propertyNames(source).entries) {
        final value = source.getProperty(keys.first);
        if (name == _name) {
          problems.add(
            '$property is a map of browser engine to true or false '
            '($property.gecko: true), not $value.',
          );
          continue;
        }
        if (!_name.isAncestorOf(name)) {
          continue;
        }
        final engine = name.numberOfElements == _name.numberOfElements + 1
            ? name
                  .getElement(
                    _name.numberOfElements,
                    form: ConfigurationPropertyNameForm.uniform,
                  )
                  .toLowerCase()
            : null;
        if (engine == null || !engines.contains(engine)) {
          problems.add(
            '$name names no browser engine of $property: it knows '
            '${engines.join(', ')}.',
          );
          continue;
        }
        final allow = switch (value) {
          final bool flag => flag,
          final String text => switch (text.trim().toLowerCase()) {
            'true' => true,
            'false' => false,
            _ => null,
          },
          _ => null,
        };
        if (allow == null) {
          problems.add('$property.$engine is true or false, not $value.');
          continue;
        }
        // The first source has the last word.
        allowed.putIfAbsent(engine, () => allow);
      }
    }
    problems.toSet().forEach(problem);
    if (problems.isNotEmpty || allowed.isEmpty) {
      return null;
    }
    return {
      for (final engine in allowed.keys.toList()..sort())
        engine: allowed[engine]!,
    };
  }
}
