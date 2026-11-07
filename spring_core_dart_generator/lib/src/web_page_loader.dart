// CSS is written as adjacent strings without spaces between rules.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:math' as math;

import 'package:spring_core_dart/core.dart' show RemoteAddresses;
import 'package:spring_core_dart_generator/src/theme_palette.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:spring_core_dart_generator/src/web_page_head.dart';

/// The page loader: what the browser shows from the first byte of the page
/// until the Flutter splash paints, made from the `splash` of the active
/// theme and written into the app's `web/index.html` between
/// [startMarker] and [endMarker].
///
/// It is plain HTML and CSS, and one small static script. Built-in loader
/// kinds (`spinner`, `dots`, `pulse`, `bar`, `skeleton`) have their CSS
/// here; a kind of the app's own gives a `web:` HTML file, which is put in
/// the page as it is, with the keys of the loader as CSS variables
/// (`door.color` is `--door-color`; a list of colors also gives its first
/// as `--door-colors-first`, to close a circular gradient).
///
/// The script follows Flutter's loader (`_flutter.loader.load`) for the
/// progress (`--spring-progress`, `data-stage`; a progress phase with a
/// `min-duration` shows no more than its eased clock, from the
/// `data-fill-at` and `data-fill-min` attributes), records the start's
/// first stages (`page` when the page runs, `engine` when Flutter's engine
/// starts) in `window.springLoader.stages`, `data-splash-stage` and a
/// `spring-splash-stage` event, and removes the loader
/// when the Flutter side calls `window.springLoaderHandOff()`; a timeout
/// removes it anyway. Because the script never changes, a
/// Content-Security-Policy can allow it by hash ([scriptHash]).
///
/// Spring has no counterpart.
abstract final class WebPageLoader {
  /// Starts the generated block of the page.
  static const startMarker = '<!-- spring:loader:start -->';

  /// Ends the generated block of the page.
  static const endMarker = '<!-- spring:loader:end -->';

  /// The function the Flutter side calls when its splash has painted: it
  /// removes the page loader.
  static const handOffHook = 'springLoaderHandOff';

  /// The built-in loader kinds, canonical.
  static const builtInKinds = {
    'spinner', 'dots', 'pulse', 'bar', 'skeleton', //
  };

  /// The script of the block, the same for every app.
  static const script =
      '''
(function () {
  var root = document.getElementById('spring-loader');
  if (!root) return;
  var done = false, progress = 0, shown = 0, floor = 0, cap = 0.4, timer;
  function now() {
    return window.performance && performance.now ? performance.now() : Date.now();
  }
  var started = now(), last = 0;
  var fillMin = +root.getAttribute('data-fill-min') || 0;
  var fillAt = +root.getAttribute('data-fill-at') || 0;
  var still = !!(window.matchMedia &&
    matchMedia('(prefers-reduced-motion: reduce)').matches);
  function ease(t) {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(2 - 2 * t, 3) / 2;
  }
  function target() {
    if (!fillMin || still) return progress;
    var t = (now() - started - fillAt) / fillMin;
    return Math.min(progress, t <= 0 ? 0 : t >= 1 ? 1 : ease(t));
  }
  var stages = {
    load: [0.08, 0.45], app: [0.5, 0.6], engine: [0.6, 0.88],
    run: [0.9, 0.95], done: [1, 1]
  };
  var reached = [], splashStages = { load: 'page', engine: 'engine' };
  function enter(stage) {
    for (var i = 0; i < reached.length; i++) if (reached[i].stage === stage) return;
    var entry = { stage: stage, at: now() };
    reached.push(entry);
    root.setAttribute('data-splash-stage', stage);
    try {
      window.dispatchEvent(new CustomEvent('spring-splash-stage', { detail: entry }));
    } catch (e) {}
  }
  function show(stage) {
    var s = stages[stage];
    if (done || !s) return;
    if (splashStages[stage]) enter(splashStages[stage]);
    floor = s[0]; cap = s[1];
    if (progress < floor) progress = floor;
    root.setAttribute('data-stage', stage);
  }
  function paint(time) {
    if (done) return;
    var dt = last ? time - last : 16, to = target(), step = dt / 300;
    last = time;
    shown = to > shown ? Math.min(to, shown + step) : Math.max(to, shown - step);
    root.style.setProperty('--spring-progress', shown.toFixed(3));
    requestAnimationFrame(paint);
  }
  function remove() {
    if (done) return;
    done = true;
    clearTimeout(timer);
    clearInterval(creep);
    if (root.parentNode) root.parentNode.removeChild(root);
    var style = document.getElementById('spring-loader-style');
    if (style && style.parentNode) style.parentNode.removeChild(style);
  }
  var creep = setInterval(function () {
    if (progress < cap) progress += (cap - progress) * 0.04;
  }, 150);
  window.springLoader = {
    get progress() { return shown; },
    get stage() { return root.getAttribute('data-stage'); },
    get elapsed() { return now() - started; },
    get stages() { return reached.slice(); },
    handOff: remove
  };
  window.$handOffHook = remove;
  timer = setTimeout(remove, 60000);
  window.addEventListener('flutter-first-frame', function () {
    show('done');
    clearTimeout(timer);
    timer = setTimeout(remove, 3000);
  });
  function wrap(loader) {
    if (!loader || loader.__springLoader || typeof loader.load !== 'function') return;
    loader.__springLoader = true;
    var load = loader.load;
    loader.load = function (options) {
      options = options || {};
      var next = options.onEntrypointLoaded;
      var config = options.config || {};
      show('load');
      options.onEntrypointLoaded = function (initializer) {
        show('app');
        var initialize = initializer.initializeEngine;
        try {
          initializer.initializeEngine = function () {
            show('engine');
            return initialize.apply(initializer, arguments).then(function (runner) {
              show('run');
              return runner;
            });
          };
        } catch (e) {}
        if (next) return next(initializer);
        return initializer.initializeEngine(config).then(function (runner) {
          return runner.runApp();
        });
      };
      return load.call(loader, options);
    };
  }
  var flutter = window._flutter = window._flutter || {};
  if (flutter.loader) {
    wrap(flutter.loader);
  } else {
    var held;
    Object.defineProperty(flutter, 'loader', {
      configurable: true,
      enumerable: true,
      get: function () { return held; },
      set: function (value) { held = value; wrap(value); }
    });
  }
  show('load');
  requestAnimationFrame(paint);
})();''';

