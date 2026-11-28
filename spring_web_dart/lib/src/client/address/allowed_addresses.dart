import 'package:spring_web_dart/src/client/address/inet_address_filter.dart';
import 'package:spring_web_dart/src/client/address/ip_address.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';

/// The hosts and addresses an HTTP transport may call: every other one is
/// denied, private networks and loopback included. The guard against
/// server-side request forgery (SSRF), where a URL that comes from outside
/// makes a server call into its own network or its cloud's metadata
/// service.
///
/// An entry is one of:
///
/// - a host name, `api.neon.books` (any case, a trailing dot ignored);
///   `*.neon.books` for its subdomains (not `neon.books` itself); `*` for
///   any host name and any public address;
/// - an address literal, `203.0.113.7` or `2001:db8::7`;
/// - a CIDR block, `10.0.0.0/8` or `fd00::/8`;
/// - a URL, whose host is taken (`https://api.neon.books`).
///
/// The rules:
///
/// 1. The host of the URL must be on the list: by name, or, for an
///    address literal, by an address or block that holds it (or `*` for a
///    public one). A relative URL (no host: in a browser, the page's own
///    origin) is allowed.
/// 2. On `dart:io` the transport resolves a host name itself, checks every
///    address it gets and connects to an address it checked, never to
///    what a second lookup might return (DNS rebinding). Each redirect is
///    checked the same way.
/// 3. A public address of an allowed host is allowed. An address of
///    [restrictedBlocks] (loopback, private networks, link-local, cloud
///    metadata, ...) is denied unless an address or block on the list
///    holds it **and lies within each restricted block the address is
///    in**: `10.0.0.0/8` opens `10.1.2.3`, `0.0.0.0/0` opens no private
///    address, and `169.254.0.0/16` does not open the metadata address
///    `169.254.169.254`, which only an entry of its own opens. The one
///    exception: an allowed `localhost` (or `*.localhost`) may resolve
///    to loopback.
/// 4. When [filter] is set, every address must also match it.
///
/// An IPv6 address that carries an IPv4 one (`::ffff:127.0.0.1`, NAT64,
/// 6to4) counts as that IPv4 address.
///
/// In a browser (`FetchHttpTransport`) and other `fetch` runtimes the
/// transport cannot resolve names: only rule 1 is checked, so a host on the
/// list is trusted to resolve to what it should; list only hosts you
/// control. A browser also follows redirects by itself, without showing
/// them; a server runtime (Deno, workerd, Node) gets them one by one, and
/// each is checked.
///
/// A denied call fails with a [FilteredHostException] that names the host,
/// the reason and [remedy] (the starter's: the property to set).
///
/// ```dart
/// final allowed = AllowedAddresses([
///   'api.neon.books',
///   'localhost',
///   '10.20.0.0/16', // the inventory service's network
/// ]);
/// final transport = IoHttpTransport(allowedAddresses: allowed);
/// ```
///
/// Spring (Java): Spring Boot 4.1 filters the resolved addresses of its
/// HTTP clients with an `InetAddressFilter` (`HttpClientSettings`), and
/// allows everything until one is set; here everything is denied until
/// allowed, and host names are checked too.
final class AllowedAddresses {
  /// The allow list of [entries] (see the class), and [filter] that every
  /// address must also match. [remedy] ends the message of a denied call:
  /// what to change to allow it. Throws an [ArgumentError] for an entry
  /// that is none of the forms above (a port, a path, a blank).
  AllowedAddresses(
    Iterable<String> entries, {
    this.filter,
    this.remedy = 'add it to the AllowedAddresses of the HTTP transport',
  }) {
    entries.forEach(_add);
  }

  /// No host at all: every call with a host is denied.
  AllowedAddresses.none({
    this.filter,
    this.remedy = 'add it to the AllowedAddresses of the HTTP transport',
  });

  /// What every address must match besides the list; `null`: nothing more.
  final InetAddressFilter? filter;

  /// The end of the message of a denied call, saying how to allow it
  /// (`add it to spring.http.clients.allowed-addresses`).
  final String remedy;

  final _hosts = <String>{};
  final _suffixes = <String>[];
  final _ranges = <IpAddressRange>[];
  var _anyHost = false;

