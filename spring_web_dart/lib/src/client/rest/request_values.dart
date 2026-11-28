// What a RestClient request accepts in a header or a cookie: nothing that
// could end the header line or the cookie pair and start another, whatever
// the transport (dart:io and fetch refuse a line break themselves; another
// transport may not). Not exported: the request spec and the API version
// inserter call it.

/// Throws an [ArgumentError] when [name] is no HTTP header name (RFC 9110
/// token) or [value] holds a CR, an LF or a NUL, which would end the header
/// line and let the rest pass for another header.
void checkHeader(String name, String value) {
  if (name.isEmpty || !_isToken(name)) {
    throw ArgumentError.value(
      name,
      'name',
      r"is no header name (letters, digits and !#$%&'*+-.^_`|~ only)",
    );
  }
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit == 0x0D || unit == 0x0A || unit == 0x00) {
      throw ArgumentError.value(
        value,
        'header $name',
        'must not hold a line break (CR, LF) or NUL',
      );
    }
  }
}

/// Throws an [ArgumentError] when the cookie [name] is no token or [value]
/// holds a control character or a `;`, which would end the pair and add
/// another cookie to the `Cookie` header.
void checkCookie(String name, String value) {
  if (name.isEmpty || !_isToken(name)) {
    throw ArgumentError.value(
      name,
      'name',
      r"is no cookie name (letters, digits and !#$%&'*+-.^_`|~ only)",
    );
  }
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit < 0x20 || unit == 0x7F || unit == 0x3B) {
      throw ArgumentError.value(
        value,
        'cookie $name',
        'must not hold a control character or ";"',
      );
    }
  }
}

bool _isToken(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final letterOrDigit =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A);
    if (!letterOrDigit && !_tokenSymbols.contains(unit)) {
      return false;
    }
  }
  return true;
}

// !#$%&'*+-.^_`|~
const _tokenSymbols = {
  0x21,
  0x23,
  0x24,
  0x25,
  0x26,
  0x27,
  0x2A,
  0x2B,
  0x2D,
  0x2E,
  0x5E,
  0x5F,
  0x60,
  0x7C,
  0x7E,
};
