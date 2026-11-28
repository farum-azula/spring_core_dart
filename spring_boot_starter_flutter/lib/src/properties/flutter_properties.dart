import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart'
    show DebugOverlayLayout;
import 'package:spring_boot_starter_flutter/src/debug/debug_layout.dart'
    show DebugCorner;
import 'package:spring_boot_starter_flutter/src/sqlite_directories.dart'
    show SqliteLocation;

// The settings of the starter that are properties. Each class is the one
// place that names its keys, describes them (the editor metadata is made
// from the fields) and, bound by the Binder, is what the code reads.

/// The app widget `SpringApp` builds, `spring.flutter.app.*`.
@ConfigurationProperties('spring.flutter.app')
final class FlutterAppProperties {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const FlutterAppProperties({
    this.type,
    this.title,
    this.description,
    this.debugBanner = true,
    this.locales,
  });

  /// The kind of app widget SpringApplicationWidget builds: widgets (no
  /// design library), material (with spring_boot_starter_flutter_material),
  /// cupertino (with spring_boot_starter_flutter_cupertino), or the type of
  /// a SpringAppFactory bean of the application. Not set: the one design
  /// starter of the application decides (material or cupertino), widgets
  /// without one; with several, it must be set.
  final String? type;

  /// The title of the app (task switcher, browser tab; the build writes it
  /// into web/index.html and the web manifest).
  final String? title;

  /// What the app is, in a sentence: the build writes it into
  /// web/index.html (the description search engines show) and the web
  /// manifest.
  final String? description;

  /// Whether the debug banner shows in debug builds.
  final bool debugBanner;

  /// The locales the app supports, as language tags. Default: the languages
  /// of the messages files.
  final List<String>? locales;
}

/// Settings of the whole starter that sit directly under `spring.flutter`.
@ConfigurationProperties('spring.flutter')
final class FlutterProperties {
  /// Settings with these values.
  const FlutterProperties({
    this.scanOsEnvironment = false,
    this.shortcuts = const {},
  });

  /// Whether the operating system environment is read as properties. The
  /// application reads it before it has an environment, from the
  /// `--dart-define` values (`scanOsEnvironmentIn`).
  final bool scanOsEnvironment;

  /// The keys of each keyboard shortcut's action (`search.open:
  /// primary+k`): one or a list, `primary` being ⌘ on Apple's platforms
  /// and Ctrl elsewhere, `char:?` a character. They run the action's
  /// `@Shortcut` methods and `ShortcutHandler` beans.
  final Map<String, List<String>> shortcuts;
}

/// The debug panel, `spring.flutter.debug.*`: logs, frames, the
/// configuration, the beans, the themes and the start of the running app,
/// opened with the action `debug.open` (⌘⇧D, or four quick taps and a
/// fifth held three seconds; `spring.flutter.shortcuts.debug.open`).
///
/// The generator reads [enabled] when it writes `main.spring.dart`: with
/// `false` the panel is no code in the app.
@ConfigurationProperties('spring.flutter.debug')
final class FlutterDebugProperties {
  /// Settings with these values.
  const FlutterDebugProperties({
    this.enabled,
    this.frameMeter = const FlutterDebugFeatureProperties(),
    this.motion = const FlutterDebugFeatureProperties(),
    this.timeline = const FlutterDebugFeatureProperties(),
    this.isolates = const FlutterDebugIsolatesProperties(),
    this.console = const FlutterDebugConsoleProperties(),
    this.drag = const FlutterDebugFeatureProperties(),
    this.overlays = const FlutterDebugOverlaysProperties(),
    this.flutterTools = const FlutterDebugFeatureProperties(),
    this.network = const FlutterDebugNetworkProperties(),
    this.logs = const FlutterDebugLogsProperties(),
    this.graph = const FlutterDebugGraphProperties(),
    this.theme = 'default',
    this.themes = const {},
  });

  /// Whether the app has the debug panel: `true` in every build, `false`
  /// in none (the build leaves its code out), not set in debug
  /// builds only (a release build compiles it away).
  final bool? enabled;

  /// The frame meter, on and off by `debug.frame-meter` (⌘⇧X, or five
  /// quick taps and a sixth held two seconds): in the build apart from the
  /// panel, so a release can have it alone.
  final FlutterDebugFeatureProperties frameMeter;

  /// The switch of every animation, `debug.motion` (⌘⇧M): in the build
  /// apart from the panel.
  final FlutterDebugFeatureProperties motion;

  /// The timeline of the start and the observations, the panel's Timeline
  /// tab and the console's `timeline` segment: in the build apart from
  /// the panel; with it, each bean's creation is measured too.
  final FlutterDebugFeatureProperties timeline;

  /// The task manager of the app's isolates and the engine's threads, the
  /// panel's Isolates tab and the console's `isolates` segment: in the
  /// build apart from the panel.
  final FlutterDebugIsolatesProperties isolates;

  /// The debug console over the app, `debug.console` (⌘⇧O, or eight quick
  /// taps and a ninth held): in the build only when enabled.
  final FlutterDebugConsoleProperties console;

  /// Moving the debug overlays by dragging them: in the build apart from
  /// the panel.
  final FlutterDebugFeatureProperties drag;

  /// How the debug overlays of one corner are put together.
  final FlutterDebugOverlaysProperties overlays;

  /// The debug panel's Flutter tab, Flutter's own debug tools (the widget
  /// inspector, the performance overlay, the `debugPaint*` flags): in the
  /// build only as far as the panel is too (`spring.flutter.debug.enabled`
  /// is its parent switch), whatever its own `enabled` says.
  final FlutterDebugFeatureProperties flutterTools;