  /// The hash of [script] for a Content-Security-Policy `script-src`
  /// (`'sha256-...'`).
  static String get scriptHash => WebPageHead.hashOf(script);

  static const _style = '''
#spring-loader{position:fixed;top:0;right:0;bottom:0;left:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--spring-progress:0}
#spring-loader .sl-body{display:flex;flex-direction:column;align-items:center;gap:20px;padding:24px;text-align:center}
#spring-loader .sl-logo{display:block;object-fit:contain}
#spring-loader .sl-title{font-size:28px;font-weight:600;letter-spacing:.04em}
#spring-loader .sl-kind{display:flex;align-items:center;justify-content:center}
@keyframes sl-spin{to{transform:rotate(360deg)}}
@keyframes sl-bounce{0%,80%,100%{transform:scale(.55);opacity:.45}40%{transform:scale(1);opacity:1}}
@keyframes sl-pulse{0%{transform:scale(.6);opacity:.9}100%{transform:scale(1.25);opacity:0}}
@keyframes sl-shimmer{from{background-position:200% 0}to{background-position:-200% 0}}
@media (prefers-reduced-motion:reduce){#spring-loader *{animation:none!important;transition:none!important}}''';

  /// Writes [block] into [html] between the markers: replaces the old
  /// block, or puts it right after `<body>` when the page has none. A
  /// `null` [block] removes the markers and what is between them. Nothing
  /// else of [html] changes. Returns `null` and does not change anything
  /// when the markers are not a proper pair (a message says why in
  /// [problem]).
  static String? apply(
    String html,
    String? block, {
    void Function(String message)? problem,
  }) {
    final start = html.indexOf(startMarker);
    final end = html.indexOf(endMarker);
    final hasStart = start != -1;
    if (hasStart != (end != -1) ||
        (hasStart && end < start) ||
        (hasStart && html.indexOf(startMarker, start + 1) != -1)) {
      problem?.call(
        'web/index.html has $startMarker and $endMarker that are not one '
        'pair, in this order: fix or remove them.',
      );
      return null;
    }
    if (hasStart) {
      final stop = end + endMarker.length;
      if (block == null) {
        // Also the line break the block started with, if any.
        var from = start;
        while (from > 0 && (html[from - 1] == ' ' || html[from - 1] == '\t')) {
          from--;
        }
        var to = stop;
        if (to < html.length && html[to] == '\n') {
          to++;
        }
        return html.replaceRange(from, to, '');
      }
      return html.replaceRange(start, stop, block);
    }
    if (block == null) {
      return html;
    }
    final body = RegExp('<body[^>]*>', caseSensitive: false).firstMatch(html);
    if (body != null) {
      final head = html.substring(0, body.end);
      return '$head\n$block${html.substring(body.end)}';
    }
    final close = html.toLowerCase().lastIndexOf('</html>');
    final at = close == -1 ? html.length : close;
    return '${html.substring(0, at)}$block\n${html.substring(at)}';
  }

