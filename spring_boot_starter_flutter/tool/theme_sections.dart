// The theme keys that are not Material components, for `properties` in
// tool/theme_metadata.json (see tool/theme_metadata.dart): the root keys,
// colors, typography, shape, spacing, elevation, motion, animations,
// background, styles and tokens, plus a flat form of the components.
//
// Names and rules come from the theme reader (lib/src/theme) and the
// hand-written pages in docs/flutter/theme. The color roles and their
// descriptions are read from docs/flutter/theme/colors.md and checked
// against the reader's own list, so a new role cannot be forgotten.
import 'dart:io';

typedef ThemeProp = Map<String, Object?>;

ThemeProp _p(
  String name,
  String type,
  String description, {
  String? defaultValue,
  List<String> values = const [],
  bool states = false,
  String? scope,
  bool open = false,
}) => {
  'name': name,
  'type': type,
  'states': states,
  'values': values,
  'description': description,
  'default': defaultValue,
  'scope': ?scope,
  if (open) 'open': true,
};

/// The components as flat properties: `components.app-bar.elevation`, and
/// `cupertino.primary-color` for the component with its own root.
List<ThemeProp> componentProperties(List<Map<String, Object?>> components) => [
  for (final component in components)
    for (final raw
        in (component['properties']! as List).cast<Map<String, Object?>>())
      {
        'name':
            '${component['ownRoot'] == true ? '' : 'components.'}'
            '${component['name']}.${raw['key']}',
        'type': raw['type'],
        'states': raw['states'],
        'values': raw['values'],
        'description': raw['description'],
        'flutter': raw['flutterField'],
        'default': raw['default'],
      },
];

/// Every other key of a theme.
List<ThemeProp> themeSections() => [
  ..._root(),
  ..._colors(),
  ..._typography(),
  ..._shape(),
  ..._motion(),
  ..._background(),
  _p(
    'tokens.*',
    'map',
    'Your own values, at any depth: numbers, durations, colors, text, '
        'images. Read them with `\$tokens.<name>` or from Dart.',
    open: true,
  ),
  _p(
    'styles.*',
    'map',
    'A look per state for your own widgets: `styles.<name>.<property>` '
        'holds a value, or a map from a state to a value.',
    open: true,
  ),
];

List<ThemeProp> _root() => [
  _p(
    'active',
    'text',
    'The theme shown at start: `system` or the name of a theme. '
        '`ThemeSelection.select(...)` changes it at run time.',
    defaultValue: 'system',
    scope: 'root',
  ),
  _p(
    'system-light',
    'text',
    'The theme `system` shows when the device is in light mode.',
    defaultValue: 'light',
    scope: 'root',
  ),
  _p(
    'system-dark',
    'text',
    'The theme `system` shows when the device is in dark mode.',
    defaultValue: 'dark',
    scope: 'root',
  ),
  _p(
    'extends',
    'text',
    'Start this theme from another theme (`light`, `dark` or one of your '
        'own) instead of the root. A cycle or an unknown parent stops the '
        'start.',
    defaultValue: 'the root',
    scope: 'theme',
  ),
  _p(
    'source',
    'text',
    'Download the theme from an https URL or '
        '`github:owner/repo/path@ref`.',
    scope: 'theme',
  ),
  _p(
    'source-sha256',
    'text',
    'Refuse a download that does not have this SHA-256 digest (64 '
        'hexadecimal digits).',
    scope: 'theme',
  ),
  _p(
    'refresh',
    'duration',
    'Look at the address again in the background when the cache is older '
        'than this.',
    scope: 'theme',
  ),
  _p(
    'brightness',
    'choice',
    'Whether the theme is light or dark. It decides which tones the '
        'palette uses and what the system bars look like.',
    defaultValue:
        '`dark` for the `dark` theme, `light` for others; inherited '
        'with `extends`',
    values: ['light', 'dark'],
  ),
  _p(
    'seed-color',
    'color',
    'The one color the whole palette is made from.',
    defaultValue: "Flutter's baseline Material 3 palette",
  ),
  _p(
    'scheme-variant',
    'choice',
    'How the palette is made from the seed.',
    defaultValue: 'tonalSpot',
    values: [
      'tonalSpot',
      'fidelity',
      'content',
      'vibrant',
      'expressive',
      'monochrome',
      'neutral',
      'rainbow',
      'fruitSalad',
    ],
  ),
  _p(
    'contrast',
    'number',
    'Palette contrast, from -1 (softer) to 1 (high); 0 is standard.',
    defaultValue: '0',
  ),
  _p(
    'visual-density',
    'choice',
    'How tightly components are packed.',
    defaultValue: "Flutter's",
    values: ['adaptive', 'standard', 'comfortable', 'compact'],
  ),
  _p(
    'tap-target-size',
    'choice',
    'The minimum size of a tap target.',
    defaultValue: "Flutter's",
    values: ['padded', 'shrink-wrap'],
  ),
  _p(
    'splash',
    'choice',
    'The ink effect when something is tapped.',
    defaultValue: "Flutter's",
    values: ['ripple', 'sparkle', 'none'],
  ),
];

