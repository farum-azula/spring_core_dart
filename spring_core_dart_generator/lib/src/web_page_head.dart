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

  /// Where the block that keeps the page open on a swipe down starts.
  static const swipeStart = '<!-- spring:page:swipe:start -->';

  /// Where it ends.
  static const swipeEnd = '<!-- spring:page:swipe:end -->';

  /// The block of `spring.flutter.web.page.swipe-to-close: false`.
  ///
  /// In an app's own browser (Telegram's for a link, Instagram's...) a
  /// swipe down closes the page when the page is at its top, and a Flutter
  /// page always is. On a touch screen the page is made a thousand screens
  /// tall and scrolled to its end, with Flutter's view fixed on the screen
  /// (on all four sides, so it fills the screen whatever `100vh` is there),
  /// and the browser's own scrolling of the page is stopped (`touchmove`),
  /// so the page is never at its top: a swipe down is Flutter's.
  static const swipeBlock =
      '''
  $swipeStart
  <style>@media (pointer: coarse){html{scrollbar-width:none}html::-webkit-scrollbar{display:none}body{height:1000vh!important;position:static!important;overscroll-behavior:none}flutter-view{position:fixed!important;inset:0!important;width:auto!important;height:auto!important}}</style>
  <script>(function(){if(!(window.matchMedia&&matchMedia('(pointer: coarse)').matches))return;function end(){window.scrollTo(0,document.body.scrollHeight);}addEventListener('DOMContentLoaded',end);addEventListener('load',end);addEventListener('resize',end);document.addEventListener('touchmove',function(e){e.preventDefault();},{passive:false});})();</script>
  $swipeEnd''';

  /// Where the block that caps the drawing's pixel ratio starts.
  static const pixelRatioStart = '<!-- spring:page:pixel-ratio:start -->';

  /// Where it ends.
  static const pixelRatioEnd = '<!-- spring:page:pixel-ratio:end -->';

  /// [html] with a block that caps the pixel ratio Flutter draws at to
  /// [max] (`spring.flutter.web.page.max-pixel-ratio`), before the engine
  /// starts; without it when [max] is `null`.
  ///
  /// A phone's screen has 3 pixels for each point: Flutter draws every
  /// frame at 9 times the pixels of the page, and a phone's graphics chip
  /// drops frames on a full-screen scroll. At 2 it draws 2.25 times fewer
  /// and the text stays sharp. The browser scales the drawing to the
  /// screen; a screen at or under [max] is left as it is.
  static String pixelRatio(String html, {required double? max}) {
    final block = RegExp(
      r'\n?[ \t]*' +
          RegExp.escape(pixelRatioStart) +
          r'[\s\S]*?' +
          RegExp.escape(pixelRatioEnd),
    );
    final without = html.replaceAll(block, '');
    if (max == null) {
      return without;
    }
    final value = max == max.roundToDouble() ? '${max.round()}' : '$max';
    return without.replaceFirst('</head>', '''
  $pixelRatioStart
  <script>(function(){var m=$value;if(window.devicePixelRatio>m){try{window.devicePixelRatio=m;}catch(e){}}})();</script>
  $pixelRatioEnd
</head>''');
  }

  /// [html] with the [swipeBlock] in its head when [swipeToClose] is
  /// `false`, without it when `true`.
  static String swipe(String html, {required bool swipeToClose}) {
    final block = RegExp(
      r'\n?[ \t]*' +
          RegExp.escape(swipeStart) +
          r'[\s\S]*?' +
          RegExp.escape(swipeEnd),
    );
    final without = html.replaceAll(block, '');
    if (swipeToClose) {
      return without;
    }
    return without.replaceFirst('</head>', '$swipeBlock\n</head>');
  }

  /// [html] with [title] in `<title>` and `apple-mobile-web-app-title`,
  /// [description] in `<meta name="description">` and [themeColor] in
  /// `<meta name="theme-color">` (added when missing); a `null` value
  /// changes nothing. A page without `<meta name="viewport">` gets
  /// Flutter's [viewport]. [backgroundColor] (the theme's surface) is the
  /// page's own background, between [backgroundStart] and its end: what
  /// shows where Flutter does not draw (an app's browser resizing, a gap
  /// at an edge) is the theme's, not white.
  static String html(
    String html, {
    String? title,
    String? description,
    String? themeColor,
    String? backgroundColor,
  }) {
    var result = _background(_viewport(html), backgroundColor);
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

  /// Where the block of the page's background color starts.
  static const backgroundStart = '<!-- spring:page:background:start -->';

  /// Where it ends.
  static const backgroundEnd = '<!-- spring:page:background:end -->';

  // [html] with the block of [color]; without it when [color] is `null`.
  static String _background(String html, String? color) {
    final block = RegExp(
      r'\n?[ \t]*' +
          RegExp.escape(backgroundStart) +
          r'[\s\S]*?' +
          RegExp.escape(backgroundEnd),
    );
    if (color == null) {
      return html.replaceAll(block, '');
    }
    final written =
        '\n  $backgroundStart\n'
        '  <style>html,body{background-color:${_attribute(color)}}</style>\n'
        '  $backgroundEnd';
    // Kept where it is, so a page written again does not change.
    if (block.hasMatch(html)) {
      return html.replaceFirst(block, written);
    }
    return html.replaceFirst('</head>', '$written\n</head>');
  }

  /// The viewport Flutter sets when it starts. Flutter's template has
  /// none, so until then a phone lays the page out about 980 points wide
  /// and shrinks it: the page loader shows at a third of its size, then
  /// grows when Flutter's tag comes. With the same tag from the start
  /// nothing moves.
  static const viewport =
      'width=device-width, initial-scale=1.0, maximum-scale=1.0, '
      'user-scalable=no';

  // [html] with the [viewport] tag when it has none; a page's own is kept.
  static String _viewport(String html) {
    if (RegExp(r'<meta\s+name="viewport"').hasMatch(html)) {
      return html;
    }
    return _meta(html, 'viewport', viewport, add: true);
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