  /// The colors of the app's page and manifest: the active theme's
  /// `primary` (the browser's `theme-color`) and `surface` (the manifest's
  /// background), as `#rrggbb`.
  ///
  /// With `system` (a light and a dark theme), `darkPrimary` and
  /// `darkSurface` are the dark theme's, for a `prefers-color-scheme: dark`
  /// rule; `null` with one theme.
  static ({
    String primary,
    String surface,
    String? darkPrimary,
    String? darkSurface,
  })
  pageColors(ThemeSet set, KeysDiagnostics diagnostics) {
    final (:light, :dark) = _active(set);
    ({String primary, String surface}) of(String name) {
      final scope = set.scope(name);
      final look = _Look(
        scope,
        ThemeValueResolver(scope, dark: _isDark(scope, name)),
        diagnostics,
      );
      String opaque(String role, int fallback) => cssColor(
        0xFF000000 |
            ((look.resolver.color(look._roleNode(role)) ?? fallback) &
                0xFFFFFF),
      );
      return (
        primary: opaque('primary', 0xFF6750A4),
        surface: opaque('surface', 0xFFFFFFFF),
      );
    }

    final lightColors = of(light);
    final darkColors = dark == null ? null : of(dark);
    return (
      primary: lightColors.primary,
      surface: lightColors.surface,
      darkPrimary: darkColors?.primary,
      darkSurface: darkColors?.surface,
    );
  }

  /// Whether the properties of [set] give a splash to the active theme.
  static bool hasSplash(ThemeSet set) {
    final (:light, :dark) = _active(set);
    return _splashOf(set.scope(light)) != null ||
        (dark != null && _splashOf(set.scope(dark)) != null);
  }

  /// The `web:` files of the loader the splash of the active theme shows,
  /// to be read before [generate].
  static Set<String> webFiles(ThemeSet set) => {
    for (final file in webSources(set)) file.path,
  };

  /// The `web:` files of the active themes' splash loaders with their
  /// `web-sha256` pins: a path below `lib/resources/` (or the app's
  /// directory), or an address to download at build time (`https://...`,
  /// `github:owner/repo/path@ref`).
  static Set<({String path, String? sha256})> webSources(ThemeSet set) {
    final (:light, :dark) = _active(set);
    final result = <({String path, String? sha256})>{};
    for (final name in [light, ?dark]) {
      final scope = set.scope(name);
      final splash = _splashOf(scope);
      final loader = splash?.children['loader']?.entry?.value.trim();
      if (loader == null) {
        continue;
      }
      String? value(String key) => scope
          .node(['loaders', canonicalName(loader), key])
          ?.entry
          ?.value
          .trim();
      final web = value('web');
      if (web != null && web.isNotEmpty && _safePath(web)) {
        final pin = value('websha256')?.toLowerCase();
        result.add((
          path: web,
          sha256: pin == null || pin.isEmpty ? null : pin,
        ));
      }
    }
    return result;
  }

  /// Whether [path] is an address to download: one the built-in address
  /// resolvers read (`https://`, `http://`, `github:`). The build has no
  /// application, so an application's own resolvers are not asked here.
  static bool isRemote(String path) => const RemoteAddresses().isAddress(path);

  static bool _safePath(String path) =>
      isRemote(path) ||
      !(path.startsWith('/') ||
          path.contains(RegExp(r'(^|[\\/])\.\.([\\/]|$)')) ||
          path.contains(RegExp(r'^[A-Za-z]:|\\')));

  /// The themes the page loader reads: the one the app shows, or for
  /// `system` the light one and the dark one.
  static ({String light, String? dark}) _active(ThemeSet set) {
    final base = set.scope('light');
    String name(String key, String fallback) {
      final value = base.node([key])?.entry?.value.trim();
      if (value == null || value.isEmpty) {
        return fallback;
      }
      final known = {for (final n in set.names) canonicalName(n): n};
      return known[canonicalName(value)] ?? fallback;
    }

    final active = base.node(const ['active'])?.entry?.value.trim();
    if (active == null || canonicalName(active) == 'system') {
      return (
        light: name('systemlight', 'light'),
        dark: name('systemdark', 'dark'),
      );
    }
    final known = {for (final n in set.names) canonicalName(n): n};
    return (light: known[canonicalName(active)] ?? 'light', dark: null);
  }

