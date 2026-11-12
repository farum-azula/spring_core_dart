import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_choice_store.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_design.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// All the themes of the app, read from the `spring.flutter.theme.*`
/// properties: the standard `light` and `dark`, and every custom theme of
/// `themes.<name>`.
///
/// The look of the app is configuration rather than `ThemeData` code, and
/// this bean holds the result. Each theme is read once and is available
/// as [SpringThemeData]; switching themes only picks another one. The
/// design starters make their own themes of it: Material's `ThemeData`
/// (the `MaterialThemes` bean of `spring_boot_starter_flutter_material`),
/// a `CupertinoThemeData` (`CupertinoThemes` of
/// `spring_boot_starter_flutter_cupertino`). Every theme is read when the
/// application starts, so an invalid property fails the start with the
/// property's name.
///
/// The starter creates it as a bean, and `SpringApp` shows its themes.
/// Inject it to list the themes (for a theme menu) or to add themes at
/// run time, for example YAML from a server ([loadYaml]): they go over the
/// files' properties, are checked first, and the app shows them at once.
/// To choose the theme shown, use [ThemeSelection].
///
/// ```dart
/// // A seasonal theme published on the shop's server, shown right away.
/// themes.loadYaml(await http.read(Uri.parse('https://cdn/themes.yml')));
/// selection.select('winter');
/// ```
final class SpringThemes extends ChangeNotifier {
  /// The themes of [properties], whose keys are relative to
  /// `spring.flutter.theme` (`seed-color`, `themes.ocean.seed-color`).
  /// Throws a `ThemePropertyException` (or a `StateError` for a wrong
  /// `extends`) when a property is invalid.
  ///
  /// [designs] are the design libraries the themes are read with: what
  /// makes a palette from `seed-color` and reads `components.*` or
  /// `cupertino.*`. None by default, as in an app of type `widgets`.
  SpringThemes(
    Map<String, String> properties, {
    RemoteAddresses addresses = const RemoteAddresses(),
    ThemeDesigns designs = ThemeDesigns.none,
  }) : this._(properties, addresses: addresses, designs: designs);

  SpringThemes._(
    Map<String, String> properties, {
    Map<String, SpringThemeData>? read,
    this.addresses = const RemoteAddresses(),
    this.designs = ThemeDesigns.none,
  }) : _files = Map.of(properties) {
    final config = _configOf(_files);
    _use(config, read ?? _read(config));
  }

  /// The themes of the `spring.flutter.theme.*` properties of
  /// [environment], with the same options as the main constructor; how the
  /// starter creates its bean.
  ///
  /// The themes are read once per [environment]: `SpringApplicationWidget`
  /// reads them for the splash while the application starts, and the bean
  /// made later from the same environment and the same properties reuses
  /// them instead of reading them again during the splash.
  factory SpringThemes.fromEnvironment(
    ConfigurableEnvironment environment, {
    RemoteAddresses addresses = const RemoteAddresses(),
    ThemeDesigns designs = ThemeDesigns.none,
  }) {
    final properties = Binder.get(environment)
        .bind(prefix, const MapType(ClassType<String>(), ClassType<String>()))
        .orElse(const <String, String>{})
        .cast<String, String>();
    final earlier = _readFor[environment];
    final themes = SpringThemes._(
      properties,
      read:
          earlier != null &&
              mapEquals(earlier.properties, properties) &&
              _sameDesigns(earlier.designs, designs)
          ? earlier.data
          : null,
      addresses: addresses,
      designs: designs,
    );
    _readFor[environment] = (
      properties: themes._files,
      data: Map.unmodifiable(themes._data),
      designs: designs,
    );
    return themes;
  }

  // The themes read from an environment's properties, for the next
  // [SpringThemes.fromEnvironment] of the same environment.
  static final _readFor =
      Expando<
        ({
          Map<String, String> properties,
          Map<String, SpringThemeData> data,
          ThemeDesigns designs,
        })
      >('SpringThemes.fromEnvironment');

  static bool _sameDesigns(ThemeDesigns a, ThemeDesigns b) =>
      a.appType == b.appType && listEquals(a.all, b.all);

  /// The themes of [context]: its bean, else, for a context without the
  /// starter's auto-configuration (in a test), themes made once from its
  /// environment, with the designs of its `springFactories` bean when it
  /// has one.
  static SpringThemes of(ApplicationContext context) =>
      context.getBeansOfType<SpringThemes>().values.firstOrNull ??
      (_made[context] ??= switch (context.environment) {
        final ConfigurableEnvironment environment =>
          SpringThemes.fromEnvironment(
            environment,
            designs: designsOf(context),
          ),
        _ => SpringThemes(const {}),
      });

