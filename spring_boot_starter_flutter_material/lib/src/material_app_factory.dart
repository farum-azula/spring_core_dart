import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_material/src/material_design_controls.dart';
import 'package:spring_boot_starter_flutter_material/src/material_text_theme.dart';
import 'package:spring_boot_starter_flutter_material/src/material_theme_design.dart';
import 'package:spring_boot_starter_flutter_material/src/material_themes.dart';

/// The [SpringAppFactory] of type `material`: a `MaterialApp` with the
/// title, locales and themes of the configuration, which `Scaffold`,
/// `AppBar` and the other Material widgets need.
///
/// ```properties
/// # lib/resources/application.properties
/// spring.flutter.app.type=material
/// spring.flutter.theme.seed-color=deepPurple
/// ```
///
/// Its themes are those of the `MaterialThemes` bean. With
/// `spring.flutter.theme.active: system` Material itself switches between
/// the light and the dark theme with the device. The starter's own widgets
/// below it (`MarkdownView`) read Material's `Theme` and select text with
/// Material's `SelectionArea`, through a [DesignScope].
final class MaterialAppFactory implements SpringAppFactory {
  /// The factory.
  const MaterialAppFactory();

  /// `material`.
  static const typeName = MaterialThemeDesign.typeName;

  @override
  String get type => typeName;

  @override
  List<LocalizationsDelegate<Object?>> get localizationsDelegates =>
      GlobalMaterialLocalizations.delegates;

  @override
  Widget build(BuildContext context, SpringAppRequest app) {
    final settings = app.settings;
    final selection = app.selection;
    final shown = app.shown;
    final themes = MaterialThemes.of(SpringScope.of(context));
    ThemeData material(String name) => themes.material(app.themes.data(name));
    // `system`: Material switches between the two with the device.
    final theme = material(
      selection.followsSystem ? selection.systemLight : shown.name,
    );
    final darkTheme = selection.followsSystem
        ? material(selection.systemDark)
        : null;
    final themeMode = selection.followsSystem
        ? ThemeMode.system
        : ThemeMode.light;
    Widget builder(BuildContext context, Widget? child) => DesignScope(
      textStyle: _textStyle,
      selectable: _selectable,
      controls: const MaterialDesignControls(),
      child: app.builder(context, child),
    );
    if (app.router case final router?) {
      return MaterialApp.router(
        routerConfig: router,
        title: settings.title,
        debugShowCheckedModeBanner: settings.debugShowCheckedModeBanner,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        color: shown.appColor,
        locale: settings.locale,
        supportedLocales: settings.supportedLocales,
        localizationsDelegates: settings.localizationsDelegates,
        builder: builder,
        scrollBehavior: settings.scrollBehavior,
        shortcuts: settings.shortcuts,
      );
    }
    return MaterialApp(
      title: settings.title,
      debugShowCheckedModeBanner: settings.debugShowCheckedModeBanner,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
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

  // What `Theme.of` gives: the theme's styles with the sizes of the
  // locale's script.
  static TextStyle? _textStyle(BuildContext context, String style) =>
      Theme.of(context).textTheme.styleNamed(style);

  static Widget _selectable(BuildContext context, Widget child) =>
      SelectionArea(child: child);
}
