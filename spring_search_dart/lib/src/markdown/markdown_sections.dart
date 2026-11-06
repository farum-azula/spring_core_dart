/// One section of a Markdown page: the text under a heading, as plain
/// text, for the index.
final class MarkdownSection {
  /// The section of [heading] (empty for the text before the first one).
  const MarkdownSection({
    required this.heading,
    required this.anchor,
    required this.body,
  });

  /// The heading without its marks; empty for the page's opening text.
  final String heading;

  /// The anchor GitHub gives the heading (`#why-beans`); `null` for the
  /// opening text.
  final String? anchor;

  /// The text, without the Markdown's marks; code stays as written.
  final String body;
}

/// A Markdown page cut into its sections at the headings of level two and
/// below: its [title] (the front matter's `title`, or the first `#`
/// heading) and the [sections] in order.
final class MarkdownSections {
  /// The [sections] of the page [title].
  const MarkdownSections(this.title, this.sections);

  /// Reads [markdown].
  factory MarkdownSections.parse(String markdown) {
    var lines = markdown.replaceAll('\r\n', '\n').split('\n');
    String? title;
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere((l) => l.trim() == '---', 1);
      if (end > 0) {
        for (final line in lines.sublist(1, end)) {
          final match = RegExp(r'^title:\s*(.*)$').firstMatch(line);
          if (match != null) {
            title = _unquoted(match[1]!.trim());
          }
        }
        lines = lines.sublist(end + 1);
      }
    }
    final sections = <MarkdownSection>[];
    final taken = <String>{};
    var heading = '';
    String? anchor;
    var body = <String>[];
    String? fence;
    void close() {
      final text = _plain(body.join('\n'));
      if (text.isNotEmpty || heading.isNotEmpty) {
        sections.add(
          MarkdownSection(heading: heading, anchor: anchor, body: text),
        );
      }
    }

    for (final line in lines) {
      final trimmed = line.trimLeft();
      final marker = RegExp('^(```+|~~~+)').firstMatch(trimmed)?[1];
      if (marker != null) {
        if (fence == null) {
          fence = marker;
        } else if (trimmed.startsWith(fence)) {
          fence = null;
        }
        continue;
      }
      final match = fence == null
          ? RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$').firstMatch(line)
          : null;
      if (match == null) {
        body.add(line);
        continue;
      }
      final text = _inline(match[2]!).trim();
      if (match[1]!.length == 1) {
        title ??= text;
        continue;
      }
      close();
      heading = text;
      anchor = anchorOf(text, taken);
      body = [];
    }
    close();
    return MarkdownSections(title ?? '', sections);
  }

  /// The page's title; empty when it has none.
  final String title;

  /// The sections, the opening text first.
  final List<MarkdownSection> sections;

  /// The anchor GitHub gives a heading of [text], unique in [taken].
  static String anchorOf(String text, [Set<String>? taken]) {
    final base = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
        .replaceAll(RegExp(r'\s'), '-');
    var id = base;
    for (var n = 1; taken != null && taken.contains(id); n++) {
      id = '$base-$n';
    }
    taken?.add(id);
    return id;
  }

  static String _unquoted(String text) =>
      text.length >= 2 &&
          (text.startsWith('"') && text.endsWith('"') ||
              text.startsWith("'") && text.endsWith("'"))
      ? text.substring(1, text.length - 1)
      : text;

  static String _inline(String text) => text
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp('<[^>]+>'), '')
      .replaceAll(RegExp('[`*~]|(?<![A-Za-z0-9])_|_(?![A-Za-z0-9])'), '');

  static String _plain(String text) => _inline(
    text
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*([-*+]|\d+\.)\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\|?\s*:?-{3,}.*$', multiLine: true), '')
        .replaceAll('|', ' ')
        .replaceAll(RegExp(r'\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]'), ''),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}
