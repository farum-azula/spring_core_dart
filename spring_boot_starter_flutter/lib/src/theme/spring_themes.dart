import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';

/// Changes, in code, every Material `ThemeData` made from the theme
/// properties: for what the properties do not cover.
///
/// The properties set colors, typography, shapes and a list of components;
/// a customizer can change anything else on the `ThemeData` (a component
/// the properties do not know, a value computed from others). Declare a
/// bean that implements it; every customizer runs, in `@Order`, on each
/// theme when it is first made, also on a `ThemeData` bean named `theme`
/// or `darkTheme` that replaces the made `light` or `dark` theme.
///
/// ```dart
/// // Stadium-shaped chips in every theme.
/// @Component()
/// class RoundedChips implements ThemeCustomizer {
///   @override
///   ThemeData customize(ThemeData theme, SpringThemeData spring) =>
///       theme.copyWith(
///         chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()),
///       );
/// }
/// ```
///
/// Spring Boot (Java) adjusts its auto-configured objects the same way,
/// for example with a `Jackson2ObjectMapperBuilderCustomizer` bean.
abstract interface class ThemeCustomizer {
  /// Returns [theme] changed, usually with `copyWith`. [theme] was made
  /// from [spring], whose name, palette and tokens the change may depend
  /// on.
  ThemeData customize(ThemeData theme, SpringThemeData spring);
}

/// Changes, in code, every `CupertinoThemeData` made from the theme
/// properties, for apps of type `cupertino`.
///
/// The Cupertino counterpart of [ThemeCustomizer]: declare a bean that
/// implements it; every customizer runs, in `@Order`, on each Cupertino
/// theme when it is first made (also on a replacing `CupertinoThemeData`
/// bean).
///
/// ```dart
/// // Bar backgrounds follow the theme's surface color.
/// @Component()
/// class SurfaceBars implements CupertinoThemeCustomizer {
///   @override
///   CupertinoThemeData customize(
///     CupertinoThemeData theme,
///     SpringThemeData spring,
///   ) => theme.copyWith(barBackgroundColor: spring.colorScheme.surface);
/// }
/// ```
abstract interface class CupertinoThemeCustomizer {
  /// Returns [theme] changed, usually with `copyWith`. [theme] was made
  /// from [spring].
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  );
}

