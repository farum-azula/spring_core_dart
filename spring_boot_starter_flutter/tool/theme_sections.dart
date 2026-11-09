// The theme keys that are not Material components, for `properties` in
// tool/theme_metadata.json (see tool/theme_metadata.dart): the root keys,
// colors, typography, shape, spacing, elevation, motion, animations,
// background, loaders, splash, styles and tokens, plus a flat form of the components.
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
  ..._loaders(),
  ..._splash(),
  ..._syntax(),
  ..._frameMeter(),
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

// The languages of code blocks: docs/flutter/theme/syntax.md.
List<ThemeProp> _syntax() => [
  _p(
    'syntax.*.rules',
    'list of maps',
    'The rules, tried in order at each position of the code: each '
        '`{ match, kind }`, a regular expression (`^` and `\$` are a '
        "line's start and end) and the kind of what it matches. Required.",
  ),
  _p(
    'syntax.*.rules.*.match',
    'text',
    'A regular expression, taken as written (no `\$` reference). An '
        'invalid one stops the start.',
  ),
  _p(
    'syntax.*.rules.*.kind',
    'choice',
    'What a match is: a piece colored by `styles.code.<kind>`, or `word`, '
        'a keyword when it is in `keywords`, a type when it matches '
        '`types`, plain otherwise.',
    values: [
      'comment', 'string', 'annotation', 'number', 'key', 'keyword', //
      'type', 'variable', 'punctuation', 'plain', 'word',
    ],
  ),
  _p(
    'syntax.*.keywords',
    'list of texts',
    'The words a `word` rule colors as keywords.',
    defaultValue: 'none',
  ),
  _p(
    'syntax.*.types',
    'text',
    'A regular expression a word of a `word` rule must match to be a type '
        'name.',
    defaultValue: 'none',
  ),
  _p(
    'syntax.*.aliases',
    'list of texts',
    "Other names of the language in a fenced block's info (`yml`, `bash`).",
    defaultValue: 'none',
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
    'remember',
    'choice',
    'Keeps the theme the user chooses (`ThemeSelection.select`) between '
        'runs and shows it again while the splash shows.',
    defaultValue: 'true',
    values: ['true', 'false'],
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
        '`github:owner/repo/path@ref`. Under `spring.flutter.theme` itself, '
        'the values every theme shares (the languages of code blocks, '
        'say), under what your files set.',
  ),
  _p(
    'source-sha256',
    'text',
    'Refuse a download that does not have this SHA-256 digest (64 '
        'hexadecimal digits).',
  ),
  _p(
    'refresh',
    'duration',
    'Look at the address again in the background when the cache is older '
        'than this.',
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
    'motion.enabled',
    'true / false',
    'Whether the app moves at all: `false` makes every page transition, '
        'text and content change, scroll to the top and theme animation '
        'instant, as the device\'s "reduce motion" does.',
    defaultValue: 'true',
  ),
  _p(
    'motion.page-transition',
    'choice',
    'How a new screen comes in, on every platform: a kind, or a map of '
        '`type`, `duration`, `curve`.',
    defaultValue: 'none',
    values: [
      'none',
      'platform',
      'fade-upwards',
      'zoom',
      'cupertino',
      'fade',
      'content',
    ],
  ),
  _p(
    'motion.page-transition.type',
    'choice',
    'The map form\'s kind.',
    defaultValue: 'none',
    values: [
      'none',
      'platform',
      'fade-upwards',
      'zoom',
      'cupertino',
      'fade',
      'content',
    ],
  ),
  _p(
    'motion.page-transition.duration',
    'duration',
    'How long the transition takes.',
  ),
  _p(
    'motion.page-transition.curve',
    'curve',
    'The curve of the transition.',
  ),
  _p(
    'motion.text-change',
    'choice',
    'What a `ThemeText` does when its text changes (another language): '
        'at once, a cross-fade, or `morph`, character after character from '
        'the start of the line. A kind, or a map of `type`, `duration`, '
        '`curve`, `stagger`.',
    defaultValue: 'none',
    values: ['none', 'fade', 'morph'],
  ),
  _p(
    'motion.text-change.type',
    'choice',
    'The map form\'s kind.',
    defaultValue: 'none',
    values: ['none', 'fade', 'morph'],
  ),
  _p(
    'motion.text-change.keep-unchanged',
    'true / false',
    'For `morph`: `true` keeps the characters that are the same in the old '
        'and the new text, so only the changed part runs through glyphs; '
        '`false` runs the wave over the whole line.',
    defaultValue: 'false',
  ),
  _p(
    'motion.text-change.duration',
    'duration',
    'How long the whole change takes.',
    defaultValue: '450ms',
  ),
  _p(
    'motion.text-change.curve',
    'curve',
    'The curve of the change.',
    defaultValue: 'ease-out',
  ),
  _p(
    'motion.text-change.stagger',
    'duration',
    'For `morph`, how much later each character starts than the one before '
        'it.',
    defaultValue: '12ms',
  ),
  _p(
    'motion.text-change.glyphs',
    'text',
    'For `morph`: the characters a changing character runs through, taken '
        'as written (no `\$` references).',
    defaultValue: '▓▒░<>/\\|=+*#%&@\$?!01',
  ),
  _p(
    'motion.text-change.glyph-duration',
    'duration',
    'For `morph`: how long each glyph shows before the next.',
    defaultValue: '40ms',
  ),
  _p(
    'motion.overscroll',
    'choice',
    'What a scrollable shows when pulled past its end: the app type\'s own '
        '(`platform`: Material\'s stretch on Android, which distorts the '
        'content) or nothing (`none`).',
    defaultValue: 'platform',
    values: ['platform', 'none'],
  ),
  _p(
    'motion.wheel-scroll',
    'text',
    'How a mouse wheel scrolls every scrollable of the app: `none` (the '
        'default) moves by the wheel\'s step at once, as Flutter does; a map '
        'of `duration` and `speed` eases each step and scales it.',
    defaultValue: 'none',
  ),
  _p(
    'motion.wheel-scroll.duration',
    'duration',
    'How long a step of the wheel takes to arrive.',
    defaultValue: '250ms',
  ),
  _p(
    'motion.wheel-scroll.speed',
    'number',
    'The share of the wheel\'s step: below 1 slower, above faster.',
    defaultValue: '1',
  ),
  _p(
    'motion.wheel-scroll.inertia',
    'text',
    'The inertia of scrolling, each kind of pointer its own: `none` (the '
        'default), or a map of `mouse`, `trackpad` and `touch`.',
    defaultValue: 'none',
  ),
  _p(
    'motion.wheel-scroll.inertia.mouse',
    'number',
    'What each quick step of the wheel in a row adds to the next (0.2: a '
        'fifth more), and the longer glide of a fast run; 0 for none.',
    defaultValue: '0',
  ),
  _p(
    'motion.wheel-scroll.inertia.trackpad',
    'number',
    'How much of its last step the page keeps each frame once the fingers '
        'stop on the trackpad (0.9 glides on); 0 for none, for a system '
        'that glides by itself.',
    defaultValue: '0',
  ),
  _p(
    'motion.wheel-scroll.inertia.touch',
    'number',
    'How much further a flick of the finger throws the page (0.5: half '
        'again as far); 0 for none.',
    defaultValue: '0',
  ),
  _p(
    'motion.scroll-to-top',
    'text',
    'How a screen goes back to its top when it shows another page '
        '(`RouteContentView`): `none` jumps; else a map of `duration` and '
        '`curve`.',
    defaultValue: '400ms ease-out-cubic',
  ),
  _p(
    'motion.scroll-to-top.duration',
    'duration',
    'How long the scroll to the top takes.',
    defaultValue: '400ms',
  ),
  _p(
    'motion.scroll-to-top.curve',
    'curve',
    'The curve of the scroll to the top.',
    defaultValue: 'ease-out-cubic',
  ),
  _p(
    'motion.content-change',
    'choice',
    'How a part of a screen shows other content in its place (another page '
        'in `RouteContentView`, `ContentChange`): at once, a cross-fade, '
        'a cross-fade rising a little, or `morph`, the new page typing '
        'itself in line after line; a kind of the app\'s own with '
        '`ContentTransitions.register`. A kind, or a map of `type`, '
        '`duration`, `curve`, `stagger`, `delay`.',
    defaultValue: 'none',
    values: ['none', 'fade', 'fade-up', 'morph'],
  ),
  _p(
    'motion.content-change.type',
    'choice',
    'The map form\'s kind; a kind of the app\'s own too.',
    defaultValue: 'none',
    values: ['none', 'fade', 'fade-up', 'morph'],
  ),
  _p(
    'motion.content-change.duration',
    'duration',
    'How long the change takes; for `morph`, the whole page.',
    defaultValue: '200ms',
  ),
  _p(
    'motion.content-change.curve',
    'curve',
    'The curve of the change.',
    defaultValue: 'ease-out',
  ),
  _p(
    'motion.content-change.stagger',
    'duration',
    'For `morph`: how much later each line starts than the one before it; '
        'the starts take at most 85 percent of the duration.',
    defaultValue: '30ms',
  ),
  _p(
    'motion.content-change.delay',
    'duration',
    'For `morph`: how long the new page waits, blank at its full height, '
        'before its first line (the duration of `text-change`, so a text '
        'above it morphs first).',
    defaultValue: '0ms',
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
      'The picture: an asset path, an https URL or a '
          '`github:owner/repo/path@ref` address (`http` only with '
          '`spring.remote.allow-insecure`). Required.',
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
      '$root.image.repeat',
      'choice',
      'Tiles the picture over the screen, at its own size with `fit: none`: '
          'a small texture such as grain.',
      values: const ['no-repeat', 'repeat', 'repeat-x', 'repeat-y'],
      defaultValue: 'no-repeat',
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
    _p(
      '$root.frame-rate',
      'text',
      'How many times a second the moving image is drawn again: a number, '
          'or `every-frame`.',
      defaultValue: '15',
    ),
  ];
  return [
    ...keys('background', 'of every screen'),
    ...keys('background.screens.*', 'of this screen'),
  ];
}

