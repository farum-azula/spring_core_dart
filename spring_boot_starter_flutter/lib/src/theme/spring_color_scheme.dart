import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';

/// The color roles of a palette that `colors.<role>` may set, by canonical
/// name (lower case, no separators): the roles of Material 3.
const colorRoles = [
  'primary',
  'onprimary',
  'primarycontainer',
  'onprimarycontainer',
  'primaryfixed',
  'primaryfixeddim',
  'onprimaryfixed',
  'onprimaryfixedvariant',
  'secondary',
  'onsecondary',
  'secondarycontainer',
  'onsecondarycontainer',
  'secondaryfixed',
  'secondaryfixeddim',
  'onsecondaryfixed',
  'onsecondaryfixedvariant',
  'tertiary',
  'ontertiary',
  'tertiarycontainer',
  'ontertiarycontainer',
  'tertiaryfixed',
  'tertiaryfixeddim',
  'ontertiaryfixed',
  'ontertiaryfixedvariant',
  'error',
  'onerror',
  'errorcontainer',
  'onerrorcontainer',
  'surface',
  'onsurface',
  'onsurfacevariant',
  'surfacedim',
  'surfacebright',
  'surfacecontainerlowest',
  'surfacecontainerlow',
  'surfacecontainer',
  'surfacecontainerhigh',
  'surfacecontainerhighest',
  'surfacetint',
  'inversesurface',
  'oninversesurface',
  'inverseprimary',
  'outline',
  'outlinevariant',
  'shadow',
  'scrim',
];

/// The palette of a theme: one color per role (`primary`, `onSurface`,
/// `outlineVariant`), light or dark.
///
/// The roles and their names are Material 3's, so a theme from properties
/// reads the same in an app of any design. The class itself belongs to no
/// design library: an app without one (`spring.flutter.app.type: widgets`)
/// has it too. The Material starter makes Material's `ColorScheme` of it.
///
/// A theme's palette is [baseline] (or the one its design makes from
/// `seed-color`) with the roles of `colors.*` over it; read it with
/// `SpringTheme.of(context).colorScheme`.
///
/// ```dart
/// final colors = SpringTheme.of(context).colorScheme;
/// ColoredBox(color: colors.surfaceContainer, child: child);
/// ```
@immutable
final class SpringColorScheme {
  SpringColorScheme._(this.brightness, this._roles);

  /// A palette of [brightness] with a color for every role. [roles] has
  /// the names of [colorRoles] in any case, with or without `-` and `_`.
  /// Throws an `ArgumentError` for a role that is missing or unknown.
  factory SpringColorScheme(Brightness brightness, Map<String, Color> roles) {
    final canonical = {
      for (final MapEntry(:key, :value) in roles.entries)
        _canonical(key): value,
    };
    for (final role in canonical.keys) {
      if (!colorRoles.contains(role)) {
        throw ArgumentError.value(role, 'roles', 'not a color role');
      }
    }
    for (final role in colorRoles) {
      if (!canonical.containsKey(role)) {
        throw ArgumentError.value(role, 'roles', 'a color role is missing');
      }
    }
    return SpringColorScheme._(brightness, Map.unmodifiable(canonical));
  }

