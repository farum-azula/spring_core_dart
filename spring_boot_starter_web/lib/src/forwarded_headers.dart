import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.forwarded');

/// How the server reads the headers a reverse proxy adds
/// (`server.forward-headers-strategy`).
///
/// Spring Boot (Java): `ServerProperties.ForwardHeadersStrategy`.
enum ForwardHeadersStrategy {
  /// The headers are ignored, the default: the request is what reached
  /// the server.
  none,

  /// The headers of trusted proxies are applied (Spring Boot: the
  /// container's own support, Tomcat's `RemoteIpValve`).
  native,

  /// The same here (Spring Boot: Spring's `ForwardedHeaderFilter`).
  framework,
}

/// Applies the headers a trusted reverse proxy adds, so the application
/// sees the request as the client sent it: the scheme (`https` behind a
/// TLS proxy, so cookies get `Secure` and redirect URIs are `https://`),
/// the host and port, and the client's address.
///
/// Read: `Forwarded` (RFC 7239: `proto`, `host`, `for`), else
/// `X-Forwarded-Proto`, `X-Forwarded-Host`, `X-Forwarded-Port` and
/// `X-Forwarded-For`. The headers are applied only when the direct peer
/// is one of the trusted proxies (by default loopback and private networks,
/// as Tomcat's `RemoteIpValve`): a client that reaches the server
/// directly cannot claim to be on HTTPS or to come from another address.
/// For the scheme, host and port the first value counts (the proxy in
/// front of the others); for the address, the list is read from the
/// right and the first address that is not a trusted proxy is the
/// client. A value that is not a valid scheme, host, port or address is
/// ignored. The forwarded headers are removed for the rest of the chain.
///
/// The proxy must set these headers itself, replacing what a client
/// sent (nginx `proxy_set_header`, Traefik and cloud load balancers do).
///
/// The starter adds it, first of all filters, when
/// `server.forward-headers-strategy` is `native` or `framework`; the
/// proxies come from `server.forward-headers.trusted-proxies`
/// (addresses and CIDR ranges).
///
/// Spring (Java): `ForwardedHeaderFilter` (which trusts every peer) and
/// Tomcat's `RemoteIpValve` (which trusts `internalProxies`).
/// `X-Forwarded-Prefix` is not read.
final class ForwardedHeaderFilter implements WebFilter, Ordered {
  /// A filter applying the headers of [trustedProxies] (the default
  /// ranges when `null`).
  ForwardedHeaderFilter({List<String>? trustedProxies})
    : _trusted = [
        for (final range in trustedProxies ?? defaultTrustedProxies)
          _Range.parse(range),
      ];

  /// Loopback, private, link-local and shared (CGNAT) addresses, as
  /// Tomcat's default `internalProxies`.
  static const defaultTrustedProxies = [
    '127.0.0.0/8',
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '169.254.0.0/16',
    '100.64.0.0/10',
    '::1/128',
    'fc00::/7',
    'fe80::/10',
  ];

  /// The filter's order: before every other filter (the sessions at
  /// -1000, the security chain at -100).
  static const filterOrder = -10000;

  @override
  int get order => filterOrder;

  final List<_Range> _trusted;

  /// Whether [address] is one of the trusted proxies.
  bool isTrusted(String? address) {
    final parsed = address == null ? null : _ip(address);
    return parsed != null && _trusted.any((r) => r.contains(parsed));
  }

  static const _names = [
    'forwarded',
    'x-forwarded-proto',
    'x-forwarded-host',
    'x-forwarded-port',
    'x-forwarded-for',
  ];

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final present = _names.any((n) => request.headers[n] != null);
    if (!present) {
      return await chain.doFilter(request, response);
    }
    if (!isTrusted(request.remoteAddress)) {
      _log.debug(
        'Forwarded headers from ${request.remoteAddress} ignored: not a '
        'trusted proxy (server.forward-headers.trusted-proxies)',
      );
      return await chain.doFilter(request, response);
    }
    return await chain.doFilter(_Forwarded.of(request, this), response);
  }
}

final class _Forwarded extends ServerHttpRequestDecorator {
  _Forwarded(
    super.delegate,
    this.uri,
    this.remoteAddress,
    this.headers,
  );

