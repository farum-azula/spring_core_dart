import 'package:spring_core_dart/src/core/env/configuration_property_name.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';

/// Makes an environment find a property however a source spells it: a
/// read of `app.read-timeout` also finds `app.readTimeout`,
/// `app.read_timeout` or the variable `APP_READTIMEOUT`.
///
/// Without it the environment looks keys up exactly, so a value written
/// `readTimeout` in YAML would be missed by `@Value(r'${app.read-timeout}')`.
/// [attach] puts a [ConfigurationPropertySourcesPropertySource] first in
/// the environment; from then on a read of a canonical name (lower case,
/// `-` between words, like `app.read-timeout` or `app.hosts[0]`) through
/// `getProperty`, `@Value` or `${...}` finds every spelling. Sources are
/// still asked in order, so the first source that has the property in any
/// form wins. Names that are not canonical (`app.readTimeout`) are still
/// looked up exactly.
///
/// Applications do not call it: `ConfigDataEnvironment`, and so
/// `SpringApplication`, attaches it. Call [attach] for an environment you
/// build and fill yourself.
///
/// ```dart
/// // An environment built by hand that should match names like the
/// // application's does.
/// final environment = StandardEnvironment()
///   ..propertySources.addFirst(
///     MapPropertySource('app', {'app.readTimeout': '5s'}),
///   );
/// ConfigurationPropertySources.attach(environment);
/// environment.getProperty('app.read-timeout'); // '5s'
/// ```
///
/// Spring (Java):
/// ```java
/// ConfigurationPropertySources.attach(environment);
/// environment.getProperty("app.read-timeout");
/// ```
abstract final class ConfigurationPropertySources {
  /// The name of the source [attach] adds: `configurationProperties`.
  static const attachedPropertySourceName = 'configurationProperties';

  /// Puts the relaxed source first in [environment]'s sources, adding it
  /// or moving it back to the front. Calling it again is harmless.
  static void attach(ConfigurableEnvironment environment) {
    final sources = environment.propertySources;
    var attached = sources.get(attachedPropertySourceName);
    if (attached is! ConfigurationPropertySourcesPropertySource ||
        !identical(attached.source, sources)) {
      attached = ConfigurationPropertySourcesPropertySource(
        attachedPropertySourceName,
        sources,
      );
    }
    sources
      ..remove(attachedPropertySourceName)
      ..addFirst(attached);
  }

  /// Whether [attach] was called on [environment] (its relaxed source is
  /// present, wherever it now stands).
  static bool isAttached(ConfigurableEnvironment environment) =>
      environment.propertySources.get(attachedPropertySourceName)
          is ConfigurationPropertySourcesPropertySource;

  /// The value of the property [name] in the single [source], under any
  /// spelling, or `null`.
  ///
  /// The canonical form is tried first; then, if [source] can list its
  /// keys, every key (in the source's order) that names the same property.
  /// Environment variables are read the way Spring Boot reads them:
  /// `APP_HOSTS_0_` is `app.hosts[0]`, `APP_READTIMEOUT` is
  /// `app.read-timeout`.
  ///
  /// ```dart
  /// ConfigurationPropertySources.getProperty(
  ///   MapPropertySource('m', {'app.readTimeout': '5s'}),
  ///   ConfigurationPropertyName.of('app.read-timeout'),
  /// ); // '5s'
  /// ```
  static Object? getProperty(
    AbstractPropertySource<Object> source,
    ConfigurationPropertyName name,
  ) => _find(source, name.toString(), name);

  /// Every property of [source] as a [ConfigurationPropertyName], each
  /// with the keys of [source] that spell it (in the source's order).
  ///
  /// Binding uses it to find the map entries and list elements under a
  /// name. The result is cached per source and rebuilt when its keys
  /// change.
  ///
  /// ```dart
  /// final names = ConfigurationPropertySources.propertyNames(source);
  /// final parent = ConfigurationPropertyName.of('app.headers');
  /// for (final name in names.keys.where(parent.isParentOf)) {
  ///   print(name.getElement(2));
  /// }
  /// ```
  static Map<ConfigurationPropertyName, List<String>> propertyNames(
    EnumerablePropertySource<Object> source,
  ) => _Mappings.of(source).names;