  static ThemeNode? _splashOf(ThemeScope scope) {
    final node = scope.node(const ['splash']);
    return node != null && node.children.isNotEmpty ? node : null;
  }

  /// The block for the splash of the active theme of [set], with its
  /// markers; `null` when the theme has no splash.
  /// [readFile] gives the text of a file below the app's directory (the
  /// `web:` of a loader), or `null`. Problems go to [diagnostics] as
  /// warnings: a page loader never fails a build.
  static String? generate(
    ThemeSet set,
    KeysDiagnostics diagnostics, {
    required String? Function(String path) readFile,
  }) {
    final (:light, :dark) = _active(set);
    final scope = set.scope(light);
    final splash = _splashOf(scope);
    if (splash == null) {
      return null;
    }
    final look = _Look(
      scope,
      ThemeValueResolver(scope, dark: _isDark(scope, light)),
      diagnostics,
    );
    final kindHtml = _kind(look, splash, readFile);
    final vars = look.variables(splash);
    final out = StringBuffer()
      ..writeln(startMarker)
      ..writeln(
        '<!-- Written by spring_core_dart_generator from the splash of the '
        'active theme; rewritten on every build. -->',
      )
      ..writeln('<style id="spring-loader-style">')
      ..writeln(_style)
      ..writeln('#spring-loader{${vars.css}}')
      ..writeln(look.kindCss);
    if (dark != null && _splashOf(set.scope(dark)) != null) {
      final darkScope = set.scope(dark);
      final darkLook = _Look(
        darkScope,
        ThemeValueResolver(darkScope, dark: _isDark(darkScope, dark)),
        diagnostics,
      );
      final darkSplash = _splashOf(darkScope)!;
      darkLook.loader = look.loaderKey == null
          ? null
          : darkScope.node(['loaders', look.loaderKey!]);
      final darkVars = darkLook.variables(darkSplash);
      if (darkVars.css != vars.css) {
        out.writeln(
          '@media (prefers-color-scheme:dark){'
          '#spring-loader{${darkVars.css}}}',
        );
      }
    }
    out
      ..writeln('</style>')
      ..write(
        '<div id="spring-loader" role="status" aria-busy="true" '
        'aria-label="Loading" data-kind="${_attribute(look.kind)}" '
        '${_fillAttributes(look)}data-stage="start"><div class="sl-body">',
      );
    if (vars.logo case final logo?) {
      out.write(
        '<img class="sl-logo" src="${_attribute(logo)}" alt="" '
        'decoding="async">',
      );
    }
    if (look.title case final title?) {
      out.write('<div class="sl-title">${_text(title)}</div>');
    }
    out
      ..write('<div class="sl-kind">$kindHtml</div>')
      ..writeln('</div></div>')
      // Nothing between the tags but the script: a policy allows it by
      // the hash of exactly that text ([scriptHash]).
      ..writeln('<script>$script</script>')
      ..write(endMarker);
    return out.toString();
  }

  // `data-fill-at` and `data-fill-min` (milliseconds) for a loader whose
  // progress phase has a `min-duration`: when that phase starts (after the
  // animated phases before it) and its minimum, so the script shows no
  // more than the clock allows, as the Flutter splash does. Empty when the
  // loader has no such phase, or a looping phase comes before it.
  static String _fillAttributes(_Look look) {
    final phases = look.loader?.children['phases'];
    if (phases == null) {
      return '';
    }
    var at = 0.0;
    for (final phase in phases.children.values) {
      if (phase.children.containsKey('progress')) {
        final min = look.resolver.milliseconds(phase.children['minduration']);
        if (min == null || min <= 0) {
          return '';
        }
        return 'data-fill-at="${cssNumber(at)}" '
            'data-fill-min="${cssNumber(min)}" ';
      }
      final repeat = look.resolver.text(phase.children['repeat']);
      if (repeat != null && canonicalName(repeat) != 'none') {
        return '';
      }
      at += look.resolver.milliseconds(phase.children['duration']) ?? 0;
    }
    return '';
  }