// The loaders and the splash: docs/flutter/theme/loaders.md.
List<ThemeProp> _loaders() => [
  _p(
    'loaders.*.kind',
    'choice',
    'What the loader looks like: a built-in kind, or a kind of the app\'s '
        'own (`@ThemeLoaderKind`). Required. An unknown kind stops the '
        'start.',
    values: ['spinner', 'dots', 'pulse', 'bar', 'skeleton'],
  ),
  _p(
    'loaders.*.color',
    'color',
    'The color of the moving part (spinner, dots, pulse, bar).',
    defaultValue: "the theme's `primary`",
  ),
  _p(
    'loaders.*.size',
    'number',
    'The diameter of a spinner or pulse, the size of one dot.',
    defaultValue: '24 (spinner, pulse), 8 (dots)',
  ),
  _p(
    'loaders.*.stroke',
    'number',
    'The line width of a spinner.',
    defaultValue: '3',
  ),
  _p(
    'loaders.*.track',
    'color',
    'The color of the track behind a spinner or bar.',
    defaultValue: 'none (spinner), the color at 20 % (bar)',
  ),
  _p(
    'loaders.*.count',
    'number',
    'The number of dots, a whole number of 1 or more.',
    defaultValue: '3',
  ),
  _p(
    'loaders.*.gap',
    'number',
    'The space between dots.',
    defaultValue: 'half the dot size',
  ),
  _p(
    'loaders.*.height',
    'number',
    'The thickness of a bar.',
    defaultValue: '4',
  ),
  _p(
    'loaders.*.width',
    'number',
    'The length of a bar.',
    defaultValue: '120',
  ),
  _p(
    'loaders.*.radius',
    'number',
    'The corner radius of a bar or a skeleton.',
    defaultValue: 'half the height (bar), 8 (skeleton)',
  ),
  _p(
    'loaders.*.base',
    'color',
    'The color of a skeleton.',
    defaultValue: '#E0E0E0',
  ),
  _p(
    'loaders.*.highlight',
    'color',
    'The color of the highlight that crosses a skeleton.',
    defaultValue: '#F5F5F5',
  ),
  _p(
    'loaders.*.shimmer.duration',
    'duration',
    'How long the highlight takes to cross a skeleton.',
    defaultValue: '1.2s',
  ),
  _p(
    'loaders.*.shimmer.curve',
    'text',
    'The curve of the highlight: a name or four numbers.',
    defaultValue: 'linear',
  ),
  _p(
    'loaders.*.shimmer.angle',
    'number',
    'The slant of the highlight in degrees.',
    defaultValue: '20',
  ),
  _p(
    'loaders.*.animation.duration',
    'duration',
    'How long one run of a built-in loader takes. `animation` may also be '
        'the name of an `animations.<name>`.',
    defaultValue: 'per kind: 1s, 900ms, 1.2s, 1.4s',
  ),
  _p(
    'loaders.*.animation.curve',
    'text',
    'The curve of the run: a name or four numbers.',
    defaultValue: 'per kind',
  ),
  _p(
    'loaders.*.animation.repeat',
    'choice',
    'What happens at the end of a run.',
    defaultValue: 'loop (back and forth for pulse)',
    values: ['none', 'loop', 'reverse'],
  ),
  _p(
    'loaders.*.phases.*.duration',
    'duration',
    'A kind of the app\'s own: how long the phase takes. Phases play in '
        'the order written.',
  ),
  _p(
    'loaders.*.phases.*.curve',
    'text',
    'The curve of the phase: a name or four numbers.',
    defaultValue: 'linear',
  ),
  _p(
    'loaders.*.phases.*.repeat',
    'choice',
    'A looping phase goes on until the loader is ready.',
    defaultValue: 'none',
    values: ['none', 'loop', 'reverse'],
  ),
  _p(
    'loaders.*.phases.*.progress',
    'true / false',
    'A phase that follows the progress the loader is given (`true`).',
  ),
  _p(
    'loaders.*.phases.*.min-duration',
    'duration',
    'A phase that follows progress fills in no less than this: it shows '
        'the smaller of the real progress and the time in the phase (eased) '
        'over this, so a fast start does not jump to the end.',
    defaultValue: '0',
  ),
  _p(
    'loaders.*.web',
    'text',
    'A kind of the app\'s own: the HTML that shows it before Flutter runs '
        '(the web page loader). A path below `lib/resources/` (the app\'s or '
        "a package's), or an address the build downloads: `https://...` or "
        '`github:owner/repo/path@ref`.',
  ),
  _p(
    'loaders.*.web-sha256',
    'text',
    'For a downloaded `web`: the SHA-256 (64 hexadecimal digits) the file '
        'must have; another file is refused.',
    defaultValue: 'none',
  ),
  _p(
    'loaders.*.tracks.*.follows',
    'text',
    'What the track (a value from 0 to 1 a loader reads each frame) '
        'follows: `time` (the clock), `stage` (from a stage of the start '
        'on), `progress` (the start\'s progress, smoothed), or a driver of '
        'the app\'s own (`LoaderTrackDrivers.register`).',
    defaultValue: 'time',
  ),
  _p(
    'loaders.*.tracks.*.duration',
    'duration',
    'A time or stage track: how long one run takes.',
  ),
  _p(
    'loaders.*.tracks.*.curve',
    'text',
    'The curve of the track: a name or four numbers.',
    defaultValue: 'linear',
  ),
  _p(
    'loaders.*.tracks.*.repeat',
    'choice',
    'A time or stage track: once, looping, or back and forth.',
    defaultValue: 'none',
    values: ['none', 'loop', 'reverse'],
  ),
  _p(
    'loaders.*.tracks.*.delay',
    'duration',
    'A time or stage track: how long it waits before it starts.',
    defaultValue: '0',
  ),
  _p(
    'loaders.*.tracks.*.from',
    'choice',
    'A stage track: the stage it starts at.',
    values: ['page', 'engine', 'splash', 'starting', 'ready', 'exit', 'app'],
  ),
  _p(
    'loaders.*.tracks.*.smoothing',
    'duration',
    'A progress track: how fast it catches up with the progress (a time '
        'constant), so it never jumps.',
    defaultValue: '300ms',
  ),
  _p(
    'loaders.*.tracks.*.*',
    'text',
    'A track of a driver of the app\'s own takes the keys it declares.',
    open: true,
  ),
  _p(
    'loaders.*.*',
    'map',
    'A kind of the app\'s own takes the keys it registered; their values '
        'are read like tokens.',
    open: true,
  ),
];

