import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/annotations.dart';

/// Turns a class into a typed view of a group of settings: every field is
/// filled from the property of the same name under [prefix].
///
/// Reading settings one by one with `@Value(r'${db.url}')` spreads property
/// names and conversions over the code. With this annotation the settings
/// of one area (a database pool, an API client) live in one class with
/// typed fields and defaults, and other beans inject that class. The class
/// becomes a bean and gets introspection metadata by itself, without
/// `@Component()` or `@Introspected()`.
///
/// Field `maxSize` is read from `prefix.max-size` in any relaxed spelling
/// (`prefix.maxSize`, `prefix.max_size`, the environment variable
/// `PREFIX_MAXSIZE`), from the first property source that has it, and
/// converted to the field's type. Lists and sets bind from a comma list
/// or indexed keys (`prefix.hosts[0]`, YAML lists, `PREFIX_HOSTS_0_`),
/// maps from the keys below them (`prefix.headers.x-a`,
/// `prefix.headers[x.y]`), nested `@Introspected` objects from
/// `prefix.nested.*`, also inside lists and maps
/// (`prefix.servers[0].name`, `prefix.backends.eu.url`). A list from a
/// higher-precedence source replaces the whole list; map entries are
/// merged per key. `Binder` describes these rules in full.
///
/// A mutable class is bound through its setters:
///
/// ```dart
/// // From db.url, db.max-size, db.timeout and db.hosts.
/// @ConfigurationProperties('db')
/// @Validated()
/// class DbProperties {
///   @NotBlank()
///   String url = '';
///   int maxSize = 10;
///   Duration timeout = const Duration(seconds: 5);
///   List<String> hosts = [];
/// }
///
/// @Component()
/// class ConnectionPool {
///   ConnectionPool(this.properties); // already bound and validated
///   final DbProperties properties;
/// }
/// ```
///
/// A class whose only constructor has parameters is created through that
/// constructor instead (constructor binding), which suits immutable
/// classes. A parameter without a property takes its `@DefaultValue`, else
/// its Dart default value, else `null` when it is nullable; otherwise the
/// start fails naming the property.
///
/// ```dart
/// @ConfigurationProperties('db')
/// class DbProperties {
///   const DbProperties(this.url, {@DefaultValue('10') required this.maxSize,
///       this.timeout = const Duration(seconds: 5)});
///   final String url;
///   final int maxSize;
///   final Duration timeout;
/// }
/// ```
///
/// With `@Validated()` on the class, the constraint annotations
/// (`@NotBlank()`, `@Min(1)`, ...) are checked after binding, and a
/// violation fails the start with a message naming the property.
///
/// The annotation can also go on a `@Bean` method, to bind the object the
/// method returns, for example a class of another package.
///
/// Spring (Java):
/// ```java
/// @ConfigurationProperties("db") @Validated
/// public class DbProperties {
///   String url; int maxSize = 10; Duration timeout;
/// }
///
/// @ConfigurationProperties("db")
/// public record DbProperties(String url, @DefaultValue("10") int maxSize) {}
/// ```
class ConfigurationProperties extends Component implements Introspected {
  /// Binds the properties under [prefix]. [name] sets the bean name
  /// instead of the one derived from the class.
  const ConfigurationProperties(
    this.prefix, {
    String? name,
    this.ignoreInvalidFields = false,
    this.ignoreUnknownFields = true,
  }) : super(name);

  /// The common start of the property names, in canonical form (lower
  /// case, `-` between words): `db` for `db.url`, or `my-app`.
  final String prefix;

  /// Whether a value that cannot be converted is ignored, so the field
  /// keeps its default, instead of failing the start. Off by default:
  /// a typo in a value should be noticed.
  final bool ignoreInvalidFields;

  /// Whether properties under [prefix] that match no field are ignored,
  /// which is the default.
  ///
  /// Set it to `false` to catch misspelled property names: the start then
  /// fails with `The elements [db.urll] were left unbound.` OS environment
  /// variables are not checked.
  final bool ignoreUnknownFields;

  /// No other class is introspected because of this annotation: only the
  /// annotated class gets metadata (`Introspected.classes` is empty).
  @override
  List<Type> get classes => const [];
}

/// Gives a `@ConfigurationProperties` field or constructor parameter a
/// property name other than its Dart name.
///
/// Needed when the property name is a Dart keyword (`import`, `default`)
/// or when the field should have a clearer name than the property. The
/// value is one element of the name, turned to dashed form like a Dart
/// name (`maxSize` reads `max-size`).
///
/// ```dart
/// @ConfigurationProperties('app')
/// class AppProperties {
///   AppProperties(@Name('import') this.importSettings);
///   final String importSettings; // app.import
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// public record AppProperties(@Name("import") String importSettings) {}
/// ```
class Name {
  /// Binds the field from the property [value] under the prefix.
  const Name(this.value);

  /// The property name, one element without dots, such as `import` or
  /// `max-size`.
  final String value;
}

/// The numeric bounds of a `@ConfigurationProperties` field, for the
/// editor metadata only (`range` in `spring_metadata.json`).
///
/// It does not check the value: add `@Min` / `@Max` with `@Validated()`
/// for that. Use it when the bounds are documentation, such as a port
/// range, or when the code clamps the value itself.
///
/// ```dart
/// /// The port to listen on.
/// @Range(0, 65535)
/// int port = 8080;
/// ```
class Range {
  /// Bounds from [min] to [max], both included.
  const Range(this.min, this.max);

  /// The lowest sensible value.
  final num min;

  /// The highest sensible value.
  final num max;
}

/// Values of a `@ConfigurationProperties` field that are accepted but
/// that the editor should warn about, with the reason in [message].
///
/// It is for the editor metadata only (`warn` in `spring_metadata.json`).
/// [values] are enum constants or literals, such as `[Mode.insecure]` or
/// `['*']`.
///
/// ```dart
/// /// How to treat certificates.
/// @WarnValues([TlsMode.insecure], 'Skips certificate checks.')
/// TlsMode tls = TlsMode.verify;
/// ```
class WarnValues {
  /// Warns about [values] with [message].
  const WarnValues(this.values, this.message);

  /// The values the warning is about.
  final List<Object> values;

  /// Why the values are risky.
  final String message;
}

/// What the editor offers for a field of a `@ConfigurationProperties`
/// class: fixed [values] for a `String` field that must stay a `String`,
/// or a [provider] that lists them at run time.
///
/// Prefer an enum field: its constants are listed automatically, with
/// their `///` text. Nothing is checked at run time.
///
/// ```dart
/// /// The log pattern flavour.
/// @PropertyValues(['plain', 'json'])
/// String format = 'plain';
///
/// /// The active profiles.
/// @PropertyValues.provider('profiles')
/// List<String> active = [];
/// ```
class PropertyValues {
  /// Offers [values] in the editor.
  const PropertyValues(this.values) : provider = null;

  /// Lets the editor ask the provider named [provider] for the values;
  /// `profiles` lists the profiles of the project.
  const PropertyValues.provider(String this.provider) : values = const [];

  /// The suggested values (none with a [provider]).
  final List<String> values;

  /// The name of the value provider, or `null`.
  final String? provider;
}