  /// The palette a theme has when nothing sets its colors: Material 3's
  /// baseline, the one Flutter's `ThemeData()` has.
  factory SpringColorScheme.baseline(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static String _canonical(String name) =>
      name.replaceAll(RegExp('[-_ ]'), '').toLowerCase();

  /// Whether the palette is light or dark.
  final Brightness brightness;

  final Map<String, Color> _roles;

  /// Every role by canonical name (`surfacecontainer`), in the order of
  /// [colorRoles].
  Map<String, Color> get roles => _roles;

  /// The color of role [name] (`surface-container`, `onPrimary`); `null`
  /// for an unknown role.
  Color? role(String name) => _roles[_canonical(name)];

  /// This palette with [roles] (names as for the constructor) changed.
  /// Throws an `ArgumentError` for an unknown role.
  SpringColorScheme withRoles(Map<String, Color> roles) => roles.isEmpty
      ? this
      : SpringColorScheme(brightness, {
          ..._roles,
          ...{
            for (final MapEntry(:key, :value) in roles.entries)
              _canonical(key): value,
          },
        });

  /// The color of the most prominent elements.
  Color get primary => _roles['primary']!;

  /// The role `onPrimary`.
  Color get onPrimary => _roles['onprimary']!;

  /// The role `primaryContainer`.
  Color get primaryContainer => _roles['primarycontainer']!;

  /// The role `onPrimaryContainer`.
  Color get onPrimaryContainer => _roles['onprimarycontainer']!;

  /// The role `primaryFixed`.
  Color get primaryFixed => _roles['primaryfixed']!;

  /// The role `primaryFixedDim`.
  Color get primaryFixedDim => _roles['primaryfixeddim']!;

  /// The role `onPrimaryFixed`.
  Color get onPrimaryFixed => _roles['onprimaryfixed']!;

  /// The role `onPrimaryFixedVariant`.
  Color get onPrimaryFixedVariant => _roles['onprimaryfixedvariant']!;

  /// The role `secondary`.
  Color get secondary => _roles['secondary']!;

  /// The role `onSecondary`.
  Color get onSecondary => _roles['onsecondary']!;

  /// The role `secondaryContainer`.
  Color get secondaryContainer => _roles['secondarycontainer']!;

  /// The role `onSecondaryContainer`.
  Color get onSecondaryContainer => _roles['onsecondarycontainer']!;

  /// The role `secondaryFixed`.
  Color get secondaryFixed => _roles['secondaryfixed']!;

  /// The role `secondaryFixedDim`.
  Color get secondaryFixedDim => _roles['secondaryfixeddim']!;

  /// The role `onSecondaryFixed`.
  Color get onSecondaryFixed => _roles['onsecondaryfixed']!;

  /// The role `onSecondaryFixedVariant`.
  Color get onSecondaryFixedVariant => _roles['onsecondaryfixedvariant']!;

  /// The role `tertiary`.
  Color get tertiary => _roles['tertiary']!;

  /// The role `onTertiary`.
  Color get onTertiary => _roles['ontertiary']!;

  /// The role `tertiaryContainer`.
  Color get tertiaryContainer => _roles['tertiarycontainer']!;

  /// The role `onTertiaryContainer`.
  Color get onTertiaryContainer => _roles['ontertiarycontainer']!;

  /// The role `tertiaryFixed`.
  Color get tertiaryFixed => _roles['tertiaryfixed']!;

  /// The role `tertiaryFixedDim`.
  Color get tertiaryFixedDim => _roles['tertiaryfixeddim']!;

  /// The role `onTertiaryFixed`.
  Color get onTertiaryFixed => _roles['ontertiaryfixed']!;

  /// The role `onTertiaryFixedVariant`.
  Color get onTertiaryFixedVariant => _roles['ontertiaryfixedvariant']!;

  /// The color of errors.
  Color get error => _roles['error']!;

  /// The role `onError`.
  Color get onError => _roles['onerror']!;

  /// The role `errorContainer`.
  Color get errorContainer => _roles['errorcontainer']!;

  /// The role `onErrorContainer`.
  Color get onErrorContainer => _roles['onerrorcontainer']!;

  /// The background of large areas.
  Color get surface => _roles['surface']!;

  /// Text and icons on [surface].
  Color get onSurface => _roles['onsurface']!;

  /// The role `onSurfaceVariant`.
  Color get onSurfaceVariant => _roles['onsurfacevariant']!;

  /// The role `surfaceDim`.
  Color get surfaceDim => _roles['surfacedim']!;

  /// The role `surfaceBright`.
  Color get surfaceBright => _roles['surfacebright']!;

  /// The role `surfaceContainerLowest`.
  Color get surfaceContainerLowest => _roles['surfacecontainerlowest']!;

  /// The role `surfaceContainerLow`.
  Color get surfaceContainerLow => _roles['surfacecontainerlow']!;

  /// The role `surfaceContainer`.
  Color get surfaceContainer => _roles['surfacecontainer']!;

  /// The role `surfaceContainerHigh`.
  Color get surfaceContainerHigh => _roles['surfacecontainerhigh']!;

  /// The role `surfaceContainerHighest`.
  Color get surfaceContainerHighest => _roles['surfacecontainerhighest']!;

  /// The role `surfaceTint`.
  Color get surfaceTint => _roles['surfacetint']!;

  /// The role `inverseSurface`.
  Color get inverseSurface => _roles['inversesurface']!;

  /// The role `onInverseSurface`.
  Color get onInverseSurface => _roles['oninversesurface']!;

  /// The role `inversePrimary`.
  Color get inversePrimary => _roles['inverseprimary']!;

  /// Borders that need contrast.
  Color get outline => _roles['outline']!;

  /// The role `outlineVariant`.
  Color get outlineVariant => _roles['outlinevariant']!;

  /// The role `shadow`.
  Color get shadow => _roles['shadow']!;

  /// The role `scrim`.
  Color get scrim => _roles['scrim']!;

  @override
  bool operator ==(Object other) =>
      other is SpringColorScheme &&
      other.brightness == brightness &&
      mapEquals(other._roles, _roles);

  @override
  int get hashCode => Object.hash(brightness, Object.hashAll(_roles.values));

  @override
  String toString() => 'SpringColorScheme(${brightness.name})';

  static final _light = SpringColorScheme._(Brightness.light, const {
    'primary': Color(0xFF6750A4),
    'onprimary': Color(0xFFFFFFFF),
    'primarycontainer': Color(0xFFEADDFF),
    'onprimarycontainer': Color(0xFF4F378B),
    'primaryfixed': Color(0xFFEADDFF),
    'primaryfixeddim': Color(0xFFD0BCFF),
    'onprimaryfixed': Color(0xFF21005D),
    'onprimaryfixedvariant': Color(0xFF4F378B),
    'secondary': Color(0xFF625B71),
    'onsecondary': Color(0xFFFFFFFF),
    'secondarycontainer': Color(0xFFE8DEF8),
    'onsecondarycontainer': Color(0xFF4A4458),
    'secondaryfixed': Color(0xFFE8DEF8),
    'secondaryfixeddim': Color(0xFFCCC2DC),
    'onsecondaryfixed': Color(0xFF1D192B),
    'onsecondaryfixedvariant': Color(0xFF4A4458),
    'tertiary': Color(0xFF7D5260),
    'ontertiary': Color(0xFFFFFFFF),
    'tertiarycontainer': Color(0xFFFFD8E4),
    'ontertiarycontainer': Color(0xFF633B48),
    'tertiaryfixed': Color(0xFFFFD8E4),
    'tertiaryfixeddim': Color(0xFFEFB8C8),
    'ontertiaryfixed': Color(0xFF31111D),
    'ontertiaryfixedvariant': Color(0xFF633B48),
    'error': Color(0xFFB3261E),
    'onerror': Color(0xFFFFFFFF),
    'errorcontainer': Color(0xFFF9DEDC),
    'onerrorcontainer': Color(0xFF8C1D18),
    'surface': Color(0xFFFEF7FF),
    'onsurface': Color(0xFF1D1B20),
    'onsurfacevariant': Color(0xFF49454F),
    'surfacedim': Color(0xFFDED8E1),
    'surfacebright': Color(0xFFFEF7FF),
    'surfacecontainerlowest': Color(0xFFFFFFFF),
    'surfacecontainerlow': Color(0xFFF7F2FA),
    'surfacecontainer': Color(0xFFF3EDF7),
    'surfacecontainerhigh': Color(0xFFECE6F0),
    'surfacecontainerhighest': Color(0xFFE6E0E9),
    'surfacetint': Color(0xFF6750A4),
    'inversesurface': Color(0xFF322F35),
    'oninversesurface': Color(0xFFF5EFF7),
    'inverseprimary': Color(0xFFD0BCFF),
    'outline': Color(0xFF79747E),
    'outlinevariant': Color(0xFFCAC4D0),
    'shadow': Color(0xFF000000),
    'scrim': Color(0xFF000000),
  });

  static final _dark = SpringColorScheme._(Brightness.dark, const {
    'primary': Color(0xFFD0BCFF),
    'onprimary': Color(0xFF381E72),
    'primarycontainer': Color(0xFF4F378B),
    'onprimarycontainer': Color(0xFFEADDFF),
    'primaryfixed': Color(0xFFEADDFF),
    'primaryfixeddim': Color(0xFFD0BCFF),
    'onprimaryfixed': Color(0xFF21005D),
    'onprimaryfixedvariant': Color(0xFF4F378B),
    'secondary': Color(0xFFCCC2DC),
    'onsecondary': Color(0xFF332D41),
    'secondarycontainer': Color(0xFF4A4458),
    'onsecondarycontainer': Color(0xFFE8DEF8),
    'secondaryfixed': Color(0xFFE8DEF8),
    'secondaryfixeddim': Color(0xFFCCC2DC),
    'onsecondaryfixed': Color(0xFF1D192B),
    'onsecondaryfixedvariant': Color(0xFF4A4458),
    'tertiary': Color(0xFFEFB8C8),
    'ontertiary': Color(0xFF492532),
    'tertiarycontainer': Color(0xFF633B48),
    'ontertiarycontainer': Color(0xFFFFD8E4),
    'tertiaryfixed': Color(0xFFFFD8E4),
    'tertiaryfixeddim': Color(0xFFEFB8C8),
    'ontertiaryfixed': Color(0xFF31111D),
    'ontertiaryfixedvariant': Color(0xFF633B48),
    'error': Color(0xFFF2B8B5),
    'onerror': Color(0xFF601410),
    'errorcontainer': Color(0xFF8C1D18),
    'onerrorcontainer': Color(0xFFF9DEDC),
    'surface': Color(0xFF141218),
    'onsurface': Color(0xFFE6E0E9),
    'onsurfacevariant': Color(0xFFCAC4D0),
    'surfacedim': Color(0xFF141218),
    'surfacebright': Color(0xFF3B383E),
    'surfacecontainerlowest': Color(0xFF0F0D13),
    'surfacecontainerlow': Color(0xFF1D1B20),
    'surfacecontainer': Color(0xFF211F26),
    'surfacecontainerhigh': Color(0xFF2B2930),
    'surfacecontainerhighest': Color(0xFF36343B),
    'surfacetint': Color(0xFFD0BCFF),
    'inversesurface': Color(0xFFE6E0E9),
    'oninversesurface': Color(0xFF322F35),
    'inverseprimary': Color(0xFF6750A4),
    'outline': Color(0xFF938F99),
    'outlinevariant': Color(0xFF49454F),
    'shadow': Color(0xFF000000),
    'scrim': Color(0xFF000000),
  });
}
