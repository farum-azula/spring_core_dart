import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';

/// Which app widget [SpringApp] builds (`spring.flutter.app.type`).
enum AppType {
  /// `WidgetsApp`: no Material or Cupertino design (the default).
  widgets,

  /// `MaterialApp`; needed by `Scaffold`, `AppBar` and other Material
  /// widgets.
  material,

  /// `CupertinoApp`.
  cupertino,
}

/// Adjusts the app widget [SpringApp] builds, for what has no property:
/// a bean of this type gets the [FlutterAppSettings] before the widget is
/// built (in `@Order`), like Spring Boot's `WebServerFactoryCustomizer`.
///
/// ```dart
/// @Component()
/// class AppLocalizations implements FlutterAppCustomizer {
///   @override
///   void customize(FlutterAppSettings app) {
///     app.localizationsDelegates.add(LegalTerms.delegate);
///     app.builder = (context, child) =>
///         MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!);
///   }
/// }
/// ```
abstract interface class FlutterAppCustomizer {
  /// Changes [app] before the app widget is built.
  void customize(FlutterAppSettings app);
}

/// What [SpringApp] builds the app widget from: the
/// `spring.flutter.app.*` properties, the theme beans and the
/// `NavigatorObserver` beans, then whatever [FlutterAppCustomizer]s
/// change. Made once per application context.
final class FlutterAppSettings {
  /// Settings for an app of [type]; the rest has Flutter's defaults.
  FlutterAppSettings({
    this.type = AppType.widgets,
    this.title = '',
    this.debugShowCheckedModeBanner = true,
    this.themeMode = ThemeMode.system,
    this.color = const Color(0xFF6750A4),
    List<Locale>? supportedLocales,
    List<LocalizationsDelegate<Object?>>? localizationsDelegates,
    List<NavigatorObserver>? navigatorObservers,
    this.theme,
    this.darkTheme,
    this.cupertinoTheme,
  }) : supportedLocales = supportedLocales ?? [const Locale('en')],
       localizationsDelegates = localizationsDelegates ?? [],
       navigatorObservers = navigatorObservers ?? [];

  /// `spring.flutter.app.type`.
  AppType type;

  /// `spring.flutter.app.title`: the app's name for the OS (task switcher,
  /// browser tab).
  String title;

  /// `spring.flutter.app.debug-banner`.
  bool debugShowCheckedModeBanner;

  /// `spring.flutter.app.theme-mode` (Material): `system`, `light`, `dark`.
  ThemeMode themeMode;

  /// The app's color for the OS (`WidgetsApp.color`); the theme's primary
  /// color when there is a `ThemeData` bean.
  Color color;

  /// `spring.flutter.app.locales`, by default the languages of the messages
  /// files (`messages.properties` counts as English, `messages_ja` adds
  /// `ja`).
  List<Locale> supportedLocales;

  /// Flutter's own delegates for the app type (texts of its widgets in
  /// every supported language); add the app's own here.
  List<LocalizationsDelegate<Object?>> localizationsDelegates;

  /// The `NavigatorObserver` beans.
  List<NavigatorObserver> navigatorObservers;

  /// The `ThemeData` bean `theme` (or the only one not named `darkTheme`).
  ThemeData? theme;

  /// The `ThemeData` bean `darkTheme`.
  ThemeData? darkTheme;

  /// The `CupertinoThemeData` bean.
  CupertinoThemeData? cupertinoTheme;

  /// Wraps every route (`MaterialApp.builder`).
  TransitionBuilder? builder;

  /// The app's scroll behavior.
  ScrollBehavior? scrollBehavior;

  /// The app's keyboard shortcuts.
  Map<ShortcutActivator, Intent>? shortcuts;

  /// The settings of [context]'s application: made once per context from
  /// its properties and beans. Throws when a property has an invalid value
  /// (`SpringApplicationWidget` checks it at the start).
  static FlutterAppSettings of(ApplicationContext context) =>
      _cache[context] ??= _settings(context);

  static final _cache = Expando<FlutterAppSettings>('FlutterAppSettings');

