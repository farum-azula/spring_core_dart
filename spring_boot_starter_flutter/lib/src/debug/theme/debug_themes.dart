import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart'
    show ConfigurationPropertiesBindException, Ordered;
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_theme.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_theme_scope.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// The debug themes of the app by name, and the one selected (the
/// `debugThemes` bean): the `DebugTheme` beans, those declared under
/// `spring.flutter.debug.themes` and the built-in `default`. The first of
/// a name is kept: a declared theme replaces a bean of its name, either
/// replaces `default`. The debug panel's Theme tab selects another live;
/// the selection lasts while the app runs.
final class DebugThemes extends ChangeNotifier
    implements ValueListenable<DebugTheme> {
  /// [themes], the first of each name kept, [selected] selected. Fails
  /// naming `spring.flutter.debug.theme` when none is named [selected].
  DebugThemes(
    Iterable<DebugTheme> themes, {
    String selected = DefaultDebugTheme.defaultName,
  }) {
    for (final theme in themes) {
      _byName.putIfAbsent(theme.name, () => theme);
    }
    _value =
        _byName[selected] ??
        (throw ConfigurationPropertiesBindException(
          'spring.flutter.debug',
          'debugThemes',
          [
            "spring.flutter.debug.theme: no debug theme '$selected'; the "
                'themes are ${names.join(', ')}',
          ],
        ));
  }

  final Map<String, DebugTheme> _byName = {};
  late DebugTheme _value;

  /// The names of the themes, in their order.
  List<String> get names => List.unmodifiable(_byName.keys);

  /// The theme selected.
  @override
  DebugTheme get value => _value;

  /// The name of the theme selected.
  String get selected => _value.name;

  /// Selects the theme named [name]; throws an [ArgumentError] for a name
  /// it does not have.
  void select(String name) {
    final theme =
        _byName[name] ??
        (throw ArgumentError.value(
          name,
          'name',
          'no debug theme of this name; the themes are ${names.join(', ')}',
        ));
    if (!identical(theme, _value)) {
      _value = theme;
      notifyListeners();
    }
  }
}

/// Puts [themes] over the app, around every debug tool
/// ([DebugThemeScope]): applied last, outside the debug panel and the
/// overlays.
final class DebugThemeCustomizer implements FlutterAppCustomizer, Ordered {
  /// The scope of [themes].
  const DebugThemeCustomizer(this.themes);

  /// The themes.
  final DebugThemes themes;

  @override
  int get order => Ordered.lowestPrecedence;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => DebugThemeScope(
      themes: themes,
      child: inner == null ? child! : inner(context, child),
    );
  }
}