// The role tables of colors.md: "| `role` | what it is used for |".
List<ThemeProp> _colors() {
  final lines = File('../docs/flutter/theme/colors.md').readAsLinesSync();
  final start = lines.indexWhere((l) => l.startsWith('## The color roles'));
  final row = RegExp(r'^\| `([a-z-]+)` \| ([^|]+) \|$');
  final found = <String, String>{};
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ') && found.isNotEmpty) {
      break;
    }
    if (row.firstMatch(line) case final m?) {
      found[m[1]!] = m[2]!.trim();
    }
  }
  final source = File('lib/src/theme/spring_theme_data.dart')
      .readAsStringSync();
  final list = RegExp(
    r'const colorRoles = \[(.*?)\];',
    dotAll: true,
  ).firstMatch(source)![1]!;
  final canonical = {
    for (final m in RegExp("'([a-z]+)'").allMatches(list)) m[1]!,
  };
  final documented = {for (final r in found.keys) r.replaceAll('-', '')};
  if (!documented.containsAll(canonical) ||
      !canonical.containsAll(documented)) {
    throw StateError(
      'docs/flutter/theme/colors.md and colorRoles differ: '
      '${canonical.difference(documented)} / ${documented.difference(canonical)}',
    );
  }
  return [
    for (final MapEntry(:key, :value) in found.entries)
      _p(
        'colors.$key',
        'color',
        value.endsWith('.') ? value : '$value.',
        defaultValue: 'from the seed',
      ),
  ];
}

const _textStyles = [
  'display-large',
  'display-medium',
  'display-small',
  'headline-large',
  'headline-medium',
  'headline-small',
  'title-large',
  'title-medium',
  'title-small',
  'body-large',
  'body-medium',
  'body-small',
  'label-large',
  'label-medium',
  'label-small',
];

List<ThemeProp> _typography() {
  final scopes = {
    'defaults': 'every style (the weakest layer)',
    for (final g in ['display', 'headline', 'title', 'body', 'label'])
      g: 'the three sizes of `$g`',
    for (final s in _textStyles) s: 'the `$s` style',
    'code': 'the monospaced `code` style',
  };
  return [
    _p(
      'typography.font-family',
      'text',
      'The font of all text.',
      defaultValue: "the platform's font",
    ),
    _p(
      'typography.font-family-fallback',
      'text',
      'Fonts to try, in order, for characters the main font does not have: '
          'a YAML list or one comma-separated value.',
    ),
    for (final MapEntry(:key, :value) in scopes.entries) ...[
      _p(
        'typography.$key.font-family',
        'text',
        'The font of $value.',
        defaultValue: 'typography.font-family',
      ),
      _p(
        'typography.$key.size',
        'number',
        'Font size of $value, in logical pixels.',
        defaultValue: key == 'code' ? '14' : "Material's",
      ),
      _p(
        'typography.$key.weight',
        'text',
        'Font weight of $value: `100` to `900` in steps of 100, or `thin`, '
            '`extra-light`, `light`, `normal`, `medium`, `semibold`, `bold`, '
            '`extra-bold`, `black`.',
        defaultValue: "Material's",
      ),
      _p(
        'typography.$key.height',
        'number',
        'Line height of $value, as a multiple of the size.',
        defaultValue: "Material's",
      ),
      _p(
        'typography.$key.letter-spacing',
        'number',
        'Space added after each letter of $value, in logical pixels.',
        defaultValue: "Material's",
      ),
    ],
  ];
}