  /// The network recorder, the panel's Network tab and the console's
  /// `network` pane and `net` segment: every request of the app's
  /// `HttpTransport` and `WebSocketTransport` beans (`RestClient`, the OAuth2
  /// client, Supabase, the WebSocket starter...), masked. In the build
  /// only when enabled, and only with a view: the panel, or the console
  /// with the pane or the segment.
  final FlutterDebugNetworkProperties network;

  /// What the panel's Logs tab and the console do with the records beyond
  /// showing them.
  final FlutterDebugLogsProperties logs;

  /// The application graph: the panel's Graph tab and the console's
  /// `graph` pane, the layers the starters give (`signals`).
  final FlutterDebugGraphProperties graph;

  /// The debug theme the debug tools start with: `default` (the built-in
  /// one, from the app's theme), one of [themes] or a `DebugTheme` bean's
  /// name. A name no theme has fails the start. The panel's Theme tab
  /// switches it live. Read only in a build with the panel or the
  /// console: with neither, debug themes are no code in the app.
  final String theme;

  /// Debug themes by name, `spring.flutter.debug.themes.<name>.*`: the
  /// colours and the font of the debug panel, the console and the frame
  /// meter; what a theme does not set is the built-in theme's. A key a
  /// theme does not have, or a value that is not a colour, fails the start.
  final Map<String, FlutterDebugThemeProperties> themes;
}

/// A debug theme of `spring.flutter.debug.themes.<name>.*`. A colour is
/// `#RRGGBB`, `#AARRGGBB` or a `Colors` name; one not set is the built-in
/// theme's, which takes the app theme's colours and a terminal's palette
/// for a dark background or a light one.
final class FlutterDebugThemeProperties {
  /// A theme of these values.
  const FlutterDebugThemeProperties({
    this.background,
    this.text,
    this.dim,
    this.accent,
    this.number,
    this.good,
    this.warning,
    this.bad,
    this.error,
    this.line,
    this.levelError,
    this.levelWarning,
    this.levelInfo,
    this.levelDebug,
    this.time,
    this.logger,
    this.command,
    this.argument,
    this.methodRead,
    this.methodWrite,
    this.graphFlash,
    this.graphHot,
    this.fontFamily,
    this.fontSize,
  });

  /// The fill of the panel, the console and the frame meter.
  final String? background;

  /// The text.
  final String? text;

  /// Secondary text: labels, hints, the echo of a command typed.
  final String? dim;

  /// What is selected or on: a chip, the input's `>`.
  final String? accent;

  /// The numbers of the console's header and the frame meter's rate; the
  /// accent by default.
  final String? number;

  /// A state that is fine (a header segment, a frame within budget).
  final String? good;

  /// A warning state.
  final String? warning;

  /// A state that is wrong.
  final String? bad;

  /// What a command reports as gone wrong.
  final String? error;

  /// Lines between rows, borders, the resize handles.
  final String? line;

  /// The level of an error record.
  final String? levelError;

  /// The level of a warning record.
  final String? levelWarning;

  /// The level of an info record.
  final String? levelInfo;

  /// The level of a debug or trace record.
  final String? levelDebug;

  /// The time of a record and the `:` after its logger.
  final String? time;

  /// The logger of a record.
  final String? logger;

  /// A command's word in the console's commands pane; orange by default.
  final String? command;

  /// How a command's arguments are written, in `help`.
  final String? argument;

  /// A method that reads (`GET`, `HEAD`, `OPTIONS`, `TRACE`) in the
  /// Network tab; terminal cyan by default.
  final String? methodRead;

  /// A method that writes (`POST`, `PUT`, `PATCH`, `DELETE`) in the
  /// Network tab; `command`'s orange by default.
  final String? methodWrite;

  /// What lights a node of the application graph that just changed or ran
  /// (its border, glow, at most a quarter of its fill, the pulse along its
  /// edges); a terminal's yellow by default.
  final String? graphFlash;

  /// The outline of a hot branch of the application graph (the widgets
  /// that rebuild often, the branch above them); a terminal's magenta by
  /// default, a hue apart from every layer's.
  ///
  /// The nodes of a graph layer take the theme's `graph-<layer id>` (any
  /// key of that form is a theme's): `graph-beans` (`good`'s green by
  /// default), `graph-widgets` (`logger`'s cyan blue), `graph-signals`
  /// (`command`'s orange), else a colour of the theme's palette.
  final String? graphHot;

  /// The font family of every debug tool's text; the app theme's by
  /// default (its `code` style for the logs and the console).
  final String? fontFamily;

  /// The size of the logs' and the console's text; 11 by default.
  final double? fontSize;
}

/// `spring.flutter.debug.network.*`.
final class FlutterDebugNetworkProperties {
  /// Settings with these values.
  const FlutterDebugNetworkProperties({
    this.enabled,
    this.bodies = false,
    this.bodyLimit = const DataSize.ofBytes(64 * 1024),
    this.bodyBudget = const DataSize.ofBytes(4 * 1024 * 1024),
    this.maxEntries = 200,
    this.maxFrames = 200,
  });

  /// Whether the app has the network recorder and its views: `true` in
  /// every build that has the debug panel (the Network tab) or the
  /// console with its `network` pane or `net` segment, `false` or not set
  /// in none (the build leaves its code out). Set to `false` in a profile,
  /// it turns off the recorder of a running app whose build has it.
  final bool? enabled;