/// All the themes of the app, read from the `spring.flutter.theme.*`
/// properties: the standard `light` and `dark`, and every custom theme of
/// `themes.<name>`.
///
/// The look of the app is configuration rather than `ThemeData` code, and
/// this bean holds the result. Each theme is read once and is available
/// as [SpringThemeData], as Material `ThemeData` ([material]) and as
/// `CupertinoThemeData` ([cupertino]); switching themes only picks another
/// one. Every theme is read when the application starts, so an invalid
/// property fails the start with the property's name.
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
  /// [light] and [dark] replace the made `light` and `dark` Material themes,
  /// and [cupertino] every Cupertino theme; the starter passes a
  /// `ThemeData` bean named `theme` / `darkTheme` and a
  /// `CupertinoThemeData` bean here. [customizers] and
  /// [cupertinoCustomizers] then change every theme, replaced ones too.
  SpringThemes(
    Map<String, String> properties, {
    this.customizers = const [],
    this.cupertinoCustomizers = const [],
    ThemeData? light,
    ThemeData? dark,
    CupertinoThemeData? cupertino,
  }) : _files = Map.of(properties),
       _lightOverride = light,
       _darkOverride = dark,
       _cupertinoOverride = cupertino {
    _apply(ThemeConfig(_files));
  }

  /// The themes of the `spring.flutter.theme.*` properties of
  /// [environment], with the same options as the main constructor; how the
  /// starter creates its bean.
  factory SpringThemes.fromEnvironment(
    ConfigurableEnvironment environment, {
    List<ThemeCustomizer> customizers = const [],
    List<CupertinoThemeCustomizer> cupertinoCustomizers = const [],
    ThemeData? light,
    ThemeData? dark,
    CupertinoThemeData? cupertino,
  }) => SpringThemes(
    Binder.get(environment)
        .bind(prefix, const MapType(ClassType<String>(), ClassType<String>()))
        .orElse(const <String, String>{})
        .cast<String, String>(),
    customizers: customizers,
    cupertinoCustomizers: cupertinoCustomizers,
    light: light,
    dark: dark,
    cupertino: cupertino,
  );

  /// The themes of [context]: its bean, else, for a context without the
  /// starter's auto-configuration (in a test), themes made once from its
  /// environment.
  static SpringThemes of(ApplicationContext context) =>
      context.getBeansOfType<SpringThemes>().values.firstOrNull ??
      (_made[context] ??= switch (context.environment) {
        final ConfigurableEnvironment environment =>
          SpringThemes.fromEnvironment(environment),
        _ => SpringThemes(const {}),
      });

  static final _made = Expando<SpringThemes>('SpringThemes');

  /// The prefix of the theme properties, `spring.flutter.theme`.
  static const prefix = 'spring.flutter.theme';

  final Map<String, String> _files;
  Map<String, String> _remote = const {};

  /// The customizers applied to every Material theme, in order.
  final List<ThemeCustomizer> customizers;

  /// The customizers applied to every Cupertino theme, in order.
  final List<CupertinoThemeCustomizer> cupertinoCustomizers;
  final ThemeData? _lightOverride;
  final ThemeData? _darkOverride;
  final CupertinoThemeData? _cupertinoOverride;

  late ThemeConfig _config;
  final _data = <String, SpringThemeData>{};
  final _material = <String, ThemeData>{};
  final _cupertino = <String, CupertinoThemeData>{};

  /// The theme properties as read, with the selection properties
  /// (`active`, `system-light`, `system-dark`) that [ThemeSelection]
  /// starts from.
  ThemeConfig get config => _config;

  /// The names of every theme: `light`, `dark`, then the custom ones in
  /// alphabetical order. A theme menu lists these.
  List<String> get names => _config.names;

  /// The theme's name as declared, for [name] written in any case or with
  /// `-` and `_` (`Ocean-Night` gives `ocean-night`); `null` when there is
  /// no such theme.
  String? nameOf(String name) => _config.nameOf(name);

  /// Theme [name] as read from the properties, for widgets that read its
  /// values directly. Throws an `ArgumentError` for an unknown name.
  SpringThemeData data(String name) =>
      _data[_name(name)] ??= SpringThemeData.of(_config, _name(name));

  /// Theme [name] as Material's `ThemeData`: the one made from the
  /// properties (or the replacing one, for `light` and `dark`), then
  /// changed by the customizers; made once. Throws an `ArgumentError` for
  /// an unknown name.
  ThemeData material(String name) => _material[_name(name)] ??= () {
    final spring = data(name);
    final override = switch (spring.name) {
      'light' => _lightOverride,
      'dark' => _darkOverride,
      _ => null,
    };
    return customizers.fold(
      override ?? spring.toMaterial(),
      (theme, customizer) => customizer.customize(theme, spring),
    );
  }();

  /// Theme [name] as a `CupertinoThemeData`: the one made from the
  /// properties (or the replacing one), then changed by the customizers;
  /// made once. Throws an `ArgumentError` for an unknown name.
  CupertinoThemeData cupertino(String name) => _cupertino[_name(name)] ??= () {
    final spring = data(name);
    return cupertinoCustomizers.fold(
      _cupertinoOverride ?? spring.toCupertino(),
      (theme, customizer) => customizer.customize(theme, spring),
    );
  }();

  /// Adds or changes themes at run time: [properties] (relative to
  /// `spring.flutter.theme`, like `themes.winter.seed-color`) go over the
  /// files' properties. They replace what an earlier [load] added.
  ///
  /// Every theme is checked first: an invalid property throws a
  /// `ThemePropertyException` and changes nothing. Then the listeners
  /// (the app) are told, and the app shows the new values at once.
  void load(Map<String, String> properties) {
    final config = ThemeConfig({..._files, ...properties});
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
    _apply(ThemeConfig(_files));
    notifyListeners();
  }

  void _apply(ThemeConfig config) => _use(config, _read(config));

  void _use(ThemeConfig config, Map<String, SpringThemeData> data) {
    _config = config;
    _data
      ..clear()
      ..addAll(data);
    _material.clear();
    _cupertino.clear();
  }

  // Every theme is read (and made into a Material theme) now, once: an
  // invalid property fails here, not when a theme is first shown, and the
  // themes read are the ones used.
  static Map<String, SpringThemeData> _read(ThemeConfig config) => {
    for (final name in config.names) name: SpringThemeData.of(config, name),
  };

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
/// The choice is not stored; an app that wants to remember it saves
/// [active] itself.
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
  ThemeSelection(this.themes) : _active = _valid(themes, themes.config.active) {
    themes.addListener(_onThemesChanged);
  }

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
/// place for spacing, a code style or brand tokens, and a `WidgetsApp` has
/// no `Theme` at all. `SpringTheme.of(context)` gives the whole
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