  /// The blocks an address is denied in unless an entry opens it (rule 3),
  /// with what each is: loopback, unspecified, private networks,
  /// link-local, cloud metadata services, shared address space, multicast,
  /// reserved and the other special-purpose blocks of RFC 6890.
  static final List<({String kind, IpAddressRange block})> restrictedBlocks = [
    for (final (kind, block) in const [
      ('loopback', '127.0.0.0/8'),
      ('loopback', '::1/128'),
      ('unspecified', '0.0.0.0/8'),
      ('unspecified', '::/128'),
      ('private', '10.0.0.0/8'),
      ('private', '172.16.0.0/12'),
      ('private', '192.168.0.0/16'),
      ('private', 'fc00::/7'),
      ('link-local', '169.254.0.0/16'),
      ('link-local', 'fe80::/10'),
      ('cloud metadata', '169.254.169.254/32'),
      ('cloud metadata', '169.254.170.2/32'),
      ('cloud metadata', 'fd00:ec2::254/128'),
      ('cloud metadata', '100.100.100.200/32'),
      ('shared address space', '100.64.0.0/10'),
      ('multicast', '224.0.0.0/4'),
      ('multicast', 'ff00::/8'),
      ('reserved', '240.0.0.0/4'),
      ('special purpose', '192.0.0.0/24'),
      ('special purpose', '192.0.2.0/24'),
      ('special purpose', '192.88.99.0/24'),
      ('special purpose', '198.18.0.0/15'),
      ('special purpose', '198.51.100.0/24'),
      ('special purpose', '203.0.113.0/24'),
      ('special purpose', '100::/64'),
      ('special purpose', '2001::/23'),
      ('special purpose', '2001:db8::/32'),
    ])
      (kind: kind, block: IpAddressRange.parse(block)),
  ];

  void _add(String raw) {
    var entry = raw.trim();
    if (entry.isEmpty) {
      throw ArgumentError.value(raw, 'entries', 'A blank allow-list entry');
    }
    if (entry.contains('://')) {
      final host = Uri.tryParse(entry)?.host ?? '';
      if (host.isEmpty) {
        throw ArgumentError.value(raw, 'entries', 'A URL without a host');
      }
      entry = host;
    }
    if (entry == '*') {
      _anyHost = true;
      return;
    }
    if (IpAddress.tryParse(entry) != null || entry.contains('/')) {
      try {
        _ranges.add(_canonical(IpAddressRange.parse(entry)));
      } on FormatException {
        throw ArgumentError.value(
          raw,
          'entries',
          'Not an address literal or a CIDR block',
        );
      }
      return;
    }
    final name = _normalize(entry);
    if (name.contains(RegExp(r'[\s:/?#@\[\]]')) || name.isEmpty) {
      throw ArgumentError.value(
        raw,
        'entries',
        'Not a host name (no port, path or user is allowed)',
      );
    }
    if (name.startsWith('*.')) {
      _suffixes.add(name.substring(1));
    } else if (name.contains('*')) {
      throw ArgumentError.value(
        raw,
        'entries',
        'Only a leading "*." is allowed',
      );
    } else {
      _hosts.add(name);
    }
  }

  static String _normalize(String host) {
    final lower = host.toLowerCase();
    return lower.endsWith('.') ? lower.substring(0, lower.length - 1) : lower;
  }

  // An IPv6 address that carries an IPv4 one counts as that IPv4 address.
  static IpAddress _canonicalAddress(IpAddress address) =>
      address.embeddedIPv4 ?? address;

  static IpAddressRange _canonical(IpAddressRange range) {
    final embedded = range.address.embeddedIPv4;
    if (embedded == null || range.prefixLength < 96) {
      return range;
    }
    return IpAddressRange(embedded, range.prefixLength - 96);
  }

  static bool _isLocalhost(String host) =>
      host == 'localhost' || host.endsWith('.localhost');

  /// Adds the host name [host] to the list from now on: a name learned at
  /// run time from a source the application trusts. The OAuth2 client adds
  /// the hosts of the endpoints a provider's discovery document names, once
  /// it has checked the document's issuer.
  ///
  /// Only a plain host name is taken: never an address literal, a block, a
  /// wildcard or a `localhost` name, so what it opens is the public
  /// addresses of that name (rule 3 still denies the restricted ones, and
  /// [filter] still applies). Returns whether [host] is allowed now;
  /// `false` for what it does not take.
  bool allowHostName(String host) {
    final name = _normalize(host.trim());
    if (name.isEmpty ||
        IpAddress.tryParse(name) != null ||
        _isLocalhost(name) ||
        name.contains(RegExp(r'[\s:/?#@\[\]*%]'))) {
      return false;
    }
    _hosts.add(name);
    return true;
  }

  /// Whether the host name [host] (not an address literal) is on the list.
  bool allowsHostName(String host) {
    final name = _normalize(host);
    return _anyHost ||
        _hosts.contains(name) ||
        _suffixes.any((suffix) => name.endsWith(suffix));
  }