List<ThemeProp> _shape() {
  const shapes = {
    'none': ('Square corners.', '0'),
    'extra-small': ('Very small rounding: text fields, tooltips.', '4'),
    'small': ('Small rounding: chips.', '8'),
    'medium': ('Medium rounding: cards.', '12'),
    'large': ('Large rounding: floating action buttons.', '16'),
    'large-increased': ('A step between large and extra large.', '20'),
    'extra-large': ('Dialogs and bottom sheets.', '28'),
    'extra-large-increased': ('A step above extra large.', '32'),
    'extra-extra-large': ('The largest rounding.', '48'),
    'full': ('A stadium: fully round ends. Buttons use it.', 'infinity'),
  };
  const levels = {
    0: ('Flat on the surface.', '0'),
    1: ('Cards, resting buttons.', '1'),
    2: ('Raised or scrolled app bars.', '3'),
    3: ('Menus and floating buttons at rest.', '6'),
    4: ('Higher menus, hovered floating buttons.', '8'),
    5: ('Dragged surfaces.', '12'),
  };
  const spaces = {
    'xs': ('The smallest gap.', '4'),
    's': ('A small gap between related items.', '8'),
    'm': ('The normal page padding.', '16'),
    'l': ('A gap between sections.', '24'),
    'xl': ('A large gap.', '32'),
  };
  return [
    for (final MapEntry(:key, :value) in shapes.entries)
      _p(
        'shape.$key',
        'number',
        'Corner radius `$key`. ${value.$1}',
        defaultValue: value.$2,
      ),
    for (final MapEntry(:key, :value) in levels.entries)
      _p(
        'elevation.level$key',
        'number',
        'Elevation level $key. ${value.$1}',
        defaultValue: value.$2,
      ),
    for (final MapEntry(:key, :value) in spaces.entries)
      _p(
        'spacing.$key',
        'number',
        'Spacing `$key`. ${value.$1}',
        defaultValue: value.$2,
      ),
    _p(
      'spacing.*',
      'number',
      'A gap of your own for your widgets, such as `gutter: 20`.',
    ),
  ];
}

List<ThemeProp> _motion() => [
  _p(
    'motion.page-transition',
    'choice',
    'The page transition used on every platform.',
    defaultValue: 'platform',
    values: ['platform', 'fade-upwards', 'zoom', 'cupertino', 'none'],
  ),
  _p(
    'motion.durations.*',
    'duration',
    'A named duration (`short` 100ms, `medium` 250ms, `long` 450ms exist '
        'without being written).',
  ),
  _p(
    'motion.curves.*',
    'curve',
    'A named curve: a curve name or four numbers (`0.2, 0, 0, 1`).',
    defaultValue: 'standard',
  ),
  _p(
    'animations.*.duration',
    'duration',
    'How long one run of the animation takes. Required.',
  ),
  _p(
    'animations.*.curve',
    'curve',
    'The curve of one run: a curve name or four numbers.',
    defaultValue: 'linear',
  ),
  _p(
    'animations.*.repeat',
    'choice',
    'What happens at the end of a run.',
    defaultValue: 'none',
    values: ['none', 'loop', 'reverse'],
  ),
];

