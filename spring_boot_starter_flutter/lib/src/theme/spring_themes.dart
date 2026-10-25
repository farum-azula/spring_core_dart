import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';

/// Adjusts every Material theme made from the properties (in `@Order`),
/// like Spring Boot's `Jackson2ObjectMapperBuilderCustomizer`.
///
/// ```dart
/// @Component()
/// class RoundedChips implements ThemeCustomizer {
///   @override
///   ThemeData customize(ThemeData theme, SpringThemeData spring) => theme.copyWith(
///     chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()),
///   );
/// }
/// ```
abstract interface class ThemeCustomizer {
  /// [theme], made from [spring], adjusted.
  ThemeData customize(ThemeData theme, SpringThemeData spring);
}

/// Adjusts every Cupertino theme made from the properties (in `@Order`).
abstract interface class CupertinoThemeCustomizer {
  /// [theme], made from [spring], adjusted.
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  );
}

/// The app's themes, made from `spring.flutter.theme.*` once: the
/// standard `light` and `dark` and every theme of `themes.<name>`, each
/// as [SpringThemeData], Material `ThemeData` and `CupertinoThemeData`.
/// A bean of the starter; all themes are checked when the application
/// starts, so an invalid property fails the start.
///
/// More themes can come at run time, e.g. YAML from a server ([loadYaml]):
/// they go over the files' properties, are checked first, and the app
/// shows them at once.
final class SpringThemes extends ChangeNotifier {
  /// The themes of [properties] (relative to `spring.flutter.theme`).
  ///
  /// A `ThemeData` bean named `theme` / `darkTheme` replaces the made
  /// `light` / `dark` Material theme ([light], [dark]), a
  /// `CupertinoThemeData` bean every Cupertino theme ([cupertino]).
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

  /// The themes of [environment]'s `spring.flutter.theme.*` properties.
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

  /// The themes of [context]: its bean, else (an application without the
  /// starter's auto-configuration, e.g. in a test) made from its
  /// environment once.
  static SpringThemes of(ApplicationContext context) =>
      context.getBeansOfType<SpringThemes>().values.firstOrNull ??
      (_made[context] ??= switch (context.environment) {
        final ConfigurableEnvironment environment =>
          SpringThemes.fromEnvironment(environment),
        _ => SpringThemes(const {}),
      });

  static final _made = Expando<SpringThemes>('SpringThemes');

  /// The properties' prefix.
  static const prefix = 'spring.flutter.theme';

  final Map<String, String> _files;
  Map<String, String> _remote = const {};

  /// Adjust every Material theme.
  final List<ThemeCustomizer> customizers;

  /// Adjust every Cupertino theme.
  final List<CupertinoThemeCustomizer> cupertinoCustomizers;
  final ThemeData? _lightOverride;
  final ThemeData? _darkOverride;
  final CupertinoThemeData? _cupertinoOverride;

  late ThemeConfig _config;
  final _data = <String, SpringThemeData>{};
  final _material = <String, ThemeData>{};
  final _cupertino = <String, CupertinoThemeData>{};

  /// The selection properties (`active`, `system-light`, `system-dark`).
  ThemeConfig get config => _config;

  /// Every theme: `light`, `dark`, then the others.
  List<String> get names => _config.names;

  /// The name of the theme [name] stands for (ignoring case and `-`), or
  /// `null` when there is none.
  String? nameOf(String name) => _config.nameOf(name);

  /// Theme [name] as read from the properties.
  SpringThemeData data(String name) =>
      _data[_name(name)] ??= SpringThemeData.of(_config, _name(name));

  /// Theme [name] as Material's `ThemeData` (with the customizers).
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

  /// Theme [name] as a `CupertinoThemeData` (with the customizers).
  CupertinoThemeData cupertino(String name) => _cupertino[_name(name)] ??= () {
    final spring = data(name);
    return cupertinoCustomizers.fold(
      _cupertinoOverride ?? spring.toCupertino(),
      (theme, customizer) => customizer.customize(theme, spring),
    );
  }();

  /// Puts [properties] (relative to `spring.flutter.theme`, like
  /// `themes.winter.seed-color`) over the files' ones: new themes, changed
  /// ones. Every theme is checked first; an invalid property throws and
  /// changes nothing. Listeners (the app) are told.
  void load(Map<String, String> properties) {
    final config = ThemeConfig({..._files, ...properties});
    final data = _read(config); // throws before anything changes
    _remote = Map.of(properties);
    _use(config, data);
    notifyListeners();
  }

  /// [load]s the theme properties of a YAML document, e.g. from a server:
  /// with the `spring.flutter.theme` keys (as in `application.yml`) or
  /// relative to it.
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

  /// Drops what [load] added: the files' themes again.
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

/// Which theme the app shows: `system` (the device's light or dark mode
/// picks `system-light` / `system-dark`) or a theme by name. Starts with
/// `spring.flutter.theme.active`; [select] switches at run time, and the
/// app follows at once.
///
/// ```dart
/// @Component()
/// class ThemePicker {
///   ThemePicker(this.selection);
///   final ThemeSelection selection;
///   void dark() => selection.select('dark');
/// }
/// ```
final class ThemeSelection extends ChangeNotifier {
  /// The selection of [themes], starting with its `active` property.
  ThemeSelection(this.themes) : _active = _valid(themes, themes.config.active) {
    themes.addListener(_onThemesChanged);
  }

  /// The selection of [context]: its bean, else one made once.
  static ThemeSelection of(ApplicationContext context) =>
      context.getBeansOfType<ThemeSelection>().values.firstOrNull ??
      (_made[context] ??= ThemeSelection(SpringThemes.of(context)));

  static final _made = Expando<ThemeSelection>('ThemeSelection');

  /// The themes chosen from.
  final SpringThemes themes;

  String _active;

  /// `system` or a theme's name.
  String get active => _active;

  /// Whether the device's light or dark mode picks the theme.
  bool get followsSystem => _active == 'system';

  /// The theme `system` shows in the device's light mode.
  String get systemLight => _valid(themes, themes.config.systemLight);

  /// The theme `system` shows in the device's dark mode.
  String get systemDark => _valid(themes, themes.config.systemDark);

  /// The theme shown when the device's mode is [platform].
  String current(Brightness platform) => followsSystem
      ? (platform == Brightness.dark ? systemDark : systemLight)
      : _active;

  /// Shows theme [name] (or `system`); throws for an unknown name.
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

/// The theme shown, for the app's own widgets, whatever the app type:
/// palette, text styles (`code` too), shapes, spacing, motion and the
/// app's tokens.
///
/// ```dart
/// final theme = SpringTheme.of(context);
/// Container(
///   padding: EdgeInsets.all(theme.space('m')),
///   color: theme.colorScheme.surfaceContainer,
///   child: Text(isbn, style: theme.textStyle('code')),
/// );
/// ```
class SpringTheme extends InheritedWidget {
  /// Gives [data] to [child].
  const SpringTheme({required this.data, required super.child, super.key});

  /// The theme.
  final SpringThemeData data;

  /// The theme shown above [context].
  static SpringThemeData of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError(
        'No SpringTheme above this widget: build the app with '
        'SpringApplicationWidget(home: ...) or SpringApp.',
      ));

  /// The theme shown above [context], or `null`.
  static SpringThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpringTheme>()?.data;

  @override
  bool updateShouldNotify(SpringTheme oldWidget) =>
      !identical(data, oldWidget.data);
}