  static bool _isDark(ThemeScope scope, String name) {
    final brightness = scope.node(const ['brightness'])?.entry?.value.trim();
    if (brightness != null) {
      return canonicalName(brightness) == 'dark';
    }
    return canonicalName(name) == 'dark';
  }

  // The HTML of the loader of the splash, and the CSS of its kind (in
  // [_Look.kindCss]).
  static String _kind(
    _Look look,
    ThemeNode splash,
    String? Function(String path) readFile,
  ) {
    final loaderName = look.resolver.text(splash.children['loader']);
    final loaders = look.scope.node(const ['loaders']);
    final node = loaderName == null || loaders == null
        ? null
        : loaders.children[canonicalName(loaderName)];
    if (loaderName != null && node == null) {
      _warn(
        look.diagnostics,
        'splash.loader names "$loaderName", which is no loader: the page '
        'loader shows the logo and title only.',
      );
    }
    if (node == null) {
      look.kind = 'none';
      return '';
    }
    final kind = canonicalName(look.resolver.text(node.children['kind']) ?? '');
    look
      ..loader = node
      ..loaderKey = canonicalName(loaderName!)
      ..kind = kind;
    if (builtInKinds.contains(kind)) {
      look.kindCss = _builtInCss(look, kind, node);
      return _builtInHtml(look, kind, node);
    }
    final path = look.resolver.text(node.children['web']);
    if (path == null) {
      _warn(
        look.diagnostics,
        'loaders.${node.spelling} has the kind "$kind" of the app\'s own and '
        'no `web:` file: the page loader shows a progress bar instead.',
      );
      look.kindCss = _builtInCss(look, 'bar', node);
      look.kind = 'bar';
      return _builtInHtml(look, 'bar', node);
    }
    if (!_safePath(path)) {
      _warn(
        look.diagnostics,
        'loaders.${node.spelling}.web "$path" must be a path below the '
        "app's directory (no .. and not absolute) or an https:// or "
        'github: address.',
      );
      return '';
    }
    final html = readFile(path);
    if (html == null) {
      _warn(
        look.diagnostics,
        isRemote(path)
            ? 'loaders.${node.spelling}.web: "$path" could not be '
                  'downloaded and has no copy from an earlier build.'
            : 'loaders.${node.spelling}.web: the file "$path" does not '
                  "exist (a path below lib/resources/, the app's own or a "
                  "dependency's).",
      );
      return '';
    }
    return html.trim();
  }

  static String _builtInHtml(_Look look, String kind, ThemeNode node) {
    switch (kind) {
      case 'spinner':
        return '<div class="sl-spinner"></div>';
      case 'dots':
        final count = look.count(node);
        return '<div class="sl-dots">${'<span></span>' * count}</div>';
      case 'pulse':
        return '<div class="sl-pulse"><span></span></div>';
      case 'bar':
        return '<div class="sl-bar"><span></span></div>';
      default:
        return '<div class="sl-skeleton"><span></span><span></span>'
            '<span></span></div>';
    }
  }

  static String _builtInCss(_Look look, String kind, ThemeNode node) {
    final primary = look.primary;
    final duration = 'var(--animation-duration,${_defaultMs[kind] ?? 900}ms)';
    final curve = 'var(--animation-curve,${_defaultCurve[kind] ?? 'ease'})';
    final color = 'var(--color,$primary)';
    final size = 'calc(var(--size,${_defaultSize[kind] ?? 40}) * 1px)';
    switch (kind) {
      case 'spinner':
        return '#spring-loader .sl-spinner{box-sizing:border-box;width:$size;'
            'height:$size;border-radius:50%;border:calc($size / 8) solid '
            'var(--track,transparent);border-top-color:$color;'
            'animation:sl-spin $duration linear infinite}';
      case 'dots':
        final count = look.count(node);
        final rules = StringBuffer(
          '#spring-loader .sl-dots{display:flex;gap:calc($size * .6)}'
          '#spring-loader .sl-dots span{display:block;width:$size;'
          'height:$size;border-radius:50%;background:$color;'
          'animation:sl-bounce $duration $curve infinite both}',
        );
        for (var i = 1; i < count; i++) {
          rules.write(
            '#spring-loader .sl-dots span:nth-child(${i + 1})'
            '{animation-delay:calc($duration * ${i / count})}',
          );
        }
        return rules.toString();
      case 'pulse':
        return '#spring-loader .sl-pulse{position:relative;width:$size;'
            'height:$size}#spring-loader .sl-pulse span{position:absolute;'
            'top:0;right:0;bottom:0;left:0;border-radius:50%;background:$color;'
            'animation:sl-pulse $duration $curve infinite}';
      case 'bar':
        return '#spring-loader .sl-bar{width:calc(var(--width,220) * 1px);'
            'max-width:60vw;'
            'height:calc(var(--height,3) * 1px);'
            'border-radius:calc(var(--radius,999) * 1px);'
            'overflow:hidden;background:var(--track,${look.track})}'
            '#spring-loader .sl-bar span{display:block;height:100%;'
            'background:$color;transform-origin:0 50%;'
            'transform:scaleX(var(--spring-progress));'
            'transition:transform .3s ease-out}';
      default:
        return '#spring-loader .sl-skeleton{display:flex;flex-direction:column;'
            'gap:10px;width:min(260px,70vw)}'
            '#spring-loader .sl-skeleton span{display:block;height:14px;'
            'border-radius:calc(var(--radius,6) * 1px);'
            'background:linear-gradient(calc(var(--shimmer-angle,20) * 1deg),'
            'var(--base,${look.base}) 25%,'
            'var(--highlight,${look.highlight}) 50%,'
            'var(--base,${look.base}) 75%);background-size:400% 100%;'
            'animation:sl-shimmer var(--shimmer-duration,1200ms) linear '
            'infinite}#spring-loader .sl-skeleton span:nth-child(2){width:80%}'
            '#spring-loader .sl-skeleton span:nth-child(3){width:55%}';
    }
  }

