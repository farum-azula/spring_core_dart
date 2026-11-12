import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/bound_properties.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background_widget.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_fonts.dart';
import 'package:spring_boot_starter_flutter/src/theme/wheel_scroll.dart';

/// Builds the app widget of one `spring.flutter.app.type`: a `WidgetsApp`
/// (this starter's own, type `widgets`), a `MaterialApp`
/// (`spring_boot_starter_flutter_material`, type `material`), a
/// `CupertinoApp` (`spring_boot_starter_flutter_cupertino`, type
/// `cupertino`).
///
/// [SpringApp] finds the bean whose [type] the property names, so this
/// starter needs no design library, and a design of your own is one more
/// bean.
///
/// ```dart
/// // An app widget of the company's own design system.
/// @Component()
/// class OceanAppFactory implements SpringAppFactory {
///   @override
///   String get type => 'ocean';
///
///   @override
///   List<LocalizationsDelegate<Object?>> get localizationsDelegates =>
///       const [GlobalWidgetsLocalizations.delegate];
///
///   @override
///   Widget build(BuildContext context, SpringAppRequest app) =>
///       OceanApp(title: app.settings.title, home: app.home);
/// }
/// ```
abstract interface class SpringAppFactory {
  /// The value of `spring.flutter.app.type` this factory is for
  /// (`widgets`, `material`), compared without case.
  String get type;

  /// Flutter's own localization delegates for the app widget: the texts of
  /// its widgets in every language. They start
  /// [FlutterAppSettings.localizationsDelegates].
  List<LocalizationsDelegate<Object?>> get localizationsDelegates;

  /// The app widget for [app]: with [SpringAppRequest.home] as its first
  /// page, else on [SpringAppRequest.router].
  Widget build(BuildContext context, SpringAppRequest app);
}

/// What a [SpringAppFactory] builds its app widget from.
final class SpringAppRequest {
  /// The request of [SpringApp]; a test of a factory makes its own.
  const SpringAppRequest({
    required this.settings,
    required this.themes,
    required this.selection,
    required this.shown,
    required this.builder,
    this.home,
    this.router,
  });

  /// Title, locales, delegates, observers and the rest of
  /// `spring.flutter.app.*`.
  final FlutterAppSettings settings;

  /// Every theme of the app.
  final SpringThemes themes;

  /// Which theme is shown, and whether it follows the device.
  final ThemeSelection selection;

  /// The theme shown now.
  final SpringThemeData shown;

  /// The app widget's `builder`: the theme's background, the motion
  /// settings and the frame meter around the navigator, then the
  /// customizers' own builder. Pass it on as it is.
  final TransitionBuilder builder;

  /// The first page; `null` when the app has a router.
  final Widget? home;

  /// The application's router; `null` when the app has a [home].
  final RouterConfig<Object>? router;
}

/// The [SpringAppFactory] of type `widgets`: a `WidgetsApp`, no design
/// library. The default of `spring.flutter.app.type`.
final class WidgetsAppFactory implements SpringAppFactory {
  /// The factory.
  const WidgetsAppFactory();

  /// `widgets`.
  static const typeName = 'widgets';

  @override
  String get type => typeName;

  @override
  List<LocalizationsDelegate<Object?>> get localizationsDelegates => const [
    GlobalWidgetsLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, SpringAppRequest app) {
    final settings = app.settings;
    final shown = app.shown;
    if (app.router case final router?) {
      return WidgetsApp.router(
        routerConfig: router,
        title: settings.title,
        debugShowCheckedModeBanner: settings.debugShowCheckedModeBanner,
        color: shown.appColor,
        textStyle: shown.widgetsTextStyle,
        locale: settings.locale,
        supportedLocales: settings.supportedLocales,
        localizationsDelegates: settings.localizationsDelegates,
        builder: app.builder,
        shortcuts: settings.shortcuts,
      );
    }
    return WidgetsApp(
      title: settings.title,
      debugShowCheckedModeBanner: settings.debugShowCheckedModeBanner,
      color: shown.appColor,
      textStyle: shown.widgetsTextStyle,
      locale: settings.locale,
      supportedLocales: settings.supportedLocales,
      localizationsDelegates: settings.localizationsDelegates,
      navigatorObservers: settings.navigatorObservers,
      builder: app.builder,
      shortcuts: settings.shortcuts,
      // WidgetsApp needs a route for `home`.
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: app.home,
    );
  }
}

/// A page of the application's router, for a design library to make its
/// page route of.
final class SpringPageRequest {
  /// The page [settings] names, showing [child].
  const SpringPageRequest({
    required this.settings,
    required this.child,
    this.content,
    this.duration,
    this.curve,
  });

  /// The route's settings: the router's page (its name and arguments).
  final RouteSettings settings;

  /// What the page shows when its route is made.
  final Widget child;