  /// The designs of [context]'s application: the [ThemeDesign]s among the
  /// factories of its starters, for its `spring.flutter.app.type`.
  static ThemeDesigns designsOf(ApplicationContext context) => ThemeDesigns.of(
    context.getBeansOfType<SpringFactories>().values.firstOrNull ??
        const SpringFactories(),
    context.environment,
  );

  static final _made = Expando<SpringThemes>('SpringThemes');

  /// The prefix of the theme properties, `spring.flutter.theme`.
  static const prefix = 'spring.flutter.theme';

  final Map<String, String> _files;
  Map<String, String> _remote = const {};
  // Themes read from a URL, by the name they were given: over the files,
  // under what `load` adds.
  final _sourced = <String, Map<String, String>>{};

  // The shared source (`spring.flutter.theme.source`, name '') goes under
  // the files, so the app's own values win; a theme's source over them.
  Map<String, String> get _fromFiles => _layered(_sourced);

  Map<String, String> _layered(Map<String, Map<String, String>> sourced) => {
    ...?sourced[''],
    ..._files,
    for (final MapEntry(:key, :value) in sourced.entries)
      if (key.isNotEmpty) ...value,
  };

  late ThemeConfig _config;
  final _data = <String, SpringThemeData>{};

  /// The theme properties as read, with the selection properties
  /// (`active`, `system-light`, `system-dark`) that [ThemeSelection]
  /// starts from.
  ThemeConfig get config => _config;

  /// The names of every theme: `light`, `dark`, then the custom ones in
  /// alphabetical order. A theme menu lists these.
  List<String> get names => _config.names;

  /// The themes the app's own files declare or choose (`themes.<name>`,
  /// `active`, `system-light`, `system-dark`), in the order of [names];
  /// not the rest of what a `source` file brings (its base themes). What
  /// the debug panel offers to try.
  List<String> get ownNames {
    final own = <String>{
      for (final key in _files.keys)
        if (key.split('.') case [final first, final name, _, ...]
            when ThemeValues.canonical(first) == 'themes')
          ThemeValues.canonical(name),
      for (final chosen in [
        _config.active,
        _config.systemLight,
        _config.systemDark,
      ])
        if (chosen != 'system') ThemeValues.canonical(chosen),
    };
    return [
      for (final name in names)
        if (own.contains(ThemeValues.canonical(name))) name,
    ];
  }

  /// The theme's name as declared, for [name] written in any case or with
  /// `-` and `_` (`Ocean-Night` gives `ocean-night`); `null` when there is
  /// no such theme.
  String? nameOf(String name) => _config.nameOf(name);

  /// Theme [name] as read from the properties, for widgets that read its
  /// values directly. Throws an `ArgumentError` for an unknown name.
  SpringThemeData data(String name) =>
      _data[_name(name)] ??= SpringThemeData.of(_config, _name(name));

  /// Adds or changes themes at run time: [properties] (relative to
  /// `spring.flutter.theme`, like `themes.winter.seed-color`) go over the
  /// files' properties. They replace what an earlier [load] added.
  ///
  /// Every theme is checked first: an invalid property throws a
  /// `ThemePropertyException` and changes nothing. Then the listeners
  /// (the app) are told, and the app shows the new values at once.
  void load(Map<String, String> properties) {
    final config = _configOf({..._fromFiles, ...properties});
    final data = _read(config); // throws before anything changes
    _remote = Map.of(properties);
    _use(config, data);
    notifyListeners();
  }

