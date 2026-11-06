import 'dart:convert';

/// The app's own `web/index.html` head and `web/manifest.json` from its
/// configuration, so they repeat nothing by hand: the title and
/// description of `spring.flutter.app.*`, the colors of the active theme.
///
/// Flutter's template writes its own (`A new Flutter project.`, the project
/// name, `#0175C2`); each value set in the configuration replaces the
/// template's, a value not set leaves the file's as it is. A page that
/// carries the head of `spring.flutter.web.seo.*` (between
/// [seoHeadStart] and its end) keeps its own title and description: the
/// SEO build wrote them for the page.
abstract final class WebPageHead {
  /// Where the SEO build's head block of a page starts.
  static const seoHeadStart = '<!-- spring:seo:head:start -->';

  /// [html] with [title] in `<title>` and `apple-mobile-web-app-title`,
  /// [description] in `<meta name="description">` and [themeColor] in
  /// `<meta name="theme-color">` (added when missing); a `null` value
  /// changes nothing.
  static String html(
    String html, {
    String? title,
    String? description,
    String? themeColor,
  }) {
    var result = html;
    // The SEO build owns the page's title and description.
    final seo = html.contains(seoHeadStart);
    if (title != null) {
      if (!seo) {
        result = result.replaceFirstMapped(
          RegExp(r'<title>[\s\S]*?</title>'),
          (_) => '<title>${_text(title)}</title>',
        );
      }
      // The app's name on a home screen, whatever the page.
      result = _meta(result, 'apple-mobile-web-app-title', title, add: false);
    }
    if (description != null && !seo) {
      result = _meta(result, 'description', description, add: true);
    }
    if (themeColor != null) {
      result = _meta(result, 'theme-color', themeColor, add: true);
    }
    return result;
  }

  /// [manifest] (the JSON of `web/manifest.json`) with these values; the
  /// keys of the configuration replaced, the rest kept in their order.
  /// `null` when [manifest] is no JSON object.
  static String? manifest(
    String manifest, {
    String? title,
    String? description,
    String? themeColor,
    String? backgroundColor,
  }) {
    final Object? json;
    try {
      json = jsonDecode(manifest);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) {
      return null;
    }
    final updated = {
      ...json,
      'name': ?title,
      'short_name': ?title,
      'description': ?description,
      'theme_color': ?themeColor,
      'background_color': ?backgroundColor,
    };
    return '${const JsonEncoder.withIndent('    ').convert(updated)}\n';
  }

  // The content of `<meta name="[name]">`, or a new one before `</head>`
  // when [add].
  static String _meta(
    String html,
    String name,
    String value, {
    required bool add,
  }) {
    final tag = RegExp(
      '<meta\\s+name="${RegExp.escape(name)}"\\s+content="[^"]*"\\s*/?>',
    );
    final written = '<meta name="$name" content="${_attribute(value)}">';
    if (tag.hasMatch(html)) {
      return html.replaceFirst(tag, written);
    }
    if (!add) {
      return html;
    }
    return html.replaceFirst('</head>', '  $written\n</head>');
  }

  static String _text(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);

  static String _attribute(String value) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
}
