import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_design_controls.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_theme_design.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_themes.dart';

/// The [SpringAppFactory] of type `cupertino`: a `CupertinoApp` with the
/// title, locales and theme of the configuration.
///
/// The starter declares it as a bean (`cupertinoAppFactory`), and
/// `SpringApp` builds the app widget with it when the property names its
/// type:
///
/// ```properties
/// # lib/resources/application-ios.properties
/// spring.flutter.app.type=cupertino
/// spring.flutter.app.title=Counter
/// spring.flutter.theme.cupertino.primary-color=#0057B8
/// ```
///
/// The theme shown is the `CupertinoThemeData` of the theme picked
/// ([CupertinoThemes]). Above its pages the app has a [DesignScope], so
/// the Flutter starter's own widgets select text with iOS's handles and
/// draw their forms with Cupertino's controls.
final class CupertinoAppFactory implements SpringAppFactory {
  /// The factory.
  const CupertinoAppFactory();

  /// `cupertino`.
  static const typeName = CupertinoThemeDesign.typeName;

  @override
  String get type => typeName;

  /// Cupertino's texts in every language, and the widgets' own.
  @override
  List<LocalizationsDelegate<Object?>> get localizationsDelegates =>
      GlobalCupertinoLocalizations.delegates;

  @override
  Widget build(BuildContext context, SpringAppRequest app) {
    final settings = app.settings;
    final shown = app.shown;
    final theme = CupertinoThemes.of(SpringScope.of(context)).cupertino(shown);
    Widget builder(BuildContext context, Widget? child) => DesignScope(
      textStyle: _textStyle,
      selectable: _selectable,
      controls: const CupertinoDesignControls(),
      child: app.builder(context, child),
    );
    if (app.router case final router?) {
      return CupertinoApp.router(
        routerConfig: router,
        title: settings.title,
        debugShowCheckedModeBanner: settings.debugShowCheckedModeBanner,
        theme: theme,
        color: shown.appColor,
        locale: settings.locale,
        supportedLocales: settings.supportedLocales,
        localizationsDelegates: settings.localizationsDelegates,
        builder: builder,
        scrollBehavior: settings.scrollBehavior,
        shortcuts: settings.shortcuts,
      );
    }
    return CupertinoApp(
      title: settings.title,
      debugShowCheckedModeBanner: settings.debugShowCheckedModeBanner,
      theme: theme,
      color: shown.appColor,
      locale: settings.locale,
      supportedLocales: settings.supportedLocales,
      localizationsDelegates: settings.localizationsDelegates,
      navigatorObservers: settings.navigatorObservers,
      builder: builder,
      scrollBehavior: settings.scrollBehavior,
      shortcuts: settings.shortcuts,
      home: app.home,
    );
  }

  // The starter's widgets take their text styles from the `SpringTheme`
  // in a Cupertino app.
  static TextStyle? _textStyle(BuildContext context, String style) => null;

  // iOS's handles on Apple's platforms, the starter's own elsewhere; no
  // menu: the platform's shortcuts copy.
  static Widget _selectable(BuildContext context, Widget child) =>
      SelectableRegion(
        selectionControls: switch (defaultTargetPlatform) {
          TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
          TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
          TargetPlatform.android ||
          TargetPlatform.fuchsia ||
          TargetPlatform.linux ||
          TargetPlatform.windows => SpringTextSelectionControls.instance,
        },
        child: child,
      );
}