  /// Whether request and response bodies and WebSocket payloads are kept,
  /// cut at [bodyLimit], their secrets masked (JSON keys and form
  /// parameters that look secret). Off: only the sizes.
  final bool bodies;

  /// The most bytes of a body or a payload kept; at most 1MB, a larger
  /// value is taken as 1MB.
  final DataSize bodyLimit;

  /// The most bytes of bodies and payloads the recorder keeps in all,
  /// with [bodies]: past it, a new one keeps its size only, until old
  /// requests leave the journal.
  final DataSize bodyBudget;

  /// How many requests and WebSocket connections are kept; the oldest goes
  /// first.
  @Range(1, 10000)
  final int maxEntries;

  /// How many frames of each WebSocket connection are kept; the counts go
  /// on past it.
  @Range(0, 10000)
  final int maxFrames;
}

/// `spring.flutter.debug.graph.*`: the application graph.
final class FlutterDebugGraphProperties {
  /// Settings with these values.
  const FlutterDebugGraphProperties({
    this.enabled,
    this.layers = const ['*'],
    this.hot = const FlutterDebugGraphHotProperties(),
  });

  /// Whether the app has the panel's Graph tab: `true` in every build with
  /// the panel, `false` in none (the build leaves its code out), not set in
  /// debug builds only. Its engine is in the build only with a
  /// layer ([layers]); the console's `graph` pane comes by
  /// `spring.flutter.debug.console.panes` instead.
  final bool? enabled;

  /// The layers the build has, by name: this starter's `widgets` and
  /// `beans`, a starter's own, `*` for every one. Read by the build: a
  /// layer it does not name is left out, its code and bean with it; with
  /// none, the Graph tab, the `graph` pane and the engine are no code in
  /// the app.
  final List<String> layers;

  /// When a widget's branch is hot: outlined in the debug theme's
  /// `graph-hot`, from the widget up to the root.
  final FlutterDebugGraphHotProperties hot;
}

/// `spring.flutter.debug.graph.hot.*`: the hot branches of the widgets
/// layer.
final class FlutterDebugGraphHotProperties {
  /// Settings with these values.
  const FlutterDebugGraphHotProperties({
    this.rebuilds = 3,
    this.window = const Duration(seconds: 5),
  });

  /// How many rebuilds within [window] make a widget hot (its node and the
  /// branch above it outlined, its tooltip telling `PageBackdrop: 14
  /// rebuilds in 5 s`).
  @Range(1, 100000)
  final int rebuilds;

  /// The window the rebuilds are counted in; also the window of a
  /// widget's rebuild count in its card.
  final Duration window;
}

/// `spring.flutter.debug.logs.*`.
final class FlutterDebugLogsProperties {
  /// Settings with these values.
  const FlutterDebugLogsProperties({
    this.export = const FlutterDebugLogsExportProperties(),
  });

  /// The export of the records as a file (`.log`, `.jsonl`).
  final FlutterDebugLogsExportProperties export;
}

/// `spring.flutter.debug.logs.export.*`.
final class FlutterDebugLogsExportProperties {
  /// Settings with these values.
  const FlutterDebugLogsExportProperties({this.enabled});

  /// Whether the app has the log export (the Logs tab's `Export .log` and
  /// `Export .jsonl`, and the `DebugFileExport` beans): `true` in every
  /// build, `false` in none (the build leaves its code out), not set in
  /// debug builds only. In any case only as far as the debug
  /// panel or the console is in the build too. Set to `false` in a
  /// profile, it turns off the export of a running app whose build has it.
  final bool? enabled;
}

/// `spring.flutter.debug.isolates.*`.
final class FlutterDebugIsolatesProperties {
  /// Settings with these values.
  const FlutterDebugIsolatesProperties({
    this.enabled,
    this.interval = const Duration(seconds: 1),
  });

  /// Whether the app has the task manager: `true` in every build, `false`
  /// in none (the build leaves its code out), not set in debug
  /// builds only (a release build compiles it away).
  final bool? enabled;

  /// How often it reads the loads and the memory while its tab or the
  /// console's `isolates` or `memory` segment shows; nothing is read, or
  /// measured, while none does.
  final Duration interval;
}

/// `spring.flutter.debug.console.*`.
final class FlutterDebugConsoleProperties {
  /// Settings with these values.
  const FlutterDebugConsoleProperties({
    this.enabled,
    this.position = DebugCorner.topLeft,
    this.opacity = 0.9,
    this.interaction = DebugConsoleInteraction.interact,
    this.passThroughOpacity = 0.7,
    this.slideDuration = const Duration(milliseconds: 220),
    this.maxLines = 12,
    this.width = 1,
    this.segments = const ['fps', 'scene-fps', 'frames-lost', 'filter'],
    this.header,
    this.panes = const ['logs'],
    this.shownPanes,
    this.history = 50,
    this.filter = const FlutterDebugLogsFilterProperties(),
  });

  /// Whether the app has the console: `true` in every build, `false` or
  /// not set in none (the build leaves its code out).
  final bool? enabled;

  /// The corner it shows in.
  final DebugCorner position;

  /// How opaque its background is, from 0 (the records alone over the
  /// app) to 1; the records stay opaque. The panes' while they interact,
  /// the header's always.
  @Range(0, 1)
  final double opacity;

  /// How its panes take the pointer at the start: `pass-through`, every
  /// tap, scroll, hover and drag over them reaches the app, only the
  /// header and the handles take one; `interact`, the panes work (the
  /// records scroll and select, the input line types), the default. The
  /// toggle at the right of the header switches it while the app runs, ⌥
  /// (Alt) held on a desktop interacts while held.
  final DebugConsoleInteraction interaction;

