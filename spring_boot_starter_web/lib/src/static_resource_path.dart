// The checks of a request path before it is looked up in a location of
// static resources. Fail closed: anything that could name another file than
// the plain one asked for, on any file system, is refused (the request is a
// 404), even when a file of that name could exist.
//
// Spring's ResourceHttpRequestHandler.processPath / isInvalidPath /
// isInvalidEncodedPath and PathResourceResolver.checkResource do part of
// this; the rest (control characters, Windows names, dot files, confusable
// characters, a strict UTF-8 decoding) is this starter's own.

/// The segments of [pathWithinMapping] (the part of the request path under
/// the mapping's pattern, still percent-encoded), each decoded once, or
/// `null` when the path is refused.
///
/// The segments are what a location is asked for: `css/app.css` gives
/// `[css, app.css]`. A path that ends with `/` gives its segments and an
/// empty last one (a directory, never served as a file). Refused, so the
/// request is a 404 whatever the locations hold:
///
/// - characters a request target never carries raw: controls, a space,
///   non-ASCII, a backslash, a malformed `%` escape, an escape that is
///   not strict UTF-8 (overlong forms, lone surrogates);
/// - a decoded segment that is `.` or `..`, that holds a `/`, `\`, NUL or
///   another control character, `:` (drive letters, alternate data
///   streams, URLs), a wildcard of Windows (`*`, `?`, `"`, `<`, `>`, `|`),
///   a `~` followed by a digit (a Windows short name, `PROGRA~1`), or
///   characters that look like dots and slashes (fullwidth and other
///   confusable forms);
/// - a segment that ends with a dot or a space, or starts with a space
///   (Windows drops trailing ones, so `a.html.` would read `a.html`);
/// - a device name of Windows (`CON`, `NUL`, `COM1`, `LPT1`, ... with any
///   extension);
/// - `WEB-INF` and `META-INF` in any case, as Spring refuses them;
/// - a hidden segment (starting with `.`), except `.well-known` as the
///   first segment;
/// - a segment that still holds a `%` escape once decoded (`%252e` is
///   `%2e`): Spring decodes such a path twice and checks the result; here
///   it is refused whatever it would give.
///
/// - a `;` (matrix parameters, `..;x`) and an empty segment (`a//b`)
///   other than a leading or a trailing one: Tomcat would cut the one and
///   merge the other, and a proxy in front may read them another way, so
///   such a path is refused rather than guessed at (Spring Security's
///   firewall refuses both with a 400).
List<String>? staticResourceSegments(String pathWithinMapping) {
  final raw = pathWithinMapping;
  for (final unit in raw.codeUnits) {
    // Only visible ASCII arrives in a request target; a backslash is
    // refused rather than read as a separator, and so is a `;`.
    if (unit <= 0x20 || unit >= 0x7F || unit == 0x5C || unit == 0x3B) {
      return null;
    }
  }
  final directory = raw.length > 1 && raw.endsWith('/');
  final segments = <String>[];
  final parts = raw.split('/');
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) {
      // A leading `/`, a trailing one (a directory), or nothing at all.
      if (i == 0 || i == parts.length - 1) {
        continue;
      }
      return null;
    }
    final decoded = _decode(part);
    if (decoded == null || !_isAllowedSegment(decoded, segments.isEmpty)) {
      return null;
    }
    // Double encoding: a segment that still holds an escape once decoded
    // (`%252e` is `%2e`) is refused, whatever a second decoding would
    // give, so no layer that decodes again can find a `..` or a `/`.
    if (_escape.hasMatch(decoded)) {
      return null;
    }
    segments.add(decoded);
  }
  if (directory) {
    segments.add('');
  }
  return segments;
}

/// Whether [segment], a decoded segment of a path relative to a location,
/// may be served; [first] says it is the first segment (where
/// `.well-known` is allowed). The same checks as [staticResourceSegments]
/// for one segment; the location checks the segments of a resolved
/// symbolic link with it too.
bool isAllowedStaticSegment(String segment, {required bool first}) =>
    _isAllowedSegment(segment, first);

/// The file name `apple-app-site-association` of the deep links of iOS,
/// which has no extension but is JSON.
const appleAppSiteAssociation = 'apple-app-site-association';

String? _decode(String part) {
  if (!part.contains('%')) {
    return part;
  }
  try {
    // Strict: a malformed escape is an ArgumentError, bytes that are not
    // UTF-8 (overlong forms included) a FormatException.
    return Uri.decodeComponent(part);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

bool _isAllowedSegment(String segment, bool first) {
  if (segment.isEmpty || segment == '.' || segment == '..') {
    return false;
  }
  for (final rune in segment.runes) {
    if (rune < 0x20 || rune == 0x7F || (rune >= 0x80 && rune < 0xA0)) {
      return false;
    }
    if (_forbidden.contains(rune) || _confusable.contains(rune)) {
      return false;
    }
    // Unpaired surrogates (decoded from CESU-like escapes) and
    // noncharacters name nothing a static file should have.
    if ((rune >= 0xD800 && rune <= 0xDFFF) || rune == 0xFFFE) {
      return false;
    }
  }
  if (segment.endsWith('.') ||
      segment.endsWith(' ') ||
      segment.startsWith(' ')) {
    return false;
  }
  if (_shortName.hasMatch(segment)) {
    return false;
  }
  final upper = segment.toUpperCase();
  if (upper == 'WEB-INF' || upper == 'META-INF') {
    return false;
  }
  final base = upper.split('.').first.trimRight();
  if (_windowsDevices.contains(base) || _numberedDevice.hasMatch(base)) {
    return false;
  }
  if (segment.startsWith('.')) {
    return first && segment == '.well-known';
  }
  return true;
}

// A percent escape.
final _escape = RegExp('%[0-9A-Fa-f]{2}');

// A Windows 8.3 short name (`PROGRA~1`).
final _shortName = RegExp('~[0-9]');

// COM1 ... LPT9, with the superscript digits Windows also reads.
final _numberedDevice = RegExp(r'^(COM|LPT)[0-9¹²³]$');

// Separators, NUL, the drive and stream separator and Windows' wildcards.
const _forbidden = {
  0x2F, // /
  0x5C, // \
  0x00,
  0x3A, // :
  0x2A, // *
  0x3F, // ?
  0x22, // "
  0x3C, // <
  0x3E, // >
  0x7C, // |
};

// Characters that some file systems, libraries or proxies fold into a dot
// or a separator (Unicode compatibility forms and look-alikes).
const _confusable = {
  0x2024, // one dot leader
  0x2025, // two dot leader
  0x2026, // horizontal ellipsis
  0xFE52, // small full stop
  0xFF0E, // fullwidth full stop
  0x3002, // ideographic full stop
  0xFF61, // halfwidth ideographic full stop
  0x2044, // fraction slash
  0x2215, // division slash
  0x2216, // set minus
  0x29F5, // reverse solidus operator
  0x29F8, // big solidus
  0x29F9, // big reverse solidus
  0xFE68, // small reverse solidus
  0xFF0F, // fullwidth solidus
  0xFF3C, // fullwidth reverse solidus
  0x2100, // account of (a/c)
  0x2101, // addressed to the subject (a/s)
  0x2105, // care of (c/o)
  0x2106, // cada una (c/u)
  0xFF1A, // fullwidth colon
  0xFE55, // small colon
  0x2236, // ratio
};

const _windowsDevices = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  r'CONIN$',
  r'CONOUT$',
  r'CLOCK$',
};
