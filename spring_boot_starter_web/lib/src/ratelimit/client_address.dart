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
/// ```dart
/// final addresses = TrustedProxyClientAddressResolver(
///   trustedProxies: ['173.245.48.0/20', '2400:cb00::/32'],
/// );
/// ```
final class TrustedProxyClientAddressResolver implements ClientAddressResolver {
  /// A resolver that believes [header] from [trustedProxies] (addresses
  /// and CIDR ranges). Throws an [ArgumentError] for a range that is
  /// none.
  TrustedProxyClientAddressResolver({
    List<String> trustedProxies = const [],
    this.header = 'X-Forwarded-For',
  }) : _trusted = [
         for (final range in trustedProxies)
           if (range.trim().isNotEmpty) IpRange.parse(range.trim()),
       ];

  /// The header the proxies put the client's address in.
  final String header;

  final List<IpRange> _trusted;

  /// Whether [address] is one of the trusted proxies.
  bool isTrusted(String? address) =>
      address != null && _trusted.any((r) => r.containsAddress(address));

  @override
  String? resolve(ServerHttpRequest request) {
    final peer = _address(request.remoteAddress ?? '');
    if (_trusted.isEmpty || !isTrusted(peer)) {
      return peer ?? request.remoteAddress;
    }
    var client = peer;
    final entries = [
      for (final value in request.headers.getAll(header))
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim(),
    ];
    for (final entry in entries.reversed) {
      final address = _address(entry);
      if (address == null) {
        break;
      }
      client = address;
      if (!isTrusted(address)) {
        break;
      }
    }
    return client;
  }

  // An entry without its port or brackets, in one spelling; null when it
  // is no address.
  static String? _address(String entry) {
    var text = entry;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      text = end < 0 ? text : text.substring(1, end);
    } else if (text.indexOf(':') case final i
        when i > 0 && text.lastIndexOf(':') == i) {
      text = text.substring(0, i);
    }
    final bytes = parseIpAddress(text);
    return bytes == null ? null : _canonical(bytes);
  }

  // One spelling per address, so `2001:DB8::1` and `2001:db8:0:0:0:0:0:1`
  // share a bucket.
  static String _canonical(List<int> bytes) {
    if (bytes.length == 4) {
      return bytes.join('.');
    }
    // An IPv4 address mapped into IPv6 is that IPv4 address.
    if (bytes.sublist(0, 10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff) {
      return bytes.sublist(12).join('.');
    }
    return [
      for (var i = 0; i < 16; i += 2)
        ((bytes[i] << 8) | bytes[i + 1]).toRadixString(16),
    ].join(':');
  }
}