  /// How opaque the panes' background is while they pass the pointer
  /// through, from 0 (none: the app shows as it is, only the panes' text
  /// over it) to 1; 0.7 by default, the app seen and the panes read. A
  /// pane's own opacity counts only while they interact. The header keeps
  /// `opacity`.
  @Range(0, 1)
  final double passThroughOpacity;

  /// How long it takes to slide in from its edge when shown and back out
  /// when hidden, as a game's console drops down (from the top in a top
  /// corner, from the bottom in a bottom one); 0 shows and hides it at
  /// once.
  final Duration slideDuration;

  /// How many lines high the `logs` pane starts; long records wrap, and
  /// older ones are a scroll away, as far back as the log buffer keeps
  /// them. The divider under it moves the room between it and the pane
  /// below; the lowest pane, the handle on the console's lower edge (by
  /// mouse or touch). The heights dragged to are kept while the app runs.
  @Range(1, 200)
  final int maxLines;

  /// How much of a wide screen's width it takes, from 0.2 to 1; on a
  /// phone (narrower than 600) all of it.
  @Range(0.2, 1)
  final double width;

  /// The segments the build has, by name: this starter's (`fps`,
  /// `frames-lost`, `filter`, `isolates` and `memory` with the task
  /// manager, `timeline`, `net` with the network recorder), another
  /// starter's, an application's own (`@ConsoleSegment`); `*` stands for
  /// every one. Read by the build: a segment it does not name (and no `*`)
  /// is left out of the build, its code and bean with it. Not set, each
  /// segment's module says whether it is in (this starter's `fps`,
  /// `frames-lost` and `filter` are, and a starter documents its own); the
  /// default list gives the header's order of those. Their order is the
  /// header's when `header` is not set.
  final List<String> segments;

  /// The segments the header shows at the start, in its order; `*` stands
  /// for the others of `segments`. Not set: all of `segments`. A name that
  /// `segments` does not have fails the start. The debug panel's Console
  /// tab shows, hides and moves them while the app runs.
  final List<String>? header;

  /// The panes the build has, by name: `logs` (the records of the log
  /// buffer, with their selection and the `export` command), `commands`
  /// (the commands and their input line, with the application's
  /// `@ConsoleCommand` classes), a starter's (`network`), an application's
  /// own (`@ConsolePane`); `*` stands for every one. Read by the build: a
  /// pane it does not name (and no `*`) is left out of the build, its code
  /// and bean with it. `[logs]` by default; listed, `logs` is in only when
  /// named.
  final List<String> panes;

  /// The panes shown at the start, under the header by their own order;
  /// `*` stands for all of `panes`. Not set: `logs` when the build has it;
  /// empty: the header alone. A name that `panes` does not have fails the
  /// start. The debug panel's Console tab shows and hides them while the
  /// app runs.
  final List<String>? shownPanes;

  /// How many lines typed into the `commands` pane up and down go back
  /// through.
  @Range(0, 1000)
  final int history;

  /// The records it shows at the start; with the debug panel, its Logs
  /// tab starts with it too, and changes it for both.
  final FlutterDebugLogsFilterProperties filter;
}

/// `spring.flutter.debug.console.filter.*`.
final class FlutterDebugLogsFilterProperties {
  /// Settings with these values.
  const FlutterDebugLogsFilterProperties({
    this.level = SpringLogLevel.trace,
    this.text = '',
  });

  /// The lowest level shown.
  final SpringLogLevel level;

  /// What a record's message or logger name must contain, in any case;
  /// empty: every record.
  final String text;
}

/// `spring.flutter.debug.overlays.*`: the overlays of the debug features
/// (the frame meter, the console) that show in one corner.
final class FlutterDebugOverlaysProperties {
  /// Settings with these values.
  const FlutterDebugOverlaysProperties({
    this.layout = DebugOverlayLayout.auto,
    this.maxHeight = 0.4,
    this.margin = const FlutterDebugOverlaysMargin(),
    this.drag = const FlutterDebugOverlaysDrag(),
  });

  /// `auto`: one under the other when they fit in the corner's room, else
  /// one at a time with dots to swipe between; `stack` or `pages` always.
  final DebugOverlayLayout layout;

  /// The room of a corner for `auto`, a fraction of the screen's height.
  final double maxHeight;

  /// Kept free around the overlays (a header under the top corners), past
  /// the screen's safe area, in logical pixels.
  final FlutterDebugOverlaysMargin margin;

  /// How a dragged overlay is placed (the `drag` feature).
  final FlutterDebugOverlaysDrag drag;
}

/// `spring.flutter.debug.overlays.margin.*`, in logical pixels.
final class FlutterDebugOverlaysMargin {
  /// Settings with these values.
  const FlutterDebugOverlaysMargin({
    this.top = 0,
    this.bottom = 0,
    this.left = 0,
    this.right = 0,
  });

  /// Above the top corners.
  final double top;

  /// Under the bottom corners.
  final double bottom;

  /// Left of the left corners.
  final double left;

  /// Right of the right corners.
  final double right;
}

/// `spring.flutter.debug.overlays.drag.*`.
final class FlutterDebugOverlaysDrag {
  /// Settings with these values.
  const FlutterDebugOverlaysDrag({
    this.snap = DebugOverlaySnap.corners,
    this.remember = true,
  });

