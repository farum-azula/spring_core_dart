import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

/// A theme of `spring.flutter.theme.*` as Cupertino's own theme.
///
/// Cupertino widgets read a `CupertinoThemeData`; this makes one of a
/// theme read from the properties, so a `CupertinoApp` and the app's own
/// widgets show the same theme.
///
/// ```yaml
/// spring.flutter.theme:
///   seed-color: teal
///   cupertino:
///     bar-background-color: '#F2F2F7'
///     text-theme:
///       nav-title-text-style: { weight: 600 }
/// ```
///
/// ```dart
/// CupertinoTheme(
///   data: SpringTheme.of(context).toCupertino(),
///   child: const CupertinoNavigationBar(middle: Text('Books')),
/// );
/// ```
extension CupertinoSpringThemeData on SpringThemeData {
  static final _made = Expando<CupertinoThemeData>('CupertinoThemeData');

  static const _transparent = Color(0x00000000);

  /// The theme as a `CupertinoThemeData`, made once: primary color, text
  /// styles and backgrounds where the properties set them, iOS's defaults
  /// otherwise. Throws a [ThemePropertyException] naming the property for
  /// a wrong value or an unknown key under `cupertino`.
  CupertinoThemeData toCupertino() => _made[this] ??= _build(_reader());

  /// `cupertino.primary-color`; `null` when not set.
  Color? get cupertinoPrimaryColor => _reader().color('primaryColor');

  /// The `cupertino.*` properties the theme reads, in the order of the
  /// reading: for the reference documentation and tests.
  List<ThemeProperty> get cupertinoProperties {
    final reader = _reader();
    _build(reader);
    return reader.asked;
  }

  // The reader of `cupertino.*`; a text style named there is the theme's.
  ThemeReader _reader() => ThemeReader(
    theme: this,
    properties: properties,
    root: 'cupertino',
    label: 'cupertino',
    namedStyle: textStyle,
  );

  // `components.app-bar.background-color`, a property of the Material
  // starter: a theme written for both designs has one color for its bars.
  Color? get _appBarBackground => designs.reads('components')
      ? ThemeReader(
          theme: this,
          properties: properties,
          root: 'components.appbar',
          label: 'app-bar',
          namedStyle: textStyle,
        ).color('backgroundColor')
      : null;

  CupertinoThemeData _build(ThemeReader r) {
    final primary =
        r.color('primaryColor') ??
        colors['primary'] ??
        (seedColor == null ? null : colorScheme.primary);
    // iOS's own styles, with this theme's primary color in the ones that
    // carry it (actions, nav actions), not iOS blue.
    final defaults = CupertinoTextThemeData(
      primaryColor: primary ?? CupertinoColors.systemBlue,
    );
    TextStyle typed(TextStyle base, String name) {
      final spec = textStyles[name];
      return (spec?.applyTo(base) ?? base).copyWith(
        fontFamily: spec?.fontFamily ?? fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      );
    }

    final typography =
        fontFamily != null ||
        fontFamilyFallback != null ||
        textStyles.isNotEmpty;
    final t = r.group('textTheme');
    // The style written under `text-theme`, over the one made from the
    // typography, over iOS's own.
    TextStyle style(String key, TextStyle base, String? from) {
      final own = t.text(key, base: base);
      return own ?? (typography && from != null ? typed(base, from) : base);
    }

    final textTheme = CupertinoTextThemeData(
      primaryColor:
          t.color('primaryColor') ?? primary ?? CupertinoColors.systemBlue,
      textStyle: style('textStyle', defaults.textStyle, 'bodylarge'),
      actionTextStyle: style(
        'actionTextStyle',
        defaults.actionTextStyle,
        'labellarge',
      ),
      tabLabelTextStyle: style(
        'tabLabelTextStyle',
        defaults.tabLabelTextStyle,
        'labelsmall',
      ),
      navTitleTextStyle: style(
        'navTitleTextStyle',
        defaults.navTitleTextStyle,
        'titlelarge',
      ),
      navLargeTitleTextStyle: style(
        'navLargeTitleTextStyle',
        defaults.navLargeTitleTextStyle,
        'displaysmall',
      ),
      navActionTextStyle: style(
        'navActionTextStyle',
        defaults.navActionTextStyle,
        'labellarge',
      ),
      pickerTextStyle: style(
        'pickerTextStyle',
        defaults.pickerTextStyle,
        'bodylarge',
      ),
      dateTimePickerTextStyle: style(
        'dateTimePickerTextStyle',
        defaults.dateTimePickerTextStyle,
        'bodylarge',
      ),
    );
    final result = CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      primaryContrastingColor: r.color('primaryContrastingColor'),
      // The theme's own background shows through the scaffolds.
      scaffoldBackgroundColor:
          r.color('scaffoldBackgroundColor') ??
          (background == null ? colors['surface'] : _transparent),
      barBackgroundColor: r.color('barBackgroundColor') ?? _appBarBackground,
      selectionHandleColor: r.color('selectionHandleColor'),
      applyThemeToAll: r.flag('applyThemeToAll'),
      textTheme: typography || t.has ? textTheme : null,
    );
    r.checkUnknown();
    return result;
  }
}