  /// What the page of [settings] shows; `null` when it is always [child].
  /// A router may replace the page of a route in place, and the route then
  /// has new settings: [childOf] asks this for them.
  final Widget Function(RouteSettings settings)? content;

  /// What the route shows now, given its current [settings]: a route
  /// builds its content with this, not with [child].
  Widget childOf(RouteSettings settings) => content?.call(settings) ?? child;

  /// How long the transition takes, both ways; `null` for the route's own.
  final Duration? duration;

  /// The curve of the transition; `null` for the route's own.
  final Curve? curve;
}

/// The page routes and hero flights of a design library, for the router
/// of `spring_boot_starter_flutter_navigation`: Material's route (the
/// transition its theme has per platform), Cupertino's (the swipe back).
///
/// The router knows no design library. For a page whose transition is
/// `platform` or `cupertino` it asks these beans, in `@Order`, and shows
/// the first route it gets; a design starter has one.
abstract interface class DesignPageRoutes {
  /// The design's route for [page] with [transition] in an app of
  /// [appType] (`spring.flutter.app.type`); `null` when the route is not
  /// this design's: Material's for `platform` in an app of type
  /// `material`, Cupertino's for `cupertino` anywhere and for `platform`
  /// in an app of type `cupertino`.
  PageRoute<Object?>? pageRoute(
    PageTransitionType transition,
    String appType,
    SpringPageRequest page,
  );

  /// The controller of the hero flights of a navigator in an app of
  /// [appType]; `null` when the app is not of this design.
  HeroController? heroController(String appType);
}