  /// `corners`: a dropped overlay joins the nearest corner; `free`: it
  /// stays where it is dropped.
  final DebugOverlaySnap snap;

  /// Whether a moved overlay is where it was left after the app restarts.
  final bool remember;
}

/// Where a dragged debug overlay goes when it is dropped.
enum DebugOverlaySnap {
  /// The nearest corner, with its others.
  corners,

  /// Where it was dropped.
  free,
}

/// How the debug console's panes take the pointer
/// (`spring.flutter.debug.console.interaction`).
enum DebugConsoleInteraction {
  /// Not at all: every tap, scroll, hover and drag over them reaches the
  /// app under the console; the header and the handles still take theirs.
  passThrough,

  /// As each pane does: the records scroll and select, a row takes a tap,
  /// the graph pans, the input line types.
  interact,
}

/// A debug feature in the build or not, `spring.flutter.debug.<feature>.*`.
final class FlutterDebugFeatureProperties {
  /// Settings with these values.
  const FlutterDebugFeatureProperties({this.enabled});

  /// Whether the app has the feature: `true` in every build, `false` in
  /// none (the build leaves its code out), not set in debug builds only (a
  /// release build compiles it away).
  final bool? enabled;
}

/// How `MarkdownView` reads its pages, `spring.flutter.markdown.*`.
@ConfigurationProperties('spring.flutter.markdown')
final class FlutterMarkdownProperties {
  /// Settings with these values.
  const FlutterMarkdownProperties({this.placeholders = false});

  /// Replaces each `{{key}}` of a page by the value of the configuration's
  /// key (`{{site.version}}`); one whose key has no value stays as it is,
  /// and `\{{` writes `{{`. The build's pages for search engines do the
  /// same (`BracePlaceholders`).
  final bool placeholders;
}

/// The frame meter, `spring.flutter.frame-meter.*`: a small panel over
/// the app with the frames a second it really draws and their times, to
/// see on a phone whether it keeps up. Its look is the theme's
/// `frame-meter`.
@ConfigurationProperties('spring.flutter.frame-meter')
final class FlutterFrameMeterProperties {
  /// Settings with these values.
  const FlutterFrameMeterProperties({
    this.enabled = false,
    this.position = DebugCorner.topRight,
    this.targetRate = 60,
  });

  /// Whether the meter shows. Off by default; turn it on in a profile you
  /// test with, not for your users.
  final bool enabled;

  /// The corner of the screen it shows in.
  final DebugCorner position;

  /// The frames a second the screen is meant to show: a frame within
  /// `1 / target-rate` is good, up to twice that a warning, more a drop.
  final int targetRate;
}

/// The web page around the app, `spring.flutter.web.page.*`; read by
/// the generator, which writes it into `web/index.html`.
@ConfigurationProperties('spring.flutter.web.page')
final class FlutterWebPageProperties {
  /// Settings with these values.
  const FlutterWebPageProperties({
    this.swipeToClose = true,
    this.maxPixelRatio,
    this.translate = true,
    this.wasmAllowList,
  });

  /// Whether a swipe down may close the page where the browser does so:
  /// an app's own browser (a messenger's, a social app's).
  /// `false` keeps the page open; the swipe then scrolls the app.
  final bool swipeToClose;

  /// The most pixels for each point Flutter draws at, written into
  /// `web/index.html` by the build. A phone's screen has 3: every frame is
  /// 9 times the pixels of the page, and its graphics chip drops frames on
  /// a full-screen scroll. 2 draws 2.25 times fewer, the text still sharp.
  /// `null`: the screen's own.
  final double? maxPixelRatio;

  /// Whether browsers and Google may offer to translate the page. Flutter
  /// draws its text on a canvas, so a translator finds none: `false`
  /// writes `translate="no"` and `<meta name="google"
  /// content="notranslate">` into `web/index.html`, and the offer is gone.
  final bool translate;

  /// The browser engines that run the WebAssembly of a `--wasm` build,
  /// `spring.flutter.web.page.wasm-allow-list.<engine>`: `blink` (Chrome,
  /// Edge), `gecko` (Firefox 147 and newer) and `webkit` (Safari 26.2 and
  /// newer), each `true` or `false`; an engine not allowed loads the
  /// JavaScript build. The build passes it to Flutter's loader as
  /// `config.wasmAllowList`, under what the app's own
  /// `flutter_bootstrap.js` passes. `null`: Flutter's default, Blink
  /// only.
  final Map<String, bool>? wasmAllowList;
}

/// The lifecycle of the app, `spring.flutter.lifecycle.*`.
@ConfigurationProperties('spring.flutter.lifecycle')
final class FlutterLifecycleProperties {
  /// Settings with these values.
  const FlutterLifecycleProperties({this.pauseInBackground = true});

  /// Whether scheduled work pauses while the app is in the background.
  final bool pauseInBackground;
}

/// The loading of the fonts of the app, `spring.flutter.fonts.*`.
@ConfigurationProperties('spring.flutter.fonts')
final class FlutterFontsProperties {
  /// Settings with these values.
  const FlutterFontsProperties({
    this.autoLoad = true,
    this.exclude,
    this.families,
  });

  /// Whether the fonts named by the theme are loaded from the assets.
  final bool autoLoad;

  /// Asset globs the font loader skips.
  final List<String>? exclude;

  /// Font families declared by name, `spring.flutter.fonts.families.<family>.*`:
  /// their asset files, and the languages they are for. One for a
  /// language is loaded when the app shows that language, not before.
  final Map<String, FontFamilyProperties>? families;
}

