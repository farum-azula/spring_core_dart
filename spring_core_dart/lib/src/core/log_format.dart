/// Formats values for log lines: what the framework writes about values
/// from outside (a path, a user name, a header) goes through it.
///
/// A value from a client can hold line breaks and terminal escapes: logged
/// as it is, `ada\nINFO ... root logged in` would add a forged line to the
/// log, and an escape code would change what a terminal shows. [formatValue]
/// replaces them, and cuts long values.
///
/// Spring (Java): `org.springframework.core.log.LogFormatUtils`.
abstract final class LogFormatUtils {
  /// [value] for a log line: a `String` in quotes, `null` as `null`,
  /// anything else by `toString()`; cut to [maxLength] characters
  /// (`-1`: no limit) followed by ` (truncated)...`; with
  /// [replaceNewlinesAndControlCharacters] (the default here), `\n` and
  /// `\r` as `<EOL>` and every other control character (`\p{Cc}`, escape
  /// codes included) as `?`, as Spring.
  ///
  /// Spring (Java): `LogFormatUtils.formatValue(value, maxLength,
  /// replaceNewlinesAndControlCharacters)`.
  static String formatValue(
    Object? value, {
    int maxLength = 100,
    bool replaceNewlinesAndControlCharacters = true,
  }) {
    if (value == null) {
      return '';
    }
    var text = value is String ? '"$value"' : value.toString();
    if (maxLength != -1 && text.length > maxLength) {
      text = '${text.substring(0, maxLength)} (truncated)...';
    }
    if (!replaceNewlinesAndControlCharacters) {
      return text;
    }
    final out = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D) {
        out.write('<EOL>');
      } else if (rune < 0x20 || (rune >= 0x7F && rune < 0xA0)) {
        out.write('?');
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }
}
