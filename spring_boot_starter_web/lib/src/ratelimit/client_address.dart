import 'package:spring_boot_starter_web/src/ip_range.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Who sent a request, as the rate limiter counts it: the address a
/// bucket keyed by `ip` belongs to.
///
/// The default ([TrustedProxyClientAddressResolver]) is the connection's
/// own address, or what the trusted proxies say. An application whose
/// front end names the client another way declares a bean of this type.
///
/// ```dart
/// // Behind a gateway that signs the client's address.
/// @Component()
/// class GatewayAddress implements ClientAddressResolver {
///   @override
///   String? resolve(ServerHttpRequest request) =>
///       verified(request.headers['X-Gateway-Client']);
/// }
/// ```
///
/// Spring (Java): Spring Cloud Gateway's `RemoteAddressResolver`
/// (`XForwardedRemoteAddressResolver.maxTrustedIndex`).
abstract interface class ClientAddressResolver {
  /// The client's address, or `null` when it is not known.
  String? resolve(ServerHttpRequest request);
}

/// The client's address behind reverse proxies that are known
/// (`spring.web.rate-limit.trusted-proxies`,
/// `spring.web.rate-limit.client-address-header`).
///
/// - A connection that does not come from one of `trustedProxies`: its
///   own address. Its headers are not read, so a client cannot choose the
///   bucket it is counted in.
/// - A connection from a trusted proxy: the entries of [header] are read
///   from the right. The last one was added by the proxy that connected;
///   when it names another trusted proxy, the one before it was added by
///   that proxy, and so on. The first entry that is not a trusted proxy
///   is the client. Everything to the left of it is what the client
///   itself sent, and is ignored.
/// - Without trusted proxies no header is ever read.
///
/// An entry that is no address ends the walk at the proxy before it.
///
/// An IPv6 client is its network, not its address: the first
/// [ipv6PrefixLength] bits (64 by default,
/// `spring.web.rate-limit.ipv6-prefix-length`), the rest zeroed. A
/// provider gives a client a whole /64, and the client picks a new
/// address in it whenever it likes; counted by address, it would never
/// reach a limit and would fill the store with buckets of one request.
/// The trusted proxies are still compared by their whole address. IPv4
/// addresses, and those mapped into IPv6 (`::ffff:a.b.c.d`), are counted
/// whole.
///
/// ```dart
/// final addresses = TrustedProxyClientAddressResolver(
///   trustedProxies: ['173.245.48.0/20', '2400:cb00::/32'],
/// );
/// ```
final class TrustedProxyClientAddressResolver implements ClientAddressResolver {
  /// A resolver that believes [header] from [trustedProxies] (addresses
  /// and CIDR ranges) and counts an IPv6 client by the first
  /// [ipv6PrefixLength] bits of its address. Throws an [ArgumentError]
  /// for a range that is none and for a prefix length outside 1..128.
  TrustedProxyClientAddressResolver({
    List<String> trustedProxies = const [],
    this.header = 'X-Forwarded-For',
    this.ipv6PrefixLength = 64,
  }) : _trusted = [
         for (final range in trustedProxies)
           if (range.trim().isNotEmpty) IpRange.parse(range.trim()),
       ] {
    if (ipv6PrefixLength < 1 || ipv6PrefixLength > 128) {
      throw ArgumentError.value(
        ipv6PrefixLength,
        'ipv6PrefixLength',
        'Not a prefix length of an IPv6 address (1..128)',
      );
    }
  }

  /// The header the proxies put the client's address in.
  final String header;

  /// How many bits of an IPv6 address say who the client is; 128 counts
  /// every address by itself.
  final int ipv6PrefixLength;

  final List<IpRange> _trusted;

  /// Whether [address] is one of the trusted proxies.
  bool isTrusted(String? address) =>
      address != null && _trusted.any((r) => r.containsAddress(address));

  bool _isTrusted(List<int> address) =>
      _trusted.any((r) => r.contains(address));

  @override
  String? resolve(ServerHttpRequest request) {
    final peer = _address(request.remoteAddress ?? '');
    if (peer == null) {
      return request.remoteAddress;
    }
    if (_trusted.isEmpty || !_isTrusted(peer)) {
      return _counted(peer);
    }
    var client = peer;
    final entries = [
      for (final value in request.headers.getAll(header))
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim(),
    ];
    // The walk compares whole addresses: a proxy is trusted by its own
    // address, not by the network the client would be counted as.
    for (final entry in entries.reversed) {
      final address = _address(entry);
      if (address == null) {
        break;
      }
      client = address;
      if (!_isTrusted(address)) {
        break;
      }
    }
    return _counted(client);
  }

  // The bytes of an entry without its port or brackets; null when it is
  // no address. An IPv4 address mapped into IPv6 is that IPv4 address.
  static List<int>? _address(String entry) {
    var text = entry;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      text = end < 0 ? text : text.substring(1, end);
    } else if (text.indexOf(':') case final i
        when i > 0 && text.lastIndexOf(':') == i) {
      text = text.substring(0, i);
    }
    final bytes = parseIpAddress(text);
    if (bytes != null &&
        bytes.length == 16 &&
        bytes.sublist(0, 10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff) {
      return bytes.sublist(12);
    }
    return bytes;
  }

  // What the address is counted as, in one spelling, so `2001:DB8::1`
  // and `2001:db8:0:0:0:0:0:1` share a bucket: an IPv4 address as it
  // is, an IPv6 address with the bits past the prefix zeroed.
  String _counted(List<int> bytes) {
    if (bytes.length == 4) {
      return bytes.join('.');
    }
    final network = [
      for (var i = 0; i < 16; i++)
        switch (ipv6PrefixLength - i * 8) {
          >= 8 => bytes[i],
          <= 0 => 0,
          final bits => bytes[i] & (0xff << (8 - bits)) & 0xff,
        },
    ];
    return [
      for (var i = 0; i < 16; i += 2)
        ((network[i] << 8) | network[i + 1]).toRadixString(16),
    ].join(':');
  }
}