  /// Checks the host of [url] (rule 1), on every platform; throws a
  /// [FilteredHostException] when it is denied. A URL without a host (a
  /// relative one, resolved by a browser against the page) passes.
  void checkUrl(Uri url) {
    final host = url.host;
    if (host.isEmpty) {
      return;
    }
    final literal = IpAddress.tryParse(host);
    if (literal == null) {
      if (!allowsHostName(host)) {
        throw FilteredHostException(
          host,
          'the host is not on the allow list',
          remedy: remedy,
        );
      }
      return;
    }
    final reason = _denial(literal, host: null);
    if (reason != null) {
      throw FilteredHostException(
        host,
        reason,
        address: literal,
        remedy: remedy,
      );
    }
  }

  /// The addresses of [resolved] (what the host name [host] resolved to,
  /// or its literal) that may be called, in their order (rules 3 and 4).
  /// Throws a [FilteredHostException] naming the first one denied when
  /// none may.
  List<IpAddress> allowedAddressesOf(
    String host,
    Iterable<IpAddress> resolved,
  ) {
    final allowed = <IpAddress>[];
    String? firstReason;
    IpAddress? firstDenied;
    final name = IpAddress.tryParse(host) == null ? _normalize(host) : null;
    for (final address in resolved) {
      final reason = _denial(address, host: name);
      if (reason == null) {
        allowed.add(address);
      } else if (firstReason == null) {
        firstReason = reason;
        firstDenied = address;
      }
    }
    if (allowed.isEmpty) {
      throw FilteredHostException(
        host,
        firstReason ?? 'the host resolved to no address',
        address: firstDenied,
        remedy: remedy,
      );
    }
    return allowed;
  }

  // Why [address] is denied (null: allowed); [host] is the allowed host
  // name it was resolved from, or null for an address literal.
  String? _denial(IpAddress address, {required String? host}) {
    final canonical = _canonicalAddress(address);
    final restricted = [
      for (final entry in restrictedBlocks)
        if (entry.block.contains(canonical)) entry,
    ];
    if (restricted.isEmpty) {
      final listed =
          host != null ||
          _anyHost ||
          _ranges.any((range) => range.contains(canonical));
      if (!listed) {
        return 'the address $address is not on the allow list';
      }
    } else {
      final loopbackOfLocalhost =
          host != null &&
          _isLocalhost(host) &&
          restricted.every((entry) => entry.kind == 'loopback');
      final opened =
          loopbackOfLocalhost ||
          _ranges.any(
            (range) =>
                range.contains(canonical) &&
                restricted.every((entry) => entry.block.covers(range)),
          );
      if (!opened) {
        final kinds = {for (final entry in restricted) entry.kind}.join(', ');
        return '${host == null ? 'the address' : 'it resolves to'} '
            '$address ($kinds), which is denied unless the address or a '
            'block within ${restricted.last.block} is on the allow list';
      }
    }
    if (filter case final filter? when !filter.matches(address)) {
      return 'the address $address does not match the InetAddressFilter';
    }
    return null;
  }

  @override
  String toString() {
    final entries = [
      if (_anyHost) '*',
      ..._hosts,
      for (final suffix in _suffixes) '*$suffix',
      for (final range in _ranges) '$range',
    ];
    return 'AllowedAddresses(${entries.join(', ')})';
  }
}

/// Thrown when a transport with [AllowedAddresses] refuses a call: its
/// host, or every address the host resolved to, is not allowed. No request
/// was sent, and another try would fail the same way, so it is not
/// retryable.
///
/// ```dart
/// try {
///   await client.get().uri('http://169.254.169.254/latest').retrieve()
///       .body<String>();
/// } on ResourceAccessException catch (error) {
///   error.cause; // a FilteredHostException
/// }
/// ```
///
/// Spring (Java): Spring Boot 4.1's `FilteredHostException`.
class FilteredHostException extends HttpTransportException {
  /// The call to [host] was refused for [reason]; [address] is the address
  /// denied, when there was one, and [remedy] says how to allow it.
  FilteredHostException(
    this.host,
    this.reason, {
    this.address,
    this.remedy = 'add it to the AllowedAddresses of the HTTP transport',
  }) : super(
         'Outgoing call to "$host" denied: $reason; $remedy',
         isRetryable: false,
       );

  /// The host of the URL, as written (a name or an address literal).
  final String host;

  /// The address that was denied, or `null` when the host name itself is
  /// not on the list.
  final IpAddress? address;

  /// Why the call was refused.
  final String reason;

  /// How to allow it: the property or the list to change.
  final String remedy;

  @override
  String toString() => 'FilteredHostException: $message';
}
