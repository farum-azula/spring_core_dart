import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/bound_properties.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background_widget.dart';
import 'package:spring_boot_starter_flutter/src/theme/wheel_scroll.dart';

/// The kind of app widget [SpringApp] builds, chosen with
/// `spring.flutter.app.type` (`widgets`, `material` or `cupertino`).
enum AppType {
  /// A `WidgetsApp`, with no Material or Cupertino design; the default.
  widgets,

  /// A `MaterialApp`, needed by `Scaffold`, `AppBar` and the other
  /// Material widgets.
  material,

  /// A `CupertinoApp`, for the iOS look (for example with
  /// `spring.flutter.app.type=cupertino` in `application-ios.properties`).
  cupertino,
}

/// Changes the settings of the app widget that [SpringApp] builds, for
/// what no property covers: a `builder`, keyboard shortcuts, a scroll
/// behaviour, the app's own localization delegates.
///
/// Declare a bean that implements it. Every such bean receives the
/// [FlutterAppSettings] once, before the app widget is first built, in
/// `@Order`. It is only for apps that let the starter build the app widget
/// (`SpringApplicationWidget(home: ...)`); an app with its own
/// `MaterialApp` sets these on it directly.
///
/// ```dart
/// // The app's own translations, and text that never grows past 130 %.
/// @Component()
/// class AppLocalizations implements FlutterAppCustomizer {
///   @override
///   void customize(FlutterAppSettings app) {
///     app.localizationsDelegates.add(LegalTerms.delegate);
///     app.builder = (context, child) => MediaQuery.withClampedTextScaling(
///       maxScaleFactor: 1.3,
///       child: child!,
///     );
///   }
/// }
/// ```
///
/// Spring Boot (Java) customizes its web server the same way, with a
/// `WebServerFactoryCustomizer` bean.
abstract interface class FlutterAppCustomizer {
  /// Changes [app] in place; called once per application context, before
  /// the app widget is built.
  void customize(FlutterAppSettings app);
}

/// The settings [SpringApp] builds the app widget from: type, title,
/// debug banner, locales, localization delegates, navigator observers,
/// and a few more.
///
/// They are made once per application context from the
/// `spring.flutter.app.*` properties and the `NavigatorObserver` beans,
/// then every [FlutterAppCustomizer] may change them. You meet the object
/// in a customizer, where you change its fields. The theme is not here: it
/// comes from [SpringThemes].
final class FlutterAppSettings {
  /// Settings for an app of [type] (`widgets` by default); every other
  /// value has Flutter's default, the locales default to English only.
  FlutterAppSettings({
    this.type = AppType.widgets,
    this.title = '',
    this.debugShowCheckedModeBanner = true,
    List<Locale>? supportedLocales,
    List<LocalizationsDelegate<Object?>>? localizationsDelegates,
    List<NavigatorObserver>? navigatorObservers,
  }) : supportedLocales = supportedLocales ?? [const Locale('en')],
       localizationsDelegates = localizationsDelegates ?? [],
       navigatorObservers = navigatorObservers ?? [];

  /// The kind of app widget, from `spring.flutter.app.type`; `widgets` by
  /// default.
  AppType type;

  /// The app's name for the OS (task switcher, browser tab), from
  /// `spring.flutter.app.title`; empty by default.
  String title;

  /// Whether debug builds show the "DEBUG" banner, from
  /// `spring.flutter.app.debug-banner`; `true` by default, as in Flutter.
  bool debugShowCheckedModeBanner;

  /// The locales the app supports, from `spring.flutter.app.locales`
  /// (`en,ja`). By default the languages of the messages files
  /// ([messageLocales]), so the app's locales and `context.message` agree.
  List<Locale> supportedLocales;

  /// The localization delegates. They start with Flutter's own for the app
  /// type (the texts of its widgets in every language); a customizer adds
  /// the app's own here.
  List<LocalizationsDelegate<Object?>> localizationsDelegates;

  /// The app's navigator observers: the `NavigatorObserver` beans, in
  /// `@Order`.
  List<NavigatorObserver> navigatorObservers;

  /// Wraps the navigator, so what it adds sits above every page, like
  /// `MaterialApp.builder`; `null` by default.
  TransitionBuilder? builder;

  /// The app's scroll behavior; `null` for the app widget's default. Not
  /// used by a `WidgetsApp`.
  ScrollBehavior? scrollBehavior;