/// A font family of `spring.flutter.fonts.families.<family>`.
final class FontFamilyProperties {
  /// A family of these files, for these languages.
  const FontFamilyProperties({this.files = const [], this.languages});

  /// The asset files of the family (`assets/fonts/NotoSansJP.woff2`); a
  /// file's format is any the platform reads (`.ttf`, `.otf`; `.woff2`
  /// on the web).
  final List<String> files;

  /// The languages the family is for (`ja`, `zh-Hant`): loaded before the
  /// first frame when the app starts in one of them, else when it switches
  /// to one. None: loaded before the first frame, always.
  final List<String>? languages;
}

/// The desktop window as text, `spring.flutter.desktop.window.*`; the
/// starter turns the sizes and the title bar into `DesktopWindowSettings`.
@ConfigurationProperties('spring.flutter.desktop.window')
final class DesktopWindowProperties {
  /// Settings with these values.
  const DesktopWindowProperties({
    this.title,
    this.titleBar = 'default',
    this.initialSize,
    this.minSize,
    this.maxSize,
  });

  /// The prefix of the properties.
  static const prefix = 'spring.flutter.desktop.window';

  /// The title of the desktop window.
  final String? title;

  /// How the title bar of the desktop window looks: `default` (the
  /// platform's), `transparent` (the app draws under a transparent title
  /// bar) or `hidden` (no title bar; the app draws its own).
  @PropertyValues(['default', 'transparent', 'hidden'])
  final String titleBar;

  /// The size of the window at start, as WIDTHxHEIGHT in logical pixels,
  /// e.g. 1280x800.
  final String? initialSize;

  /// The smallest size of the window, as WIDTHxHEIGHT.
  final String? minSize;

  /// The largest size of the window, as WIDTHxHEIGHT.
  final String? maxSize;
}

/// The dev server of `flutter run` on the web,
/// `spring.flutter.web.dev-server.*`.
///
/// Nothing reads it at run time: the generator reads these keys from the
/// configuration files at build time and writes `web_dev_config.yaml`. The
/// class describes them for editors. Before 0.7.1 the keys were directly
/// under `spring.flutter.web`; such a key now fails the build with its new
/// name.
@ConfigurationProperties('spring.flutter.web.dev-server')
final class FlutterWebProperties {
  /// Settings with these values; all unset by default.
  const FlutterWebProperties({
    this.host,
    this.port,
    this.baseHref,
    this.https,
    this.headers,
    this.contentSecurityPolicy,
    this.contentSecurityPolicyReportOnly,
    this.contentSecurityPolicyConnectSrc,
    this.proxy,
  });

  /// The address the dev server of flutter run on the web listens on, e.g.
  /// localhost or 0.0.0.0.
  final String? host;

  /// The port of the web dev server; 0 picks a free port.
  @Range(0, 65535)
  @WarnValues(
    [
      1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77,
      79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123,
      135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526,
      530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993,
      995, 1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061, 6000, 6566,
      6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080, //
    ],
    "Browsers refuse to open this port (Chromium's list of blocked ports).",
  )
  final int? port;

  /// The path the app is served under; starts and ends with /.
  final String? baseHref;

  /// TLS for the web dev server.
  final FlutterWebHttps? https;

  /// A header added to every response of the web dev server.
  final Map<String, String>? headers;

  /// The Content-Security-Policy header of the web dev server.
  final String? contentSecurityPolicy;

  /// Whether `content-security-policy` is sent as
  /// `Content-Security-Policy-Report-Only`: the browser reports what the
  /// policy would block and blocks nothing. `false` (the default) enforces
  /// it.
  final bool? contentSecurityPolicyReportOnly;

  /// Origins added to the `connect-src` of spa mode's ready policy: the APIs
  /// the app calls, a provider's endpoints on other hosts. Default: none.
  final List<String>? contentSecurityPolicyConnectSrc;

  /// Rules that forward requests of the dev server to another server.
  final List<FlutterWebProxyRule>? proxy;
}

/// TLS of the web dev server, `spring.flutter.web.dev-server.https.*`.
final class FlutterWebHttps {
  /// Settings with these values.
  const FlutterWebHttps({this.certPath, this.certKeyPath});

  /// The TLS certificate (PEM) of the web dev server.
  final String? certPath;

  /// The private key (PEM) of the certificate.
  final String? certKeyPath;
}

/// One forwarding rule of the web dev server,
/// `spring.flutter.web.dev-server.proxy[n]`.
final class FlutterWebProxyRule {
  /// A rule with these values; each sets exactly one of prefix and regex.
  const FlutterWebProxyRule({
    this.prefix,
    this.regex,
    this.replace,
    this.target,
  });

  /// Rule `n` matches paths starting with it (`/api/`). Default: none.
  final String? prefix;

  /// Or the paths matching it; each rule sets exactly one of `prefix` and
  /// `regex`. Default: none.
  final String? regex;

  /// The forwarded path: the matched part replaced, `$1` for the first
  /// group. Default: the path unchanged.
  final String? replace;

  /// Where requests matching rule `n` are forwarded
  /// (`http://localhost:8080`). Default: none.
  final String? target;
}

