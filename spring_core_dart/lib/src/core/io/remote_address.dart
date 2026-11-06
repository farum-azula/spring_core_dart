import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/log.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// An address in the configuration that something is downloaded from: a
/// theme, an image, a page loader. [RemoteAddresses] reads it from the
/// value as written, through its chain of [RemoteAddressResolver]s.
///
/// Spring (Java): no counterpart; Spring Boot has no downloads in its
/// configuration.
final class RemoteAddress {
  /// The address [uri] that [written], the value of [property], names.
  RemoteAddress({
    required this.property,
    required this.written,
    required this.uri,
  });

  /// The property the address is the value of.
  final String property;

  /// The value as written.
  final String written;

  /// The address to connect to.
  final Uri uri;

  /// Whether the connection is encrypted (`https`).
  bool get secure => uri.scheme == 'https';

  @override
  bool operator ==(Object other) =>
      other is RemoteAddress && other.property == property && other.uri == uri;

  @override
  int get hashCode => Object.hash(property, uri);

  @override
  String toString() => '$uri ($property)';
}

/// Reads one kind of address of the configuration: a scheme or a shorthand
/// (`github:`, a company's `cdn:`). [RemoteAddresses] asks its resolvers in
/// order, and the first that [supports] a value resolves it: a chain of
/// responsibility, so a new kind of address is a new resolver, not a
/// change of the others.
///
/// ```dart
/// // `cdn:themes/ocean.yml` is a file of the company's CDN.
/// final class CdnAddressResolver implements RemoteAddressResolver {
///   const CdnAddressResolver();
///
///   @override
///   bool supports(String text) => text.startsWith('cdn:');
///
///   @override
///   Uri resolve(String text, {required String property}) =>
///       Uri.https('cdn.example.com', '/${text.substring('cdn:'.length)}');
/// }
///
/// final app = SpringApplication(
///   [appBeans],
///   addressResolvers: [const CdnAddressResolver()],
/// );
/// ```
///
/// Spring (Java): like a `ProtocolResolver` of the `ResourceLoader`.
abstract interface class RemoteAddressResolver {
  /// Whether this resolver reads [text] (by its scheme or prefix).
  bool supports(String text);

  /// The address [text] names. Throws an [ArgumentError] named [property]
  /// when [text] is malformed.
  Uri resolve(String text, {required String property});
}

/// `https://` and `http://` URLs as written.
final class UrlAddressResolver implements RemoteAddressResolver {
  /// The resolver of URLs.
  const UrlAddressResolver();

  @override
  bool supports(String text) =>
      text.startsWith('https://') || text.startsWith('http://');

  @override
  Uri resolve(String text, {required String property}) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError.value(text, property, 'is no URL: it has no host');
    }
    return uri;
  }
}

/// `github:owner/repo/path/to/file@ref`: the file as
/// `raw.githubusercontent.com` serves it (`ref` a branch, a tag or a
/// commit; `HEAD` without one).
final class GitHubAddressResolver implements RemoteAddressResolver {
  /// The resolver of `github:` addresses.
  const GitHubAddressResolver();

  static const _prefix = 'github:';

  @override
  bool supports(String text) => text.startsWith(_prefix);

  @override
  Uri resolve(String text, {required String property}) {
    final reference = text.substring(_prefix.length);
    final at = reference.lastIndexOf('@');
    final location = at < 0 ? reference : reference.substring(0, at);
    final ref = at < 0 ? 'HEAD' : reference.substring(at + 1);
    final parts = location.split('/');
    if (parts.length < 3 || parts.any((p) => p.isEmpty) || ref.isEmpty) {
      throw ArgumentError.value(
        text,
        property,
        'github: addresses look like github:owner/repo/path/to/file@ref',
      );
    }
    return Uri.https(
      'raw.githubusercontent.com',
      '/${parts[0]}/${parts[1]}/$ref/${parts.skip(2).join('/')}',
    );
  }
}

