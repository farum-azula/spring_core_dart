import 'dart:typed_data';

/// An IP address, IPv4 or IPv6, as its bytes: what the outgoing address
/// checks (`InetAddressFilter`, `AllowedAddresses`) compare.
///
/// It exists because `dart:io`'s `InternetAddress` is not there in a
/// browser, and the checks run on every platform. Parse a literal with
/// [IpAddress.parse] or [IpAddress.tryParse]; a transport on `dart:io`
/// makes one from the bytes of a resolved address
/// ([IpAddress.fromBytes]).
///
/// An IPv6 address that carries an IPv4 one (`::ffff:127.0.0.1`, the NAT64
/// prefix `64:ff9b::/96`, 6to4 `2002::/16`) is classified by that IPv4
/// address too ([embeddedIPv4]), so `::ffff:127.0.0.1` is a loopback
/// address for the checks.
///
/// ```dart
/// IpAddress.parse('10.0.0.5').isV4; // true
/// IpAddress.parse('[::1]').toString(); // '::1'
/// IpAddress.tryParse('api.neon.books'); // null: a host name
/// ```
///
/// Spring (Java): `java.net.InetAddress` of an address literal
/// (`InetAddress.ofLiteral("10.0.0.5")`).
final class IpAddress {
  IpAddress._(this.bytes);