/// The pages the build writes for search engines, link previews and
/// models, `spring.flutter.web.seo.*`.
///
/// A Flutter web page draws on a canvas: its HTML holds no text. With
/// [enabled], the generator writes into `web/` a page per route and
/// Markdown file (its title, description, preview and text in plain HTML,
/// never shown), `sitemap.xml`, `robots.txt`, `llms.txt` and
/// `llms-full.txt`; `flutter build web` copies them. Nothing reads these
/// keys at run time; the class describes them for editors.
///
/// ```yaml
/// # lib/resources/application-web.yml
/// spring.flutter.web.seo:
///   enabled: true
///   site-url: https://spring-dart.dev
///   from-routes: true
///   title: '{title} · Spring Dart'
/// ```
@ConfigurationProperties('spring.flutter.web.seo')
final class FlutterWebSeoProperties {
  /// Settings with these values; off by default.
  const FlutterWebSeoProperties({
    this.enabled = false,
    this.siteUrl,
    this.fromRoutes = false,
    this.exclude,
    this.title = '{title}',
    this.description,
    this.image,
    this.siteName,
    this.content,
    this.pages,
    this.sitemap = true,
    this.llms = true,
    this.markdown = true,
    this.lastmod = true,
    this.pageFiles = 'directory',
  });

  /// Whether the build writes the pages.
  final bool enabled;

  /// The site's address (`https://spring-dart.dev`), for the absolute
  /// addresses of `canonical`, `og:url` and the sitemap; required when
  /// [enabled]. Its path is where the app is served.
  final String? siteUrl;

  /// Whether every screen of `spring_boot_starter_flutter_navigation` is a
  /// page (its title, `@RouteInfo`, its Markdown).
  final bool fromRoutes;

  /// Files of every Markdown folder, the routes' and `content[n]`'s, that
  /// make no page: globs from the folder (`**/contents*.md`, a table of
  /// contents the site reads for its menu). `*` matches within a folder,
  /// `**` across folders, and `**/` no folder too.
  final List<String>? exclude;

  /// The page's `<title>`; `{title}` is the page's own.
  final String title;

  /// The description of a page that has none.
  final String? description;

  /// The preview image of a page that has none
  /// (`resources:images/og.png`). Link previews (messengers, X, Slack) show
  /// it large: about 1200×630.
  final String? image;

  /// The site's name in a link preview (`og:site_name`).
  final String? siteName;

  /// Folders of Markdown files, a page per file.
  final List<FlutterWebSeoContent>? content;

  /// Pages by hand, or what a route says overridden.
  final List<FlutterWebSeoPage>? pages;

  /// Whether `sitemap.xml` and `robots.txt` are written.
  final bool sitemap;

  /// Whether `llms.txt` and `llms-full.txt` are written.
  final bool llms;

  /// Whether the Markdown of a page is written next to it (`<path>.md`).
  final bool markdown;

  /// Whether the sitemap gives each Markdown page its `lastmod`: the day
  /// of the last commit that changed its file (`git log`); none in a
  /// shallow clone, whose one commit would date every page (a CI checkout
  /// needs `fetch-depth: 0`).
  final bool lastmod;

  /// How a page's file is named: `directory` (`<path>/index.html`, which a
  /// static host serves after a redirect to `<path>/`, so the page's
  /// addresses end with `/`) or `html` (`<path>.html`, which Cloudflare
  /// Pages, GitHub Pages and Netlify serve at `<path>` with no redirect).
  final String pageFiles;
}

/// The browser cache of a web build, Spring Boot's
/// `spring.web.resources.cache.cachecontrol.*`.
///
/// Nothing reads it at run time: the generator reads these keys from the
/// configuration files at build time and writes a block of rules into the
/// app's `web/_headers` (Cloudflare Pages): `no-cache` for the files without
/// a hash in their names, the `Cache-Control` these keys build for the
/// app's images and fonts (`/assets/*`). The class describes them for
/// editors; a server of `spring_boot_starter_web` reads the same keys for
/// its static resources.
@ConfigurationProperties('spring.web.resources.cache.cachecontrol')
final class FlutterWebCacheControlProperties {
  /// Settings with these values; all unset by default.
  const FlutterWebCacheControlProperties({
    this.maxAge,
    this.noCache,
    this.noStore,
    this.mustRevalidate,
    this.noTransform,
    this.cachePublic,
    this.cachePrivate,
    this.proxyRevalidate,
    this.staleWhileRevalidate,
    this.staleIfError,
    this.sMaxAge,
  });

  /// `max-age`: how long the app's images and fonts are kept without
  /// asking again (`30d`). A number without a unit is seconds.
  final Duration? maxAge;

  /// `no-cache`: kept, used only after the server confirmed it.
  final bool? noCache;

  /// `no-store`: never kept. Wins over `no-cache` and `max-age`.
  final bool? noStore;

  /// `must-revalidate`: once stale, not used without asking the server.
  final bool? mustRevalidate;

  /// `no-transform`: proxies must not change the content.
  final bool? noTransform;

  /// `public`: shared caches (a CDN) may keep them too.
  final bool? cachePublic;

  /// `private`: only the user's own browser may keep them.
  final bool? cachePrivate;

  /// `proxy-revalidate`: `must-revalidate` for shared caches only.
  final bool? proxyRevalidate;

  /// `stale-while-revalidate`: how long a stale file may be used while a
  /// fresh one is fetched. A number without a unit is seconds.
  final Duration? staleWhileRevalidate;

  /// `stale-if-error`: how long a stale file may be used when the server
  /// fails. A number without a unit is seconds.
  final Duration? staleIfError;

  /// `s-maxage`: how long shared caches may keep them. A number without a
  /// unit is seconds.
  final Duration? sMaxAge;
}

/// A folder of Markdown files, `spring.flutter.web.seo.content[n]`.
final class FlutterWebSeoContent {
  /// A folder with these values.
  const FlutterWebSeoContent({this.location, this.path = '/', this.exclude});

