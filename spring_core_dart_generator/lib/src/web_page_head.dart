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
  /// A Telegram Mini App is told to keep its vertical swipes for the page
  /// (`web_app_setup_swipe_behavior`, Bot API 7.7) and to open at its full
  /// height (`web_app_expand`), the way telegram-web-app.js sends them:
  /// `TelegramWebviewProxy.postEvent` in the apps, a message to the parent
  /// window in Telegram Web. No script of Telegram's is loaded for it.
  ///
  /// In an app's own browser (Telegram's for a link, Instagram's...) a
  /// swipe down closes the page when the page is at its top, and a Flutter
  /// page always is: the page is made one pixel taller than the screen and
  /// kept one pixel down, at its load and at each touch, so the swipe is
  /// no close. Touch screens only; the pixel is never seen.
  static const swipeBlock =
      '''
  $swipeStart
  <style>@media (pointer: coarse){html{height:calc(100% + 1px);scrollbar-width:none}html::-webkit-scrollbar{display:none}}</style>
  <script>(function(){function post(t,d){var e=JSON.stringify({eventType:t,eventData:d});try{var p=window.TelegramWebviewProxy;if(p&&p.postEvent){p.postEvent(t,JSON.stringify(d));}else if(window.external&&'notify' in window.external){window.external.notify(e);}else if(window.parent!==window){window.parent.postMessage(e,'*');}}catch(x){}}post('web_app_expand',{});post('web_app_setup_swipe_behavior',{allow_vertical_swipe:false});if(!(window.matchMedia&&matchMedia('(pointer: coarse)').matches))return;function keep(){if(window.scrollY<1)window.scrollTo(0,1);}addEventListener('load',keep);addEventListener('scroll',keep,{passive:true});addEventListener('resize',keep);addEventListener('touchstart',keep,{passive:true,capture:true});setTimeout(keep,0);})();</script>
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