/// Changes the settings of the app widget that [SpringApp] builds, for
/// what no property covers: a `builder`, keyboard shortcuts, a scroll
/// behaviour, the app's own localization delegates.
///
/// Declare a bean that implements it. Every such bean receives the
/// [FlutterAppSettings] once, before the app widget is first built, in
/// `@Order`. It is only for apps that let the starter build the app widget
/// (`SpringApplicationWidget(home: ...)`); an app with its own app widget
/// sets these on it directly.
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
    this.type = WidgetsAppFactory.typeName,
    this.title = '',
    this.debugShowCheckedModeBanner = true,
    List<Locale>? supportedLocales,
    List<LocalizationsDelegate<Object?>>? localizationsDelegates,
    List<NavigatorObserver>? navigatorObservers,
    this.locale,
  }) : supportedLocales = supportedLocales ?? [const Locale('en')],
       localizationsDelegates = localizationsDelegates ?? [],
       navigatorObservers = navigatorObservers ?? [];

  /// The locale the app shows (Flutter's `locale:`); `null` by default,
  /// the device's. The navigation starter sets the language of the first
  /// address (`/ja/...`), so what the start prepares for a language (the
  /// fonts of `spring.flutter.fonts.families`) is ready for the first
  /// frame.
  Locale? locale;

  /// The kind of app widget: the [SpringAppFactory.type] of the factory
  /// that builds it, from `spring.flutter.app.type` or, when that is not
  /// set, the one the starters decide on ([SpringAppFactories.resolve]):
  /// `material` or `cupertino` with one design starter, else `widgets`.
  String type;

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
    final factory = SpringAppFactories.of(context).resolve(properties.type);
    // A list with no tag is no list: the messages files decide.
    final tags = [
      for (final tag in properties.locales ?? const <String>[])
        if (tag.isNotEmpty) tag,
    ];
    final locales = tags.isEmpty
        ? messageLocales(context)
        : [for (final tag in tags) _locale(tag)];
    final settings = FlutterAppSettings(
      type: factory.type,
      title: properties.title ?? '',
      debugShowCheckedModeBanner: properties.debugBanner,
      supportedLocales: locales,
      localizationsDelegates: [...factory.localizationsDelegates],
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

/// The [SpringAppFactory] beans of an application, by type.
final class SpringAppFactories {
  /// The factories [all]; the first of a type wins.
  const SpringAppFactories(this.all);

  /// The factories of [context]: its [SpringAppFactory] beans in `@Order`,
  /// then this starter's own for `widgets` (which a context without the
  /// starter's auto-configuration, in a test, has no bean of).
  factory SpringAppFactories.of(ApplicationContext context) =>
      SpringAppFactories([
        ...context.getSortedBeans<SpringAppFactory>(),
        const WidgetsAppFactory(),
      ]);

  // The starter of each type of this family, for the message.
  static const _starters = {
    'material': 'spring_boot_starter_flutter_material',
    'cupertino': 'spring_boot_starter_flutter_cupertino',
  };

  /// Every factory, in order.
  final List<SpringAppFactory> all;

  /// The factory of `spring.flutter.app.type` [type], or, when it is not
  /// set, the one the application's starters decide on, as Spring Boot
  /// deduces the web application type from the class path: the factory of
  /// the one type besides `widgets` (a design starter's, or the app's
  /// own), else `widgets`. With factories of several types the choice is
  /// the application's: an `ArgumentError` naming the property and the
  /// types. Otherwise as [named].
  SpringAppFactory resolve(String? type) {
    if (type != null && type.trim().isNotEmpty) {
      return named(type);
    }
    final designed = <String, SpringAppFactory>{};
    for (final factory in all) {
      final name = factory.type.toLowerCase();
      if (name != WidgetsAppFactory.typeName) {
        designed.putIfAbsent(name, () => factory);
      }
    }
    return switch (designed.values.toList()) {
      [] => named(WidgetsAppFactory.typeName),
      [final only] => only,
      final several => throw ArgumentError(
        'not set, and the application has app widgets of several types: '
            '${[for (final factory in several) factory.type].join(', ')}. '
            'Choose one, for every platform or in a profile of each '
            '(spring.flutter.app.type=cupertino in '
            'application-ios.properties)',
        'spring.flutter.app.type',
      ),
    };
  }

  /// The factory of [type], compared without case. Throws an
  /// `ArgumentError` naming `spring.flutter.app.type` for a type no
  /// factory has, with the starter to add when it is one of this family's.
  SpringAppFactory named(String type) {
    final wanted = type.trim().toLowerCase();
    for (final factory in all) {
      if (factory.type.toLowerCase() == wanted) {
        return factory;
      }
    }
    final known = {for (final factory in all) factory.type}.join(', ');
    throw ArgumentError.value(
      type,
      'spring.flutter.app.type',
      switch (_starters[wanted]) {
        final starter? =>
          'the app widget of type $wanted is built by $starter: add it to '
              'the dependencies (this application has: $known)',
        null => 'one of: $known',
      },
    );
  }
}

/// An app widget set up by properties instead of code: a `WidgetsApp`, or
/// with a design starter a `MaterialApp` or `CupertinoApp`, with the
/// title, debug banner, locales and themes of the configuration.
///
/// It saves writing and keeping an app widget in step with the
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
    Widget content = _LanguageFonts(
      child: ThemeBackground(child: child ?? const SizedBox.shrink()),
    );
    // `motion.enabled: false`: every motion instant, as the device's
    // "reduce motion".
    if (SpringTheme.maybeOf(context)?.motionEnabled == false) {
      content = MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: content,
      );
    }
    // `motion.wheel-scroll.inertia.touch`: a flick throws the page further.
    final touch = SpringTheme.maybeOf(context)?.wheelScroll.inertia.touch ?? 0;
    if (touch > 0) {
      final behavior = ScrollConfiguration.of(context);
      content = ScrollConfiguration(
        behavior: behavior.copyWith(
          physics: InertiaScrollPhysics(
            touch,
            parent: behavior.getScrollPhysics(context),
          ),
        ),
        child: content,
      );
    }
    if (SpringTheme.maybeOf(context)?.overscroll == OverscrollEffect.none) {
      content = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: content,
      );
    }
    final meter = _frameMeter(SpringScope.of(context));
    if (meter.enabled) {
      final spring = SpringScope.of(context);
      content = FrameMeter(
        position: meter.position,
        targetRate: meter.targetRate,
        stages: spring.containsBean('splashStages')
            ? spring.getBean<SplashStages>()
            : null,
        child: content,
      );
    }
    return (app.builder ?? (_, child) => child!)(context, content);
  };

  // `spring.flutter.frame-meter.*`, read once per context.
  static FlutterFrameMeterProperties _frameMeter(ApplicationContext context) =>
      _meters[context] ??= boundProperties<FlutterFrameMeterProperties>(
        context.environment,
        'flutterFrameMeterProperties',
      );

  static final _meters = Expando<FlutterFrameMeterProperties>('frame meter');

  Widget _app(
    FlutterAppSettings app,
    SpringThemes themes,
    ThemeSelection selection,
    SpringThemeData shown,
  ) {
    final spring = SpringScope.of(context);
    final home = widget.home;
    return SpringAppFactories.of(spring)
        .named(app.type)
        .build(
          context,
          SpringAppRequest(
            settings: app,
            themes: themes,
            selection: selection,
            shown: shown,
            builder: _builder(app),
            home: home,
            router: home == null ? SpringApp.routerOf(spring) : null,
          ),
        );
  }
}

// Loads the font families declared for the language the app shows
// (`spring.flutter.fonts.families.<family>.languages`) when it changes;
// the start loaded the first language's before the first frame.
class _LanguageFonts extends StatefulWidget {
  const _LanguageFonts({required this.child});

  final Widget child;

  @override
  State<_LanguageFonts> createState() => _LanguageFontsState();
}

class _LanguageFontsState extends State<_LanguageFonts> {
  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.maybeLocaleOf(context);
    if (locale != null && locale != _locale) {
      _locale = locale;
      unawaited(ThemeFonts.loadLanguage(locale.toLanguageTag()));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