  /// Adds or changes themes from a YAML document, for example one
  /// downloaded from a server. Its keys may start with
  /// `spring.flutter.theme` (as in `application.yml`) or be relative to
  /// it. It adds to what earlier loads added; otherwise it works like
  /// [load].
  ///
  /// ```dart
  /// themes.loadYaml(await http.read(Uri.parse('https://cdn/themes.yml')));
  /// ```
  void loadYaml(String yaml) {
    final properties = <String, String>{};
    for (final source in YamlPropertySourceLoader().load('themes', yaml)) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      for (final name in source.propertyNames) {
        final key = name.replaceAllMapped(
          RegExp(r'\[(\d+)\]'),
          (m) => '.${m[1]}',
        );
        final relative = key.startsWith('$prefix.')
            ? key.substring(prefix.length + 1)
            : key;
        properties[relative] = '${source.getProperty(name)}';
      }
    }
    load({..._remote, ...properties});
  }

  /// Drops every theme property that [load] and [loadYaml] added, back to
  /// the files' themes, and tells the listeners. A [ThemeSelection] showing
  /// a theme that is gone falls back to `system`.
  void unload() {
    _remote = const {};
    _apply(_configOf(_fromFiles));
    notifyListeners();
  }

  /// Reads the addresses of the themes: the application's resolvers
  /// (`SpringApplication(addressResolvers:)`), then the built-in ones.
  final RemoteAddresses addresses;

  /// The design libraries the themes are read with.
  final ThemeDesigns designs;

  ThemeConfig _configOf(Map<String, String> properties) =>
      ThemeConfig(properties, addresses: addresses, designs: designs);

  /// Every address the themes download from: the images of every theme
  /// (backgrounds, the splash's logo, image tokens).
  Iterable<RemoteAddress> get downloads => {
    for (final name in names)
      for (final image in data(name).images) ?image.address,
  };

  /// Sets the properties of the theme read from a URL under [name]
  /// (`themes.<name>.seed-color`, keys relative to `spring.flutter.theme`),
  /// or takes them away with `null`; the starter's theme source loader
  /// calls it. They go over the files' properties and under what [load]
  /// adds, and replace what an earlier call for the same [name] set. The
  /// empty [name] is `spring.flutter.theme.source`: its values (keys
  /// without `themes.`) are shared by every theme and go under the files,
  /// so the app's own values win.
  ///
  /// Every theme is checked first: an invalid property throws a
  /// `ThemePropertyException` and changes nothing. Then the listeners (the
  /// app) are told, and the app shows the new values at once.
  void applySource(String name, Map<String, String>? properties) {
    final next = {..._sourced};
    if (properties == null) {
      next.remove(name);
    } else {
      next[name] = Map.of(properties);
    }
    final config = _configOf({..._layered(next), ..._remote});
    final data = _read(config); // throws before anything changes
    _sourced
      ..clear()
      ..addAll(next);
    _use(config, data);
    notifyListeners();
  }

  void _apply(ThemeConfig config) => _use(config, _read(config));

  void _use(ThemeConfig config, Map<String, SpringThemeData> data) {
    _config = config;
    _data
      ..clear()
      ..addAll(data);
  }

  // Every theme is read (and checked by its designs) now, once: an
  // invalid property fails here, not when a theme is first shown, and the
  // themes read are the ones used.
  static Map<String, SpringThemeData> _read(ThemeConfig config) {
    final data = {
      for (final name in config.names) name: SpringThemeData.of(config, name),
    };
    _logUnread(data.values);
    return data;
  }

  // The design properties of the themes that no starter of the
  // application reads: once per property, so an app that meant to show
  // them learns which starter it lacks.
  static void _logUnread(Iterable<SpringThemeData> themes) {
    final unread = <String, String>{
      for (final theme in themes) ...theme.unreadDesignProperties,
    };
    for (final MapEntry(key: property, value: starter) in unread.entries) {
      if (_logged.add(property)) {
        _themesLog.info(
          () =>
              'The theme property $property is not shown and not checked: '
              '$starter, which reads it, is not in the application.',
        );
      }
    }
  }

  static final _logged = <String>{};

  static const _themesLog = SpringLog(
    'spring_boot_starter_flutter.SpringThemes',
  );

  String _name(String name) =>
      _config.nameOf(name) ??
      (throw ArgumentError.value(
        name,
        'name',
        'no such theme; one of ${names.join(', ')}',
      ));
}

/// The choice of the theme the app shows: `system` or the name of a
/// theme.
///
/// With `system`, the device's light or dark mode picks the theme
/// (`system-light` or `system-dark`, by default `light` and `dark`). The
/// choice starts with `spring.flutter.theme.active` (`system` by default).
/// It is a bean of the starter and a `ChangeNotifier`: a settings page
/// calls [select], and the app follows at once.
/// The choice is kept between runs in [store] (`spring.flutter.theme.remember`,
/// `true` by default) and shown again while the splash shows.
///
/// ```dart
/// // A settings tile that switches to the dark theme.
/// class DarkModeTile extends SpringStatelessWidget<(ThemeSelection,)> {
///   const DarkModeTile({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final (selection,) = beans;
///     return ListTile(
///       title: const Text('Dark'),
///       selected: selection.active == 'dark',
///       onTap: () => selection.select('dark'),
///     );
///   }
/// }
/// ```
final class ThemeSelection extends ChangeNotifier {
  /// The choice among [themes], starting with their `active` property.
  /// Throws an `ArgumentError` when that names no theme.
  ThemeSelection(this.themes, {this.store})
    : _active = _valid(themes, themes.config.active) {
    themes.addListener(_onThemesChanged);
  }

  /// Where a choice is kept between runs when `spring.flutter.theme.remember`
  /// is on (the default); `null`: not kept.
  final ThemeChoiceStore? store;

  /// The choice of [context]: its bean, else, for a context without the
  /// starter's auto-configuration, one made once.
  static ThemeSelection of(ApplicationContext context) =>
      context.getBeansOfType<ThemeSelection>().values.firstOrNull ??
      (_made[context] ??= ThemeSelection(SpringThemes.of(context)));