// The look of the frame meter (spring.flutter.frame-meter.enabled).
List<ThemeProp> _frameMeter() => [
  for (final (key, meaning, fallback) in [
    ('background', "The meter's fill.", 'the surface at 85%'),
    ('foreground', 'The text.', 'on-surface'),
    ('good', 'A frame within the budget.', 'primary'),
    ('warning', 'A frame up to twice the budget.', 'tertiary'),
    ('bad', 'A frame over twice the budget.', 'error'),
  ])
    _p('frame-meter.$key', 'color', meaning, defaultValue: fallback),
  _p(
    'frame-meter.text-style',
    'text',
    'The typography style of the text: `label-small`, `body-medium`... or '
        '`code`.',
    defaultValue: 'label-small',
  ),
];

List<ThemeProp> _splash() => [
  ..._background()
      .where(
        (p) =>
            !(p['name'] as String).contains('.screens.') &&
            (p['name'] as String).startsWith('background.'),
      )
      .map(
        (p) => {
          ...p,
          'name': (p['name'] as String).replaceFirst(
            'background.',
            'splash.background.',
          ),
        },
      ),
  _p(
    'splash.logo.source',
    'text',
    'The logo: an asset path or an https URL. It takes the other image '
        'keys of `background.image` (`refresh`, `fallback`, ...).',
  ),
  _p(
    'splash.logo.size',
    'number',
    'The width of the logo.',
    defaultValue: '96',
  ),
  _p('splash.title', 'text', 'The text under the logo.'),
  _p(
    'splash.loader',
    'text',
    'The name of a `loaders.<name>` shown under the title; a kind of the '
        "app's own may cover the whole splash.",
  ),
  _p(
    'splash.animation',
    'text',
    'The name of an `animations.<name>` that fades and grows the logo.',
  ),
  _p(
    'splash.min-duration',
    'duration',
    'The splash stays at least this long, even when the app is ready.',
    defaultValue: '0',
  ),
  _p(
    'splash.exit.transition',
    'text',
    'The fade out when the app is ready: `<duration> [<curve>]`.',
    defaultValue: '300ms ease-out',
  ),
  _p(
    'splash.exit.reveal',
    'true / false',
    'When the last phase of a loader with phases of its own starts, the '
        'background, the logo and the title go at once: the loader plays '
        'its way out over the app, which is built under the splash.',
    defaultValue: 'false',
  ),
];