// The keys of the background and of the background of one screen.
List<ThemeProp> _background() {
  List<ThemeProp> keys(String root, String where) => [
    _p(
      '$root.color',
      'color',
      'The base layer under everything else $where. It also shows while '
          'the image loads.',
      defaultValue: "the theme's `surface`",
    ),
    _p(
      '$root.image.source',
      'text',
      'The picture: an asset path, an https URL, or an http URL with '
          '`allow-http`. Required.',
    ),
    _p(
      '$root.image.refresh',
      'duration',
      'How old the cache may get before the picture is looked at again in '
          'the background.',
    ),
    _p(
      '$root.image.source-sha256',
      'text',
      'The file must have exactly this SHA-256 digest (64 hexadecimal '
          'digits).',
    ),
    _p(
      '$root.image.headers.*',
      'text',
      'A request header, such as `Authorization`; `\${...}` placeholders '
          'are resolved by the configuration.',
    ),
    _p(
      '$root.image.timeout',
      'duration',
      'The longest a download may take.',
      defaultValue: '10s',
    ),
    _p(
      '$root.image.fallback',
      'text',
      'An asset shown while a network image is not there yet.',
    ),
    _p(
      '$root.image.allow-http',
      'true / false',
      'Allows an `http://` source. Without it an `http://` source stops '
          'the start.',
      defaultValue: 'false',
    ),
    _p(
      '$root.image.fit',
      'choice',
      'How the picture fills the screen.',
      defaultValue: 'cover',
      values: [
        'cover',
        'contain',
        'fill',
        'fit-width',
        'fit-height',
        'none',
        'scale-down',
      ],
    ),
    _p(
      '$root.image.alignment',
      'alignment',
      'Which part of the picture stays in view: `center`, `top-left`, '
          '..., or `x, y` from -1 to 1.',
      defaultValue: 'center',
    ),
    _p(
      '$root.image.opacity',
      'number',
      'How opaque the picture is, from 0 to 1.',
      defaultValue: '1',
    ),
    _p(
      '$root.image.blur',
      'number',
      'A Gaussian blur radius in logical pixels; 0 is sharp.',
      defaultValue: '0',
    ),
    _p(
      '$root.overlay.color',
      'color',
      'A flat color painted over the whole image; use some transparency.',
    ),
    _p(
      '$root.overlay.gradient.type',
      'choice',
      'The kind of gradient.',
      defaultValue: 'linear',
      values: ['linear', 'radial'],
    ),
    _p(
      '$root.overlay.gradient.begin',
      'alignment',
      'Where a linear gradient starts; the centre of a radial one.',
      defaultValue: 'top (linear), center (radial)',
    ),
    _p(
      '$root.overlay.gradient.end',
      'alignment',
      'Where a linear gradient ends. A radial gradient does not use it.',
      defaultValue: 'bottom',
    ),
    _p(
      '$root.overlay.gradient.colors',
      'list of colors',
      'The colors of the gradient, at least two.',
    ),
    _p(
      '$root.overlay.gradient.stops',
      'list of numbers',
      'Where each color sits along the gradient, from 0 to 1.',
      defaultValue: 'even spacing',
    ),
    _p(
      '$root.animation',
      'text',
      'The name of an `animations.<name>` that moves the image.',
    ),
    _p(
      '$root.effect',
      'choice',
      'How the image moves.',
      defaultValue: 'drift when `animation` is set',
      values: ['drift', 'zoom', 'pulse'],
    ),
    _p(
      '$root.transition',
      'text',
      'The cross-fade when the background changes: `<duration> [<curve>]`.',
      defaultValue: '300ms ease-out',
    ),
  ];
  return [
    ...keys('background', 'of every screen'),
    ...keys('background.screens.*', 'of this screen'),
  ];
}
