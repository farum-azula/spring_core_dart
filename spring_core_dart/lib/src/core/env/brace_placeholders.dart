/// `{{key}}` placeholders in a text that is not configuration: Markdown
/// pages, templates of an app's own. Each is replaced by [resolve]'s value
/// of its key; one whose key has no value stays as it is, so a text that
/// shows `{{token}}` of another tool keeps it. `\{{` writes `{{` as text.
///
/// `${...}` is left alone: it is the configuration's own placeholder, and
/// documentation is full of examples of it.
///
/// ```dart
/// BracePlaceholders.resolve(
///   'spring_boot_dart: ^{{site.package-version}}',
///   environment.getProperty,
/// ); // 'spring_boot_dart: ^0.7.2'
/// ```
///
/// Spring has no counterpart; it is Mustache's syntax for one value.
abstract final class BracePlaceholders {
  static final _placeholder = RegExp(
    r'(\\)?\{\{\s*([A-Za-z0-9_$][A-Za-z0-9_.\-\[\]$]*)\s*\}\}',
  );

  /// [text] with each `{{key}}` whose key [resolve] knows replaced by its
  /// value.
  static String resolve(String text, String? Function(String key) resolve) {
    if (!text.contains('{{')) {
      return text;
    }
    return text.replaceAllMapped(_placeholder, (match) {
      if (match[1] != null) {
        return match[0]!.substring(1);
      }
      return resolve(match[2]!) ?? match[0]!;
    });
  }
}