  static const _defaultMs = {
    'spinner': 900,
    'dots': 900,
    'pulse': 1200,
    'bar': 900,
  };
  static const _defaultCurve = {'dots': 'ease-in-out', 'pulse': 'ease-out'};
  static const _defaultSize = {'spinner': 40, 'dots': 10, 'pulse': 40};
}

// The values of one theme for the page.
final class _Look {
  _Look(this.scope, this.resolver, this.diagnostics);

  final ThemeScope scope;
  final ThemeValueResolver resolver;
  final KeysDiagnostics diagnostics;

  ThemeNode? loader;
  String? loaderKey;
  String kind = 'none';
  String kindCss = '';

  String? get title => resolver.text(
    scope.node(const ['splash', 'title']),
  );

  String get primary => cssColor(
    resolver.color(_roleNode('primary')) ?? 0xFF6750A4,
  );

  String get track => _rgba(primary, .2);
  String get base => cssColor(
    resolver.color(_roleNode('surfacecontainerhigh')) ?? 0xFFE0E0E0,
  );
  String get highlight => cssColor(
    resolver.color(_roleNode('surfacecontainerhighest')) ?? 0xFFF0F0F0,
  );

  // A node-less role is read through a throw-away reference.
  ThemeNode _roleNode(String role) {
    final node = ThemeNode(role)
      ..depth = 1
      ..entry = ThemeEntry('x', const ['x'], '\$colors.$role', 'splash');
    return scope.node(['colors', role]) ?? node;
  }

  static String _rgba(String hex, double alpha) {
    final value = int.parse(hex.substring(1, 7), radix: 16);
    return cssColor((((alpha * 255).round()) << 24) | value);
  }

  int count(ThemeNode node) {
    final value = resolver.number(node.children['count']);
    return (value ?? 3).round().clamp(1, 12);
  }

  // The CSS declarations of the loader's variables and the page, with the
  // logo's path.
  ({String css, String? logo}) variables(ThemeNode splash) {
    final out = <String>[];
    final surface = resolver.color(_roleNode('surface')) ?? 0xFFFFFFFF;
    final background = splash.children['background'];
    var backgroundCss = cssColor(surface);
    var luminance = _luminance(surface);
    if (background != null) {
      final plain = resolver.color(background.children['color']);
      final gradient = _gradient(background.children['gradient']);
      if (gradient != null) {
        backgroundCss = gradient.css;
        luminance = gradient.luminance;
      } else if (plain != null) {
        backgroundCss = cssColor(plain);
        luminance = _luminance(plain);
      }
    }
    out
      ..add('background:$backgroundCss')
      ..add('color:${luminance > .5 ? '#1a1a1a' : '#f5f5f5'}');
    String? logo;
    if (splash.children['logo'] case final node?) {
      final source = resolver.text(node.children['source']);
      if (source != null) {
        logo = _logoUrl(source);
        if (logo == null) {
          _warn(
            diagnostics,
            'splash.logo.source "$source" is not an asset path, an http(s) '
            'URL or a data:image URL: the page loader has no logo.',
          );
        }
      }
      final size = resolver.number(node.children['size']);
      if (logo != null) {
        final px = cssNumber(size ?? 96);
        out.add('--spring-logo-size:${px}px');
      }
    }
    if (logo != null) {
      kindCss +=
          '#spring-loader .sl-logo{width:var(--spring-logo-size);'
          'height:var(--spring-logo-size)}';
    }
    if (loader case final node?) {
      _variables(node, const [], out);
    }
    return (css: out.join(';'), logo: logo);
  }

  static double _luminance(int argb) {
    double channel(int shift) {
      final v = ((argb >> shift) & 0xFF) / 255;
      return v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4) as double;
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }

  static String? _logoUrl(String source) {
    final text = source.trim();
    final lower = text.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return text;
    }
    if (lower.startsWith('data:image/')) {
      return text;
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(text) ||
        text.startsWith('//') ||
        text.contains('..')) {
      return null;
    }
    // Flutter serves the app's assets below `assets/`.
    return text.startsWith('/') ? text : 'assets/$text';
  }