  /// The app's keyboard shortcuts; `null` for Flutter's defaults.
  Map<ShortcutActivator, Intent>? shortcuts;

  /// The settings of [context]'s application, made on the first call and
  /// kept for the life of the context. Throws an `ArgumentError` naming the
  /// property when a `spring.flutter.app.*` value is invalid;
  /// `SpringApplicationWidget` calls it at the start, so such a value fails
  /// the start.
  static FlutterAppSettings of(ApplicationContext context) =>
      _cache[context] ??= _settings(context);

  static final _cache = Expando<FlutterAppSettings>('FlutterAppSettings');

  static FlutterAppSettings _settings(ApplicationContext context) {
    final properties = boundProperties<FlutterAppProperties>(
      context.environment,
      'flutterAppProperties',
    );
    final type = properties.type;
    // A list with no tag is no list: the messages files decide.
    final tags = [
      for (final tag in properties.locales ?? const <String>[])
        if (tag.isNotEmpty) tag,
    ];
    final locales = tags.isEmpty
        ? messageLocales(context)
        : [for (final tag in tags) _locale(tag)];
    final settings = FlutterAppSettings(
      type: type,
      title: properties.title ?? '',
      debugShowCheckedModeBanner: properties.debugBanner,
      supportedLocales: locales,
      localizationsDelegates: switch (type) {
        AppType.material => [...GlobalMaterialLocalizations.delegates],
        AppType.cupertino => [...GlobalCupertinoLocalizations.delegates],
        AppType.widgets => [GlobalWidgetsLocalizations.delegate],
      },
      navigatorObservers: context.getSortedBeans<NavigatorObserver>(),
    );
    for (final customizer in context.getSortedBeans<FlutterAppCustomizer>()) {
      customizer.customize(settings);
    }
    return settings;
  }

  /// The locales of the application's messages files: English for the
  /// file without a language (`messages.properties`), then one locale per
  /// `messages_<locale>.properties` file (`messages_ja` adds `ja`). The
  /// files are those of `spring.messages.basename`, `messages` by default.
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
        'resources:$directory${name}_*.properties',
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
    final language = parts.first;
    if (parts.length == 1) {
      return Locale(language);
    }
    if (parts.length >= 3) {
      return Locale.fromSubtags(
        languageCode: language,
        scriptCode: parts[1],
        countryCode: parts[2],
      );
    }
    return parts[1].length == 4
        ? Locale.fromSubtags(languageCode: language, scriptCode: parts[1])
        : Locale(language, parts[1]);
  }
}

/// An app widget set up by properties instead of code: a `WidgetsApp`,
/// `MaterialApp` or `CupertinoApp` with the title, debug banner, locales
/// and themes of the configuration.
///
/// It saves writing and keeping a `MaterialApp` in step with the
/// configuration: the type comes from `spring.flutter.app.type`, the other
/// settings from `spring.flutter.app.*` ([FlutterAppSettings]), the theme
/// from `spring.flutter.theme.*`. The theme shown is the one the
/// `ThemeSelection` bean picks; a theme picked at run time, or loaded from
/// a server, shows at once, and `system` follows the device's light or
/// dark mode. A [SpringTheme] above the app gives that theme to the app's
/// own widgets.
///
/// `SpringApplicationWidget(home: ...)` puts it at the root, so an app
/// rarely creates it; widget tests put it under a `SpringScope`.
///
/// ```properties
/// # lib/resources/application.properties
/// spring.flutter.app.type=material
/// spring.flutter.app.title=Counter
/// spring.flutter.theme.seed-color=deepPurple
/// ```
class SpringApp extends StatefulWidget {
  /// The app widget with [home] as its first page, or, without one, with
  /// the application's router: the `RouterConfig<Object>` bean the
  /// navigation starter (`spring_boot_starter_flutter_navigation`) adds, or
  /// one of the app's own.
  const SpringApp({this.home, super.key});

  /// The first page, shown at the app's start; `null` to use the router.
  final Widget? home;

  /// The router of [context]'s application: its `RouterConfig<Object>`
  /// bean. Throws a `FlutterError` when there is none, saying what to add.
  static RouterConfig<Object> routerOf(ApplicationContext context) {
    final names = context.getBeanNamesForType(RouterConfig<Object>);
    if (names.isEmpty) {
      throw FlutterError.fromParts([
        ErrorSummary('SpringApp has no home and the application no router.'),
        ErrorHint(
          'Pass a home (SpringApplicationWidget(home: ...)), or add '
          'spring_boot_starter_flutter_navigation, whose screens '
          '(@ScreenRoute) make the router, or declare a '
          'RouterConfig<Object> bean.',
        ),
      ]);
    }
    return context.getBean<RouterConfig<Object>>();
  }