  /// The folder (`resources:content/blog/`).
  final String? location;

  /// The address of the folder (`/blog`): `first.md` is `/blog/first`,
  /// `index.md` is `/blog`.
  final String path;

  /// Files left out, globs below the folder (`_*.md`).
  final List<String>? exclude;
}

/// A page by hand, `spring.flutter.web.seo.pages[n]`.
final class FlutterWebSeoPage {
  /// A page with these values.
  const FlutterWebSeoPage({
    this.path,
    this.title,
    this.description,
    this.image,
    this.index,
  });

  /// The page's address (`/`).
  final String? path;

  /// Its title.
  final String? title;

  /// Its description.
  final String? description;

  /// Its preview image.
  final String? image;

  /// `false`: search engines may not list it (`noindex`, not in the
  /// sitemap).
  final bool? index;
}

/// The development switches under `spring.devtools.restart`.
@ConfigurationProperties('spring.devtools.restart')
final class FlutterRestartProperties {
  /// Settings with these values.
  const FlutterRestartProperties({this.enabled = true});

  /// A hot reload restarts the context when the generated code changed:
  /// beans, annotations or `lib/resources/`.
  final bool enabled;
}

/// The data source properties the starter reads to put SQLite files in the
/// app's directory, `spring.datasource.*`; the rest belongs to
/// `spring_boot_starter_data`.
@ConfigurationProperties('spring.datasource')
final class FlutterDataSourceProperties {
  /// Settings with these values.
  const FlutterDataSourceProperties({
    this.url,
    this.sqlite = const FlutterSqliteProperties(),
  });

  /// The prefix of the unnamed data source.
  static const prefix = 'spring.datasource';

  /// The database URL; the Flutter starter reads it to put SQLite files in
  /// the app's directory (see `spring_boot_starter_data`).
  final String? url;

  /// The SQLite settings the starter provides.
  final FlutterSqliteProperties sqlite;
}

/// The SQLite setting the starter reads, `spring.datasource.sqlite.location`;
/// the others (`base-directory`, `isolate`), which the starter sets, are
/// described by `spring_boot_starter_data`.
final class FlutterSqliteProperties {
  /// Settings with these values.
  const FlutterSqliteProperties({this.location = SqliteLocation.support});

  /// Which directory of the app holds the databases, the one the starter
  /// sets `base-directory` to; any other value stops the start, naming
  /// these three.
  final SqliteLocation location;
}

/// The named data sources, `spring.datasources.<name>.*`.
@ConfigurationProperties('spring')
final class FlutterDataSourcesProperties {
  /// Settings with these values.
  const FlutterDataSourcesProperties({this.datasources});

  /// The prefix of the named data sources.
  static const prefix = 'spring.datasources';

  /// The named databases; each is read like `spring.datasource`.
  final Map<String, FlutterDataSourceProperties>? datasources;
}

/// The resources downloaded and kept, `spring.flutter.resources.cache.*`:
/// an `http:` or `https:` resource (`ResourceView`, `ResourceImage`, a
/// `Resource` of `@Value` or the `ResourceLoader`) is read from the app's
/// files once kept, and asked again in the background past its age.
@ConfigurationProperties('spring.flutter.resources.cache')
final class FlutterResourcesCacheProperties {
  /// Settings with these values.
  const FlutterResourcesCacheProperties({
    this.enabled = true,
    this.maxAge = const Duration(days: 7),
    this.maxEntrySize,
    this.maxSize,
    this.locations = const [],
  });

  /// Whether `http:` and `https:` resources are kept on disk.
  final bool enabled;

  /// How long a kept resource is used as it is; past it, it is still used
  /// and asked again in the background (`If-None-Match` /
  /// `If-Modified-Since`: an unchanged one costs no download).
  final Duration maxAge;

  /// The largest resource kept; a larger one is read from the network
  /// every time. Not set: 50 MB.
  final DataSize? maxEntrySize;

  /// The most bytes the kept resources take together; past it the least
  /// recently used go first. Their own folder of the app's `cache` place,
  /// `spring/resources/`: the `@Cacheable` caches on disk
  /// (`spring.cache.type: disk`) keep theirs with limits of their own. Not
  /// set: no limit but the system's.
  final DataSize? maxSize;

  /// Rules by address, the first that matches wins: `pattern` (`**` any
  /// path, `*` one segment), and its own `max-age` or `enabled: false`.
  final List<ResourceCacheLocation> locations;
}

/// A rule of `spring.flutter.resources.cache.locations`.
@Introspected()
final class ResourceCacheLocation {
  /// A rule with these values.
  const ResourceCacheLocation({
    this.pattern = '',
    this.maxAge,
    this.enabled = true,
  });

  /// The addresses it is for: `https://avatars.steamstatic.com/**`.
  final String pattern;

  /// Their age; not set: `spring.flutter.resources.cache.max-age`.
  final Duration? maxAge;

  /// `false`: they are not kept.
  final bool enabled;
}

/// How `ResourceView` shows a resource, `spring.flutter.resources.view.*`.
@ConfigurationProperties('spring.flutter.resources.view')
final class FlutterResourcesViewProperties {
  /// Settings with these values.
  const FlutterResourcesViewProperties({
    this.fade = const Duration(milliseconds: 200),
  });

  /// How long a resource fades in over its placeholder once it is there;
  /// `0` shows it at once (and so does less motion asked by the system).
  final Duration fade;
}