  // `{type, begin, end, colors, stops}` as a CSS gradient.
  ({String css, double luminance})? _gradient(ThemeNode? node) {
    final list = node?.children['colors'];
    if (node == null || list == null || !list.isList) {
      return null;
    }
    final colors = [
      for (final item in list.items) resolver.color(item),
    ];
    if (colors.length < 2 || colors.contains(null)) {
      return null;
    }
    final stops = node.children['stops'];
    final shares = stops != null && stops.isList
        ? [for (final item in stops.items) resolver.number(item)]
        : null;
    final usable =
        shares != null &&
        shares.length == colors.length &&
        !shares.contains(null);
    final parts = [
      for (var i = 0; i < colors.length; i++)
        cssColor(colors[i]!) +
            (usable ? ' ${cssNumber(shares[i]! * 100)}%' : ''),
    ].join(',');
    final type = canonicalName(
      resolver.text(node.children['type']) ?? 'linear',
    );
    final begin = _alignment(resolver.text(node.children['begin']));
    final average =
        colors.map((c) => _luminance(c!)).reduce((a, b) => a + b) /
        colors.length;
    if (type == 'radial') {
      final at = begin ?? (0.0, 0.0);
      final x = cssNumber((at.$1 + 1) * 50);
      final y = cssNumber((at.$2 + 1) * 50);
      return (
        css: 'radial-gradient(circle min(80vw,80vh) at $x% $y%,$parts)',
        luminance: average,
      );
    }
    final from = begin ?? (-1.0, 0.0);
    final to = _alignment(resolver.text(node.children['end'])) ?? (1.0, 0.0);
    final dx = to.$1 - from.$1;
    final dy = to.$2 - from.$2;
    final angle = (math.atan2(dx, -dy) * 180 / math.pi).round();
    return (css: 'linear-gradient(${angle}deg,$parts)', luminance: average);
  }

  static (double, double)? _alignment(String? raw) {
    if (raw == null) {
      return null;
    }
    const named = {
      'center': (0.0, 0.0),
      'top': (0.0, -1.0),
      'bottom': (0.0, 1.0),
      'left': (-1.0, 0.0),
      'right': (1.0, 0.0),
      'topleft': (-1.0, -1.0),
      'topright': (1.0, -1.0),
      'bottomleft': (-1.0, 1.0),
      'bottomright': (1.0, 1.0),
      'topcenter': (0.0, -1.0),
      'bottomcenter': (0.0, 1.0),
      'centerleft': (-1.0, 0.0),
      'centerright': (1.0, 0.0),
    };
    final found = named[canonicalName(raw)];
    if (found != null) {
      return found;
    }
    final parts = raw.split(',').map((p) => double.tryParse(p.trim())).toList();
    return parts.length == 2 && !parts.contains(null)
        ? (parts[0]!, parts[1]!)
        : null;
  }

  // The leaves of the loader as CSS variables named after the key path.
  void _variables(ThemeNode node, List<String> path, List<String> out) {
    for (final child in node.children.values) {
      final here = [...path, child.spelling];
      if (path.isEmpty &&
          const {
            'kind',
            'web',
            'websha256',
          }.contains(canonicalName(child.spelling))) {
        continue;
      }
      final value = _value(child, here);
      if (value != null) {
        out.add('--${_kebab(here)}:$value');
        // A gradient that turns full circle ends with its first color.
        if (child.isList &&
            scope.nodeKind(child, groups: true) == ValueKind.colors) {
          final first = resolver.color(child.items.first);
          if (first != null) {
            out.add('--${_kebab(here)}-first:${cssColor(first)}');
          }
        }
      } else if (child.children.isNotEmpty && !child.isList) {
        _variables(child, here, out);
      }
    }
  }

