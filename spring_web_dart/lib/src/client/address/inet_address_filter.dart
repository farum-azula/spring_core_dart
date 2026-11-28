import 'package:spring_web_dart/src/client/address/ip_address.dart';

/// Decides whether an outgoing call may go to an IP address, as Spring
/// Boot's `InetAddressFilter`: a test of one address, built from the
/// factories below and combined with [and], [or], [andNot] and [negate].
///
/// A transport with `AllowedAddresses` asks it about every address a host
/// name resolves to (on `dart:io`), on top of the allow list: an address
/// must pass both. Use it to narrow what the allow list lets through, for
/// example to keep a host that is allowed by name off a block of your
/// network.
///
/// ```dart
/// // Only the 192.168.0.0/24 network, without its gateway.
/// final filter = InetAddressFilter.of(['192.168.0.0/24'])
///     .andNot(InetAddressFilter.of(['192.168.0.1']));
/// filter.matches(IpAddress.parse('192.168.0.7')); // true
/// ```
///
/// Spring (Java), Spring Boot 4.1:
/// ```java
/// InetAddressFilter.of("192.168.0.0/24").andNot("192.168.0.1");
/// ```
abstract class InetAddressFilter {
  /// A filter for subclasses; most code uses the factories instead.
  const InetAddressFilter();

  /// The filter that asks [predicate].
  const factory InetAddressFilter.adapt(bool Function(IpAddress) predicate) =
      _PredicateFilter;

  /// The filter of the [addresses]: each an address literal (`10.0.0.5`,
  /// `::1`) or a CIDR block (`10.0.0.0/8`, `fd00::/8`). Throws a
  /// [FormatException] for anything else.
  factory InetAddressFilter.of(Iterable<String> addresses) => _RangesFilter([
    for (final entry in addresses) IpAddressRange.parse(entry),
  ]);

  /// Every address.
  static const InetAddressFilter all = _ConstantFilter(true);

  /// No address.
  static const InetAddressFilter none = _ConstantFilter(false);

  /// The addresses that are not all zeros (`0.0.0.0`, `::`).
  static const InetAddressFilter routable = _PredicateFilter(_isRoutable);

  /// The multicast addresses (`224.0.0.0/4`, `ff00::/8`).
  static final InetAddressFilter multicast = InetAddressFilter.of([
    '224.0.0.0/4',
    'ff00::/8',
  ]);

  /// The private networks and loopback: `127.0.0.0/8`, `10.0.0.0/8`,
  /// `172.16.0.0/12`, `192.168.0.0/16`, `::1` and the unique local
  /// addresses `fc00::/7`, as Spring Boot's `internalAddresses()`.
  static final InetAddressFilter internalAddresses = routable.and(
    InetAddressFilter.of([
      '127.0.0.0/8',
      '10.0.0.0/8',
      '172.16.0.0/12',
      '192.168.0.0/16',
      '::1/128',
      'fc00::/7',
    ]),
  );

  /// The special-purpose blocks of RFC 6890 (loopback, link-local, shared
  /// address space, documentation, benchmarking, reserved, ...) and the
  /// [internalAddresses], as Spring Boot's `specialPurpose()`.
  static final InetAddressFilter specialPurpose = InetAddressFilter.of(
    specialPurposeBlocks,
  ).or(internalAddresses);

  /// The addresses of the public internet: [routable], not [multicast] and
  /// not [specialPurpose], as Spring Boot's `externalAddresses()`.
  static final InetAddressFilter externalAddresses = routable
      .andNot(multicast)
      .andNot(specialPurpose);

  /// The blocks of [specialPurpose] in CIDR notation (Spring Boot's list).
  static const List<String> specialPurposeBlocks = [
    '0.0.0.0/8',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
    '192.0.0.0/24',
    '192.0.2.0/24',
    '192.88.99.0/24',
    '198.18.0.0/15',
    '198.51.100.0/24',
    '203.0.113.0/24',
    '240.0.0.0/4',
    '255.255.255.255/32',
    '::1/128',
    '::/128',
    '64:ff9b::/96',
    '100::/64',
    '2001::/23',
    '2001::/32',
    '2001:2::/48',
    '2001:db8::/32',
    '2001:10::/28',
    '2002::/16',
    'fc00::/7',
    'fe80::/10',
  ];

  /// Whether a call may go to [address].
  bool matches(IpAddress address);

  /// Both this filter and [other] must match.
  InetAddressFilter and(InetAddressFilter other) =>
      _PredicateFilter((address) => matches(address) && other.matches(address));

  /// This filter must match and [other] must not.
  InetAddressFilter andNot(InetAddressFilter other) => _PredicateFilter(
    (address) => matches(address) && !other.matches(address),
  );

  /// This filter or [other] must match.
  InetAddressFilter or(InetAddressFilter other) =>
      _PredicateFilter((address) => matches(address) || other.matches(address));

  /// The addresses this filter does not match.
  InetAddressFilter negate() =>
      _PredicateFilter((address) => !matches(address));

  static bool _isRoutable(IpAddress address) =>
      address.bytes.any((byte) => byte != 0);
}

final class _PredicateFilter extends InetAddressFilter {
  const _PredicateFilter(this._predicate);

  final bool Function(IpAddress) _predicate;

  @override
  bool matches(IpAddress address) => _predicate(address);
}

final class _ConstantFilter extends InetAddressFilter {
  const _ConstantFilter(this._value);

  final bool _value;

  @override
  bool matches(IpAddress address) => _value;
}

final class _RangesFilter extends InetAddressFilter {
  _RangesFilter(this._ranges);

  final List<IpAddressRange> _ranges;

  @override
  bool matches(IpAddress address) =>
      _ranges.any((range) => range.contains(address));
}