  /// The address of the 4 (IPv4) or 16 (IPv6) [bytes]. Throws an
  /// [ArgumentError] for any other length.
  factory IpAddress.fromBytes(List<int> bytes) {
    if (bytes.length != 4 && bytes.length != 16) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'An IP address has 4 or 16 bytes',
      );
    }
    return IpAddress._(Uint8List.fromList(bytes));
  }

  /// The address written as [text]: dotted IPv4 (`192.168.0.1`) or IPv6
  /// (`::1`, `[::1]`, `fe80::1%en0` with its zone left out). Throws a
  /// [FormatException] for anything else, a host name included.
  factory IpAddress.parse(String text) =>
      tryParse(text) ??
      (throw FormatException('Not an IP address literal', text));

  /// The address written as [text] (see [IpAddress.parse]), or `null`
  /// when it is not an address literal (a host name).
  ///
  /// IPv4 is read strictly: four decimal numbers of 0–255 without leading
  /// zeros. `0x7f.1` or `0177.0.0.1` are no literals here (a resolver may
  /// read them as `127.0.0.1`, which is why a host name is checked again
  /// after resolution).
  static IpAddress? tryParse(String text) {
    var value = text.trim();
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) {
      return null;
    }
    if (value.contains(':')) {
      final zone = value.indexOf('%');
      final address = zone < 0 ? value : value.substring(0, zone);
      try {
        return IpAddress._(Uint8List.fromList(Uri.parseIPv6Address(address)));
      } on FormatException {
        return null;
      }
    }
    final parts = value.split('.');
    if (parts.length != 4) {
      return null;
    }
    final bytes = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      final part = parts[i];
      if (part.isEmpty ||
          part.length > 3 ||
          (part.length > 1 && part.startsWith('0')) ||
          part.codeUnits.any((unit) => unit < 0x30 || unit > 0x39)) {
        return null;
      }
      final number = int.parse(part);
      if (number > 255) {
        return null;
      }
      bytes[i] = number;
    }
    return IpAddress._(bytes);
  }

  /// The address bytes: 4 for IPv4, 16 for IPv6. Do not change them.
  final Uint8List bytes;

  /// Whether it is an IPv4 address.
  bool get isV4 => bytes.length == 4;

  /// The IPv4 address an IPv6 address carries, or `null`: IPv4-mapped
  /// (`::ffff:a.b.c.d`), IPv4-compatible (`::a.b.c.d`, not `::` and
  /// `::1`), NAT64 (`64:ff9b::a.b.c.d`) and 6to4 (`2002:aabb:ccdd::`).
  /// `null` for an IPv4 address.
  IpAddress? get embeddedIPv4 {
    if (isV4) {
      return null;
    }
    bool zeros(int from, int to) {
      for (var i = from; i < to; i++) {
        if (bytes[i] != 0) {
          return false;
        }
      }
      return true;
    }

    IpAddress last4() => IpAddress._(Uint8List.sublistView(bytes, 12, 16));
    if (zeros(0, 10) && bytes[10] == 0xff && bytes[11] == 0xff) {
      return last4();
    }
    if (zeros(0, 12) && !(zeros(12, 15) && bytes[15] <= 1)) {
      return last4();
    }
    if (bytes[0] == 0x00 &&
        bytes[1] == 0x64 &&
        bytes[2] == 0xff &&
        bytes[3] == 0x9b &&
        zeros(4, 12)) {
      return last4();
    }
    if (bytes[0] == 0x20 && bytes[1] == 0x02) {
      return IpAddress._(Uint8List.sublistView(bytes, 2, 6));
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! IpAddress || other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  /// The address in its usual form: `10.0.0.5`, or IPv6 in lower case
  /// with the longest run of zero groups as `::` (`fe80::1`).
  @override
  String toString() {
    if (isV4) {
      return bytes.join('.');
    }
    final groups = [
      for (var i = 0; i < 16; i += 2) (bytes[i] << 8) | bytes[i + 1],
    ];
    var bestStart = -1;
    var bestLength = 1;
    for (var i = 0; i < 8;) {
      if (groups[i] != 0) {
        i++;
        continue;
      }
      var end = i;
      while (end < 8 && groups[end] == 0) {
        end++;
      }
      if (end - i > bestLength) {
        bestStart = i;
        bestLength = end - i;
      }
      i = end;
    }
    String hex(Iterable<int> part) =>
        part.map((group) => group.toRadixString(16)).join(':');
    if (bestStart < 0) {
      return hex(groups);
    }
    return '${hex(groups.take(bestStart))}::'
        '${hex(groups.skip(bestStart + bestLength))}';
  }
}

/// A block of IP addresses in CIDR notation (`10.0.0.0/8`, `fe80::/10`),
/// or a single address (`/32`, `/128`).
///
/// ```dart
/// final block = IpAddressRange.parse('192.168.0.0/16');
/// block.contains(IpAddress.parse('192.168.4.2')); // true
/// block.contains(IpAddress.parse('::ffff:192.168.4.2')); // true
/// ```
///
/// Spring (Java): the CIDR blocks Spring Boot's `InetAddressFilter.of`
/// reads (`InetAddressFilter.of("192.168.0.0/24")`).
final class IpAddressRange {
  /// The block of the addresses whose first [prefixLength] bits are those
  /// of [address]. Throws an [ArgumentError] when [prefixLength] is out of
  /// 0–32 (IPv4) or 0–128 (IPv6).
  factory IpAddressRange(IpAddress address, int prefixLength) {
    final bits = address.bytes.length * 8;
    if (prefixLength < 0 || prefixLength > bits) {
      throw ArgumentError.value(
        prefixLength,
        'prefixLength',
        'Must be within 0-$bits',
      );
    }
    return IpAddressRange._(address, prefixLength);
  }

  /// The block written as [text]: `address/prefix`, or an address alone
  /// (the block of that one address). Throws a [FormatException]
  /// otherwise.
  factory IpAddressRange.parse(String text) {
    final slash = text.indexOf('/');
    final address = IpAddress.tryParse(
      slash < 0 ? text : text.substring(0, slash),
    );
    if (address == null) {
      throw FormatException('Not an IP address or CIDR block', text);
    }
    if (slash < 0) {
      return IpAddressRange._(address, address.bytes.length * 8);
    }
    final prefix = int.tryParse(text.substring(slash + 1).trim());
    if (prefix == null || prefix < 0 || prefix > address.bytes.length * 8) {
      throw FormatException('Not a CIDR prefix length', text);
    }
    return IpAddressRange._(address, prefix);
  }

  IpAddressRange._(this.address, this.prefixLength);

  /// The first address (with the bits after the prefix as written).
  final IpAddress address;

  /// How many leading bits the addresses of the block share.
  final int prefixLength;

  /// Whether [other] is in the block. An IPv6 address that carries an
  /// IPv4 one ([IpAddress.embeddedIPv4]) is in an IPv4 block when that
  /// IPv4 address is.
  bool contains(IpAddress other) {
    if (other.bytes.length != address.bytes.length) {
      final embedded = other.embeddedIPv4;
      return embedded != null && address.isV4 && contains(embedded);
    }
    return _samePrefix(address.bytes, other.bytes, prefixLength);
  }

  /// Whether every address of [other] is in this block.
  bool covers(IpAddressRange other) =>
      other.address.bytes.length == address.bytes.length &&
      other.prefixLength >= prefixLength &&
      contains(other.address);

  static bool _samePrefix(Uint8List a, Uint8List b, int bits) {
    final whole = bits ~/ 8;
    for (var i = 0; i < whole; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    final rest = bits % 8;
    if (rest == 0) {
      return true;
    }
    final mask = (0xff << (8 - rest)) & 0xff;
    return (a[whole] & mask) == (b[whole] & mask);
  }

  @override
  bool operator ==(Object other) =>
      other is IpAddressRange &&
      other.address == address &&
      other.prefixLength == prefixLength;

  @override
  int get hashCode => Object.hash(address, prefixLength);

  @override
  String toString() => '$address/$prefixLength';
}