  // The CSS text of a leaf (a value, a color object or a list), or null.
  String? _value(ThemeNode node, List<String> path) {
    final isCurve = canonicalName(path.last) == 'curve';
    if (node.entry == null && node.children.isEmpty) {
      return null;
    }
    if (node.entry == null &&
        !node.isList &&
        !(node.children.containsKey('color') &&
            node.children.keys.every(
              const {'color', 'mix', 'alpha'}.contains,
            ))) {
      return null;
    }
    final kind = scope.nodeKind(node, groups: true);
    switch (kind) {
      case null:
        return null;
      case ValueKind.color:
        final c = resolver.color(node);
        return c == null ? null : cssColor(c);
      case ValueKind.number:
        final n = resolver.number(node);
        return n == null ? null : cssNumber(n);
      case ValueKind.duration:
        final ms = resolver.milliseconds(node);
        return ms == null ? null : '${cssNumber(ms)}ms';
      case ValueKind.text:
        final text = resolver.text(node);
        if (text == null) {
          return null;
        }
        if (text == 'true' || text == 'false') {
          return text == 'true' ? '1' : '0';
        }
        return isCurve ? _curve(text) : _cssString(text);
      case ValueKind.colors:
        final items = [for (final i in node.items) resolver.color(i)];
        return items.contains(null)
            ? null
            : items.map((c) => cssColor(c!)).join(',');
      case ValueKind.numbers:
        final items = [for (final i in node.items) resolver.number(i)];
        return items.contains(null)
            ? null
            : items.map((n) => cssNumber(n!)).join(',');
      case ValueKind.texts:
        final items = [for (final i in node.items) resolver.text(i)];
        return items.contains(null)
            ? null
            : items.map((t) => _cssString(t!)).join(',');
      case ValueKind.insets || ValueKind.image:
        return null;
    }
  }

  static String _kebab(List<String> path) => path
      .map(
        (s) => s
            .replaceAllMapped(
              RegExp('([a-z0-9])([A-Z])'),
              (m) => '${m[1]}-${m[2]}',
            )
            .toLowerCase()
            .replaceAll(RegExp('[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), ''),
      )
      .where((s) => s.isNotEmpty)
      .join('-');

  static const _curves = {
    'linear': 'linear',
    'ease': 'ease',
    'easein': 'ease-in',
    'easeout': 'ease-out',
    'easeinout': 'ease-in-out',
    'decelerate': 'cubic-bezier(0,0,.2,1)',
    'fastoutslowin': 'cubic-bezier(.4,0,.2,1)',
    'emphasized': 'cubic-bezier(.2,0,0,1)',
    'emphasizeddecelerate': 'cubic-bezier(.05,.7,.1,1)',
    'emphasizedaccelerate': 'cubic-bezier(.3,0,.8,.15)',
    'easeincubic': 'cubic-bezier(.55,.055,.675,.19)',
    'easeoutcubic': 'cubic-bezier(.215,.61,.355,1)',
    'easeinoutcubic': 'cubic-bezier(.645,.045,.355,1)',
  };

  static String _curve(String name) => _curves[canonicalName(name)] ?? 'ease';
}

// A CSS string: quotes, backslashes, line breaks and `<` escaped, so a
// theme text cannot leave the string or the style element.
String _cssString(String text) {
  final out = StringBuffer('"');
  for (final unit in text.runes) {
    switch (unit) {
      case 0x22: // "
        out.write(r'\22 ');
      case 0x5C: // \
        out.write(r'\5C ');
      case 0x3C: // <
        out.write(r'\3C ');
      case 0x3E: // >
        out.write(r'\3E ');
      case 0x26: // &
        out.write(r'\26 ');
      case 0x0A || 0x0D || 0x0C:
        out.write(r'\A ');
      default:
        if (unit < 0x20) {
          out.write(' ');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  return (out..write('"')).toString();
}

String _attribute(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

String _text(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

// A warning once, however many themes show it.
void _warn(KeysDiagnostics diagnostics, String message) {
  if (!diagnostics.warnings.contains(message)) {
    diagnostics.warnings.add(message);
  }
}