  static FlutterAppSettings _settings(ApplicationContext context) {
    final environment = context.environment;
    String? property(String key) {
      final value = environment.getProperty('spring.flutter.app.$key')?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final type =
        _enum(AppType.values, 'type', property('type')) ?? AppType.widgets;
    final themes = context.getBeansOfType<ThemeData>();
    final theme =
        themes['theme'] ??
        [
          for (final MapEntry(:key, :value) in themes.entries)
            if (key != 'darkTheme') value,
        ].singleOrNull;
    final locales = switch (property('locales')) {
      final list? => [
        for (final tag in list.split(','))
          if (tag.trim().isNotEmpty) _locale(tag.trim()),
      ],
      null => messageLocales(context),
    };
    final settings = FlutterAppSettings(
      type: type,
      title: property('title') ?? '',
      debugShowCheckedModeBanner:
          _bool('debug-banner', property('debug-banner')) ?? true,
      themeMode:
          _enum(ThemeMode.values, 'theme-mode', property('theme-mode')) ??
          ThemeMode.system,
      color: theme?.colorScheme.primary ?? const Color(0xFF6750A4),
      supportedLocales: locales,
      localizationsDelegates: switch (type) {
        AppType.material => [...GlobalMaterialLocalizations.delegates],
        AppType.cupertino => [...GlobalCupertinoLocalizations.delegates],
        AppType.widgets => [GlobalWidgetsLocalizations.delegate],
      },
      navigatorObservers: context.getSortedBeans<NavigatorObserver>(),
      theme: theme,
      darkTheme: themes['darkTheme'],
      cupertinoTheme: context
          .getBeansOfType<CupertinoThemeData>()
          .values
          .singleOrNull,
    );
    for (final customizer in context.getSortedBeans<FlutterAppCustomizer>()) {
      customizer.customize(settings);
    }
    return settings;
  }

  /// The languages of the application's messages files
  /// (`spring.messages.basename`, `messages` by default): English for the
  /// file without a language, then one locale per `messages_<locale>` file.
  static List<Locale> messageLocales(ApplicationContext context) {
    final basenames =
        context.environment.getProperty('spring.messages.basename') ??
        'messages';
    final locales = <Locale>{const Locale('en')};
    for (final basename in basenames.split(',')) {
      final name = basename.trim().split('/').last;
      final directory = basename.trim().contains('/')
          ? basename.trim().substring(0, basename.trim().lastIndexOf('/') + 1)
          : '';
      for (final resource in context.getResources(
        'classpath:$directory${name}_*.properties',
      )) {
        final file = resource.filename ?? '';
        final tag = file.substring(
          '${name}_'.length,
          file.length - '.properties'.length,
        );
        if (tag.isNotEmpty) {
          locales.add(_locale(tag));
        }
      }
    }
    return locales.toList();
  }

  // `en`, `pt_BR`, `pt-BR`, `zh_Hant_TW`.
  static Locale _locale(String tag) {
    final parts = tag.split(RegExp('[_-]'));
    return switch (parts) {
      [final language] => Locale(language),
      [final language, final script, final country] => Locale.fromSubtags(
        languageCode: language,
        scriptCode: script,
        countryCode: country,
      ),
      [final language, final second, ...] when second.length == 4 =>
        Locale.fromSubtags(languageCode: language, scriptCode: second),
      [final language, final country, ...] => Locale(language, country),
      _ => Locale(tag),
    };
  }

  static T? _enum<T extends Enum>(List<T> values, String key, String? value) {
    if (value == null) {
      return null;
    }
    for (final candidate in values) {
      if (candidate.name.toLowerCase() == value.toLowerCase()) {
        return candidate;
      }
    }
    throw ArgumentError.value(
      value,
      'spring.flutter.app.$key',
      'one of ${values.map((v) => v.name).join(', ')}',
    );
  }

  static bool? _bool(String key, String? value) =>
      switch (value?.toLowerCase()) {
        null => null,
        'true' => true,
        'false' => false,
        _ => throw ArgumentError.value(
          value,
          'spring.flutter.app.$key',
          'true or false',
        ),
      };
}

/// The app widget built from the application's configuration: a
/// `WidgetsApp`, `MaterialApp` or `CupertinoApp` (`spring.flutter.app.type`)
/// with the title, debug banner, theme mode and locales of
/// `spring.flutter.app.*`, the `ThemeData` / `CupertinoThemeData` beans,
/// the `NavigatorObserver` beans and the [FlutterAppCustomizer]s' changes
/// (see [FlutterAppSettings]). `SpringApplicationWidget(home: ...)` puts it
/// at the root; tests may put it under a `SpringScope`.
///
/// ```properties
/// spring.flutter.app.type=material
/// spring.flutter.app.title=Counter
/// spring.flutter.app.debug-banner=false
/// ```
class SpringApp extends StatelessWidget {
  /// The app with [home] as its first page.
  const SpringApp({required this.home, super.key});

  /// The first page.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final app = FlutterAppSettings.of(SpringScope.of(context));
    return switch (app.type) {
      AppType.material => MaterialApp(
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        theme: app.theme,
        darkTheme: app.darkTheme,
        themeMode: app.themeMode,
        color: app.color,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        navigatorObservers: app.navigatorObservers,
        builder: app.builder,
        scrollBehavior: app.scrollBehavior,
        shortcuts: app.shortcuts,
        home: home,
      ),
      AppType.cupertino => CupertinoApp(
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        theme: app.cupertinoTheme,
        color: app.color,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        navigatorObservers: app.navigatorObservers,
        builder: app.builder,
        scrollBehavior: app.scrollBehavior,
        shortcuts: app.shortcuts,
        home: home,
      ),
      AppType.widgets => WidgetsApp(
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        color: app.color,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        navigatorObservers: app.navigatorObservers,
        builder: app.builder,
        shortcuts: app.shortcuts,
        // WidgetsApp needs a route for `home`.
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: home,
      ),
    };
  }
}