  @override
  State<SpringApp> createState() => _SpringAppState();
}

class _SpringAppState extends State<SpringApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // `system`: the device switched between light and dark mode.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final spring = SpringScope.of(context);
    final app = FlutterAppSettings.of(spring);
    final themes = SpringThemes.of(spring);
    final selection = ThemeSelection.of(spring);
    return ListenableBuilder(
      listenable: Listenable.merge([themes, selection]),
      builder: (context, _) {
        final platform =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final shown = themes.data(selection.current(platform));
        WheelScrollSmoother.instance.spec = shown.wheelScroll;
        return SpringTheme(
          data: shown,
          child: _app(app, themes, selection, shown),
        );
      },
    );
  }

  // The theme's background goes around the navigator, inside the app's own
  // builder.
  // `motion.overscroll: none` turns the stretch or glow at a
  // scrollable's end off for the whole app.
  TransitionBuilder _builder(FlutterAppSettings app) => (context, child) {
    Widget content = ThemeBackground(child: child ?? const SizedBox.shrink());
    if (SpringTheme.maybeOf(context)?.overscroll == OverscrollEffect.none) {
      content = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: content,
      );
    }
    return (app.builder ?? (_, child) => child!)(context, content);
  };

  Widget _app(
    FlutterAppSettings app,
    SpringThemes themes,
    ThemeSelection selection,
    SpringThemeData shown,
  ) {
    final home = widget.home;
    if (home == null) {
      return _routerApp(app, themes, selection, shown);
    }
    return switch (app.type) {
      AppType.material => MaterialApp(
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        // `system`: Material switches between the two with the device.
        theme: themes.material(
          selection.followsSystem ? selection.systemLight : shown.name,
        ),
        darkTheme: selection.followsSystem
            ? themes.material(selection.systemDark)
            : null,
        themeMode: selection.followsSystem ? ThemeMode.system : ThemeMode.light,
        color: shown.appColor,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        navigatorObservers: app.navigatorObservers,
        builder: _builder(app),
        scrollBehavior: app.scrollBehavior,
        shortcuts: app.shortcuts,
        home: home,
      ),
      AppType.cupertino => CupertinoApp(
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        theme: themes.cupertino(shown.name),
        color: shown.appColor,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        navigatorObservers: app.navigatorObservers,
        builder: _builder(app),
        scrollBehavior: app.scrollBehavior,
        shortcuts: app.shortcuts,
        home: home,
      ),
      AppType.widgets => WidgetsApp(
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        color: shown.appColor,
        textStyle: shown.widgetsTextStyle,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        navigatorObservers: app.navigatorObservers,
        builder: _builder(app),
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

  // The app widget on the router bean, the same settings as with a home.
  Widget _routerApp(
    FlutterAppSettings app,
    SpringThemes themes,
    ThemeSelection selection,
    SpringThemeData shown,
  ) {
    final router = SpringApp.routerOf(SpringScope.of(context));
    return switch (app.type) {
      AppType.material => MaterialApp.router(
        routerConfig: router,
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        theme: themes.material(
          selection.followsSystem ? selection.systemLight : shown.name,
        ),
        darkTheme: selection.followsSystem
            ? themes.material(selection.systemDark)
            : null,
        themeMode: selection.followsSystem ? ThemeMode.system : ThemeMode.light,
        color: shown.appColor,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        builder: _builder(app),
        scrollBehavior: app.scrollBehavior,
        shortcuts: app.shortcuts,
      ),
      AppType.cupertino => CupertinoApp.router(
        routerConfig: router,
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        theme: themes.cupertino(shown.name),
        color: shown.appColor,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        builder: _builder(app),
        scrollBehavior: app.scrollBehavior,
        shortcuts: app.shortcuts,
      ),
      AppType.widgets => WidgetsApp.router(
        routerConfig: router,
        title: app.title,
        debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
        color: shown.appColor,
        textStyle: shown.widgetsTextStyle,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        builder: _builder(app),
        shortcuts: app.shortcuts,
      ),
    };
  }
}