/// The addresses of the configuration: a chain of
/// [RemoteAddressResolver]s, the application's own first (in their
/// order, by `Ordered` when they implement it), then the built-in ones
/// ([GitHubAddressResolver], [UrlAddressResolver]). Every feature that
/// downloads (themes, images, page loaders) reads its addresses here, so
/// they all accept the same kinds and a new kind works everywhere.
///
/// ```dart
/// final address = const RemoteAddresses().parse(
///   'github:farum-azula/themes/themes/code.yml@code-v0.2.0',
///   property: 'spring.flutter.theme.source',
/// );
/// ```
///
/// The application's chain is the `remoteAddresses` bean, made from
/// `SpringApplication(addressResolvers:)`; the resolvers are passed to the
/// application because the themes are read before the beans exist.
final class RemoteAddresses {
  /// The chain of [resolvers] then the built-in ones.
  const RemoteAddresses([this.resolvers = const []]);

  /// The built-in resolvers, asked after the application's.
  static const builtIn = <RemoteAddressResolver>[
    GitHubAddressResolver(),
    UrlAddressResolver(),
  ];

  /// The application's own resolvers.
  final List<RemoteAddressResolver> resolvers;

  /// The whole chain, in the order it is asked.
  List<RemoteAddressResolver> get chain => [
    ...OrderComparator.sort(resolvers),
    ...builtIn,
  ];

  /// The resolver that reads [text], or `null` when none does.
  RemoteAddressResolver? resolverOf(String text) {
    final trimmed = text.trim();
    for (final resolver in chain) {
      if (resolver.supports(trimmed)) {
        return resolver;
      }
    }
    return null;
  }

  /// Whether [text] is an address a resolver reads, rather than a path.
  bool isAddress(String text) => resolverOf(text) != null;

  /// Reads [written], the value of [property]. Throws an [ArgumentError]
  /// named after [property] when no resolver reads it or the one that does
  /// finds it malformed.
  RemoteAddress parse(String written, {required String property}) {
    final text = written.trim();
    final resolver = resolverOf(text);
    if (resolver == null) {
      throw ArgumentError.value(
        written,
        property,
        'is no address: https://..., github:owner/repo/path@ref, or a kind '
        'of an address resolver of the application',
      );
    }
    return RemoteAddress(
      property: property,
      written: written,
      uri: resolver.resolve(text, property: property),
    );
  }
}

/// An insecure address the configuration names while insecure connections
/// are not allowed: the application does not start.
final class InsecureConnectionException implements Exception {
  /// The [addresses] that are not secure.
  InsecureConnectionException(this.addresses);

  /// The addresses that are not secure.
  final List<RemoteAddress> addresses;

  @override
  String toString() =>
      'InsecureConnectionException: the connection is not secure: '
      '${addresses.join(', ')}. Use https, or set '
      '${RemoteAddressPolicy.property}=true to allow insecure connections '
      '(http, and https with an invalid certificate).';
}

/// Whether the addresses of the configuration may use insecure
/// connections: `http://`, and `https://` with a certificate that is
/// expired, self-signed or for another host. Not by default: an insecure
/// address stops the start. With `spring.remote.allow-insecure=true` they
/// work, and a warning lists them.
///
/// ```yaml
/// spring:
///   remote:
///     allow-insecure: true   # a theme server of the local network
/// ```
///
/// A browser checks certificates by itself: on the web only `http://` is
/// allowed this way.
final class RemoteAddressPolicy {
  /// A policy that allows insecure connections when [allowInsecure].
  const RemoteAddressPolicy({this.allowInsecure = false});

  /// Reads [property] from [properties]; `false` when it is not set.
  factory RemoteAddressPolicy.of(PropertyResolver properties) =>
      RemoteAddressPolicy(
        allowInsecure:
            properties.getPropertyAs<bool>(property, defaultValue: false) ??
            false,
      );

  /// The property that allows insecure connections.
  static const property = 'spring.remote.allow-insecure';

  static const _log = SpringLog('spring_core_dart.RemoteAddressPolicy');

  /// Whether insecure connections are allowed.
  final bool allowInsecure;

  /// Checks [addresses]: throws an [InsecureConnectionException] naming
  /// the insecure ones unless they are allowed; then logs a warning that
  /// lists them. Returns the insecure ones.
  List<RemoteAddress> check(Iterable<RemoteAddress> addresses) {
    final insecure = [
      for (final address in {...addresses})
        if (!address.secure) address,
    ];
    if (insecure.isEmpty) {
      return const [];
    }
    if (!allowInsecure) {
      throw InsecureConnectionException(insecure);
    }
    _log.warning(
      () =>
          'Insecure connections are allowed ($property): '
          '${insecure.join(', ')}',
    );
    return insecure;
  }
}