  static final _made = Expando<ThemeSelection>('ThemeSelection');

  /// The themes to choose from.
  final SpringThemes themes;

  String _active;

  /// What was chosen: `system` or a theme's name.
  String get active => _active;

  /// Whether the device's light or dark mode picks the theme ([active] is
  /// `system`).
  bool get followsSystem => _active == 'system';

  /// The theme `system` shows when the device is in light mode
  /// (`spring.flutter.theme.system-light`, `light` by default).
  String get systemLight => _valid(themes, themes.config.systemLight);

  /// The theme `system` shows when the device is in dark mode
  /// (`spring.flutter.theme.system-dark`, `dark` by default).
  String get systemDark => _valid(themes, themes.config.systemDark);

  /// The name of the theme shown when the device is in the [platform]
  /// mode: the chosen theme, or the light or dark one for `system`.
  String current(Brightness platform) => followsSystem
      ? (platform == Brightness.dark ? systemDark : systemLight)
      : _active;

  /// Shows theme [name], or follows the device with `system`; the name is
  /// matched ignoring case, `-` and `_`. Throws an `ArgumentError` for an
  /// unknown name. Listeners are told only when the choice changes.
  void select(String name) {
    final valid = _valid(themes, name);
    if (valid != _active) {
      _active = valid;
      notifyListeners();
      if (themes.config.remember) {
        _keep(valid);
      }
    }
  }

  // Keeps [choice]; a store that fails (no files in a test, storage full)
  // is logged, the choice still shows.
  void _keep(String choice) {
    final store = this.store;
    if (store == null) {
      return;
    }
    unawaited(
      Future.sync(() => store.write(choice)).catchError(
        (Object error) => _log.warning(
          () => 'The theme chosen is not kept: $error',
        ),
      ),
    );
  }

  static const _log = SpringLog('spring_boot_starter_flutter.ThemeSelection');

  /// Shows [name], a choice kept from an earlier run, without keeping it
  /// again; a name that is no theme any more is ignored.
  void restore(String name) {
    if (!themes.config.remember) {
      return;
    }
    final String valid;
    try {
      valid = _valid(themes, name);
    } on ArgumentError {
      return;
    }
    if (valid != _active) {
      _active = valid;
      notifyListeners();
    }
  }

  void _onThemesChanged() {
    // A theme that went away with [SpringThemes.unload]: back to system.
    if (!followsSystem && themes.nameOf(_active) == null) {
      _active = 'system';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    themes.removeListener(_onThemesChanged);
    super.dispose();
  }

  static String _valid(SpringThemes themes, String name) {
    if (name.trim().toLowerCase() == 'system') {
      return 'system';
    }
    return themes.nameOf(name) ??
        (throw ArgumentError.value(
          name,
          'spring.flutter.theme.active',
          'system or a theme: ${themes.names.join(', ')}',
        ));
  }
}

/// Gives the theme shown to the app's own widgets, whatever the app type:
/// palette, text styles (`code` too), shapes, spacing, motion and the
/// app's own tokens.
///
/// Material widgets read Material's `Theme.of(context)`, which has no
/// place for spacing, a code style or brand tokens, and an app without a
/// design library has no `Theme` at all. `SpringTheme.of(context)` gives the whole
/// [SpringThemeData] of the theme shown instead. `SpringApp` puts one
/// above the app; you create one only to show a part of the UI in another
/// theme, such as a theme preview.
///
/// ```dart
/// // A code label spaced and colored by the theme's values.
/// final theme = SpringTheme.of(context);
/// Container(
///   padding: EdgeInsets.all(theme.space('m')),
///   color: theme.colorScheme.surfaceContainer,
///   child: Text(isbn, style: theme.textStyle('code')),
/// );
/// ```
class SpringTheme extends InheritedWidget {
  /// Gives [data] to [child] and every widget below it.
  const SpringTheme({required this.data, required super.child, super.key});

  /// The theme the widgets below see.
  final SpringThemeData data;

  /// The theme of the nearest [SpringTheme] above [context]; the widget is
  /// rebuilt when it changes. Throws a `FlutterError` when there is none
  /// (an app not built by `SpringApp`).
  static SpringThemeData of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError(
        'No SpringTheme above this widget: build the app with '
        'SpringApplicationWidget(home: ...) or SpringApp.',
      ));

  /// Like [of], but `null` when there is no [SpringTheme] above
  /// [context].
  static SpringThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpringTheme>()?.data;

  @override
  bool updateShouldNotify(SpringTheme oldWidget) =>
      !identical(data, oldWidget.data);
}
