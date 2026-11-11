/// A range of IP addresses: one address (`203.0.113.7`, `2001:db8::1`) or
/// a CIDR block (`173.245.48.0/20`, `2400:cb00::/32`).
///
/// The server uses it for the lists of trusted proxies
/// (`server.forward-headers.trusted-proxies`,
/// `spring.web.rate-limit.trusted-proxies`).
///
/// ```dart
/// final cloudflare = IpRange.parse('173.245.48.0/20');
/// cloudflare.containsAddress('173.245.52.9'); // true
/// ```
///
/// Spring (Java): Spring Security's `IpAddressMatcher`.
final class IpRange {
  IpRange._(this._bytes, this._bits);

  /// Reads an address or a CIDR block. Throws an [ArgumentError] for
  /// anything else.
  factory IpRange.parse(String text) {
    final slash = text.indexOf('/');
    final address = parseIpAddress(
      slash < 0 ? text.trim() : text.substring(0, slash).trim(),
    );
    if (address == null) {
      throw ArgumentError('Not an address or range: $text');
    }
    final length = address.length * 8;
    final bits = slash < 0
        ? length
        : int.tryParse(text.substring(slash + 1).trim());
    if (bits == null || bits < 0 || bits > length) {
      throw ArgumentError('Not an address or range: $text');
    }
    return IpRange._(address, bits);
  }

  final List<int> _bytes;
  final int _bits;

  /// Whether the address of the bytes [address] ([parseIpAddress]) is in
  /// the range. An IPv4 address mapped into IPv6 (`::ffff:a.b.c.d`) is
  /// that IPv4 address.
  bool contains(List<int> address) {
    var raw = address;
    if (raw.length == 16 &&
        _bytes.length == 4 &&
        raw.sublist(0, 10).every((b) => b == 0) &&
        raw[10] == 0xff &&
        raw[11] == 0xff) {
      raw = raw.sublist(12);
    }
    if (raw.length != _bytes.length) {
      return false;
    }
    final full = _bits ~/ 8;
    for (var i = 0; i < full; i++) {
      if (raw[i] != _bytes[i]) {
        return false;
      }
    }
    final rest = _bits % 8;
    if (rest == 0) {
      return true;
    }
    final mask = (0xff << (8 - rest)) & 0xff;
    return (raw[full] & mask) == (_bytes[full] & mask);
  }

  /// Whether [address], as text, is in the range; `false` for text that
  /// is no address.
  bool containsAddress(String address) {
    final parsed = parseIpAddress(address);
    return parsed != null && contains(parsed);
  }
}

/// The bytes of an IPv4 (4) or IPv6 (16) address, or `null` when [text]
/// is neither.
List<int>? parseIpAddress(String text) {
  if (text.isEmpty || text.length > 45) {
    return null;
  }
  try {
    return Uri.parseIPv4Address(text);
  } on FormatException {
    // not IPv4
  }
  try {
    return Uri.parseIPv6Address(text);
  } on FormatException {
    return null;
  }
}