  static Object? _find(
    AbstractPropertySource<Object> source,
    String canonical,
    ConfigurationPropertyName name,
  ) {
    if (source is ConfigurationPropertySourcesPropertySource) {
      return null;
    }
    // The exact key first: cheap, and the common case.
    final exact = source.getProperty(canonical);
    if (exact != null || source is! EnumerablePropertySource<Object>) {
      return exact;
    }
    for (final key in _Mappings.of(source).names[name] ?? const <String>[]) {
      final value = source.getProperty(key);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  // `APP_HOSTS_0_` → `app.hosts[0]`: split at `_`, lower case, digit-only
  // elements become indexes (Boot's SystemEnvironmentPropertyMapper).
  static ConfigurationPropertyName _adaptSystemEnvironment(String name) {
    final buffer = StringBuffer();
    for (final part in name.split('_')) {
      if (part.isEmpty) {
        continue;
      }
      final lower = part.toLowerCase();
      if (_digits.hasMatch(lower)) {
        buffer.write('[$lower]');
      } else {
        if (buffer.isNotEmpty) {
          buffer.write('.');
        }
        buffer.write(lower);
      }
    }
    return ConfigurationPropertyName.adapt(buffer.toString(), '.');
  }

  static final _digits = RegExp(r'^[0-9]+$');
}

/// The property source that [ConfigurationPropertySources.attach] puts
/// first in an environment, so reads of a property find it under any
/// spelling.
///
/// It holds no values of its own: it asks the environment's other sources
/// in order, each the relaxed way (see
/// [ConfigurationPropertySources.getProperty]). A name that is not
/// canonical gives `null`, so the sources after it answer exactly. Created
/// by `attach`; applications never build one.
///
/// ```dart
/// final relaxed = ConfigurationPropertySourcesPropertySource(
///   'configurationProperties',
///   [MapPropertySource('m', {'app.myProp': 'x'})],
/// );
/// relaxed.getProperty('app.my-prop'); // 'x'
/// ```
///
/// Spring (Java):
/// ```java
/// // Package-private in Spring Boot; created by
/// // ConfigurationPropertySources.attach(environment).
/// ```
final class ConfigurationPropertySourcesPropertySource
    extends AbstractPropertySource<Iterable<AbstractPropertySource<Object>>> {
  /// Creates the source called [name] over the sources [source], which is
  /// not copied, so later changes to it are seen.
  const ConfigurationPropertySourcesPropertySource(super.name, super.source);

  @override
  Object? getProperty(String name) {
    final configurationName = ConfigurationPropertyName.ofIfValid(name);
    if (configurationName == null || configurationName.isEmpty) {
      return null;
    }
    for (final candidate in source) {
      final value = ConfigurationPropertySources._find(
        candidate,
        name,
        configurationName,
      );
      if (value != null) {
        return value;
      }
    }
    return null;
  }
}

// The adapted names of an enumerable source, rebuilt when its keys change
// (compared like Boot's SpringIterableConfigurationPropertySource does).
final class _Mappings {
  _Mappings(this._keys, this.names);

  static final _cache = Expando<_Mappings>('ConfigurationPropertySources');

  final List<String> _keys;
  final Map<ConfigurationPropertyName, List<String>> names;

  static _Mappings of(EnumerablePropertySource<Object> source) {
    final keys = source is MapPropertySource
        ? source.source.keys
        : source.propertyNames;
    final cached = _cache[source];
    if (cached != null && cached._sameKeys(keys)) {
      return cached;
    }
    final system = source is SystemEnvironmentPropertySource;
    final names = <ConfigurationPropertyName, List<String>>{};
    final snapshot = keys.toList(growable: false);
    for (final key in snapshot) {
      for (final name in {
        if (system) ConfigurationPropertySources._adaptSystemEnvironment(key),
        ConfigurationPropertyName.adapt(key, '.'),
      }) {
        if (!name.isEmpty) {
          names.putIfAbsent(name, () => []).add(key);
        }
      }
    }
    return _cache[source] = _Mappings(snapshot, names);
  }

  bool _sameKeys(Iterable<String> keys) {
    if (keys.length != _keys.length) {
      return false;
    }
    var i = 0;
    for (final key in keys) {
      if (!identical(_keys[i], key) && _keys[i] != key) {
        return false;
      }
      i++;
    }
    return true;
  }
}