  factory _Forwarded.of(ServerHttpRequest request, ForwardedHeaderFilter f) {
    String? proto;
    String? host;
    String? port;
    List<String> chain;
    final forwarded = request.headers.getAll('forwarded');
    if (forwarded.isNotEmpty) {
      final elements = _forwardedElements(forwarded);
      final first = elements.isEmpty
          ? const <String, String>{}
          : elements.first;
      proto = first['proto'];
      host = first['host'];
      chain = [for (final e in elements) ?e['for']];
    } else {
      proto = _first(request.headers['x-forwarded-proto']);
      host = _first(request.headers['x-forwarded-host']);
      port = _first(request.headers['x-forwarded-port']);
      chain = _list(request.headers.getAll('x-forwarded-for'));
    }

    var uri = request.uri;
    final scheme = proto?.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      uri = uri.replace(scheme: scheme, port: uri.port);
      // A new scheme without a port: the scheme's own (443, 80).
      if (host == null && port == null) {
        uri = Uri(
          scheme: scheme,
          host: uri.host,
          path: uri.path,
          query: uri.hasQuery ? uri.query : null,
        );
      }
    }
    if (host != null) {
      final parsed = _hostAndPort(host);
      if (parsed != null) {
        uri = Uri(
          scheme: uri.scheme,
          host: parsed.$1,
          port: parsed.$2,
          path: uri.path,
          query: uri.hasQuery ? uri.query : null,
        );
      }
    }
    if (port != null) {
      final number = int.tryParse(port);
      if (number != null && number > 0 && number < 65536) {
        uri = uri.replace(port: number);
      }
    }

    // The client: from the right, the first address that is not a
    // trusted proxy.
    var client = request.remoteAddress;
    for (final entry in chain.reversed) {
      final address = _address(entry);
      if (address == null) {
        break; // `unknown`, an obfuscated name, garbage: stop at the proxy
      }
      client = address;
      if (!f.isTrusted(address)) {
        break;
      }
    }

    final headers = HttpHeaders()..putAll(request.headers);
    ForwardedHeaderFilter._names.forEach(headers.remove);
    return _Forwarded(request, uri, client, headers);
  }

  @override
  final Uri uri;

  @override
  final String? remoteAddress;

  @override
  final HttpHeaders headers;

  @override
  bool get isSecure => uri.scheme == 'https' || uri.scheme == 'wss';

  static String? _first(String? value) {
    final first = value?.split(',').first.trim();
    return first == null || first.isEmpty ? null : first;
  }

  static List<String> _list(List<String> values) => [
    for (final value in values)
      for (final part in value.split(','))
        if (part.trim().isNotEmpty) part.trim(),
  ];

  // RFC 7239: elements by `,`, pairs by `;`, values maybe quoted.
  static List<Map<String, String>> _forwardedElements(List<String> values) => [
    for (final element in _list(values))
      {
        for (final pair in element.split(';'))
          if (pair.indexOf('=') case final i when i > 0)
            pair.substring(0, i).trim().toLowerCase(): _unquote(
              pair.substring(i + 1).trim(),
            ),
      },
  ];

  static String _unquote(String value) =>
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
      ? value.substring(1, value.length - 1)
      : value;

  static final _hostName = RegExp(r'^[A-Za-z0-9.-]{1,253}$');

  // `host`, `host:port`, `[v6]`, `[v6]:port`; null when not valid.
  static (String, int?)? _hostAndPort(String text) {
    String host;
    String? port;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end < 0) {
        return null;
      }
      host = text.substring(1, end);
      final rest = text.substring(end + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) {
          return null;
        }
        port = rest.substring(1);
      }
      if (_ip(host)?.length != 16) {
        return null;
      }
    } else {
      final colon = text.lastIndexOf(':');
      host = colon < 0 ? text : text.substring(0, colon);
      port = colon < 0 ? null : text.substring(colon + 1);
      if (!_hostName.hasMatch(host)) {
        return null;
      }
    }
    int? number;
    if (port != null) {
      number = int.tryParse(port);
      if (number == null || number < 1 || number > 65535) {
        return null;
      }
    }
    return (host, number);
  }

  // An address of `for`/`X-Forwarded-For`, without a port or brackets.
  static String? _address(String entry) {
    var text = entry;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      text = end < 0 ? text : text.substring(1, end);
    } else if (text.indexOf(':') case final i
        when i > 0 && text.lastIndexOf(':') == i) {
      text = text.substring(0, i); // v4:port
    }
    return _ip(text) == null ? null : text;
  }
}

// An address range: an address and a prefix length.
final class _Range {
  _Range(this._bytes, this._bits);

  factory _Range.parse(String text) {
    final slash = text.indexOf('/');
    final address = _ip(
      slash < 0 ? text.trim() : text.substring(0, slash).trim(),
    );
    if (address == null) {
      throw ArgumentError('Not an address or range: $text');
    }
    final length = address.length * 8;
    final bits = slash < 0 ? length : int.tryParse(text.substring(slash + 1));
    if (bits == null || bits < 0 || bits > length) {
      throw ArgumentError('Not an address or range: $text');
    }
    return _Range(address, bits);
  }

  final List<int> _bytes;
  final int _bits;

  bool contains(List<int> address) {
    var raw = address;
    // An IPv4 address mapped into IPv6 (::ffff:a.b.c.d) is that address.
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
}

// The bytes of an IPv4 (4) or IPv6 (16) address, or null.
List<int>? _ip(String text) {
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
