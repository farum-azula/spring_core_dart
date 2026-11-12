// ThemeDesigns, what the design libraries of an application add to its
// themes, with designs of the test's own: which design is the app's, the
// order they are asked in, the palette of a seed, their theme properties,
// their page transitions and their check of every theme.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

// A design library of the test. Its palettes have the seed as primary and
// the design's own [mark] as tertiary, so a palette tells who made it.
final class _Design implements ThemeDesign {
  _Design(
    this.appType, {
    required this.mark,
    this.themeProperties = const [],
    this.schemeVariants = const [],
    this.transitions = const {},
    this.onCheck,
  });

  @override
  final String appType;

  final Color mark;

  @override
  final List<String> themeProperties;

  @override
  final List<String> schemeVariants;

  final Map<PageTransitionType, PageTransitionsBuilder> transitions;

  final void Function(SpringThemeData theme)? onCheck;

  final specs = <ColorSchemeSpec>[];
  final checked = <String>[];

  @override
  SpringColorScheme colorScheme(ColorSchemeSpec spec) {
    specs.add(spec);
    return SpringColorScheme.baseline(spec.brightness).withRoles({
      'primary': ?spec.seedColor,
      'tertiary': mark,
    });
  }

  @override
  PageTransitionsBuilder? pageTransition(PageTransitionType type) =>
      transitions[type];

  @override
  void check(SpringThemeData theme) {
    checked.add(theme.name);
    onCheck?.call(theme);
  }
}

const _oceanMark = Color(0xFF0000AA);
const _sandMark = Color(0xFFAAAA00);

_Design _ocean({void Function(SpringThemeData theme)? onCheck}) => _Design(
  'ocean',
  mark: _oceanMark,
  themeProperties: const ['waves', 'tide-height'],
  schemeVariants: const ['deepSea', 'lagoon'],
  transitions: const {PageTransitionType.zoom: _Named('ocean zoom')},
  onCheck: onCheck,
);

_Design _sand() => _Design(
  'sand',
  mark: _sandMark,
  themeProperties: const ['dunes', 'components'],
  schemeVariants: const ['lagoon', 'dry'],
  transitions: const {
    PageTransitionType.zoom: _Named('sand zoom'),
    PageTransitionType.cupertino: _Named('sand slide'),
  },
);

final class _Named extends PageTransitionsBuilder {
  const _Named(this.name);

  final String name;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

const _spec = ColorSchemeSpec(
  brightness: Brightness.light,
  seedColor: Color(0xFF123456),
);

Matcher _named(String name) =>
    isA<_Named>().having((builder) => builder.name, 'name', name);

void main() {
  group('the design of the app', () {
    test('none: no design, an app of type widgets', () {
      expect(ThemeDesigns.none.all, isEmpty);
      expect(ThemeDesigns.none.appType, 'widgets');
      expect(ThemeDesigns.none.own, isNull);
      expect(ThemeDesigns.none.themeProperties, isEmpty);
      expect(const ThemeDesigns().appType, 'widgets');
    });

    test('own: the design of the app type, in any spelling', () {
      final ocean = _ocean();
      final sand = _sand();
      ThemeDesign? own(String appType) =>
          ThemeDesigns(all: [ocean, sand], appType: appType).own;
      expect(own('ocean'), same(ocean));
      expect(own('sand'), same(sand));
      expect(own('Ocean'), same(ocean));
      expect(own('SAND'), same(sand));
      expect(own('o-cean'), same(ocean));
      // Designs in the application, an app of another type.
      expect(own('widgets'), isNull);
      expect(own('lava'), isNull);
      expect(ThemeDesigns(all: [ocean, sand]).own, isNull);
    });
  });

  group('the palette', () {
    test('nothing set: the baseline, and no design is asked', () {
      final ocean = _ocean();
      final designs = ThemeDesigns(all: [ocean], appType: 'ocean');
      for (final brightness in Brightness.values) {
        final spec = ColorSchemeSpec(brightness: brightness);
        expect(spec.isBaseline, isTrue);
        expect(
          designs.colorScheme(spec, property: 'p', value: 'v'),
          same(SpringColorScheme.baseline(brightness)),
        );
      }
      expect(ocean.specs, isEmpty);
    });

    test('a seed, a variant or a contrast alone makes it a design\'s', () {
      expect(_spec.isBaseline, isFalse);
      expect(
        const ColorSchemeSpec(
          brightness: Brightness.dark,
          schemeVariant: 'lagoon',
        ).isBaseline,
        isFalse,
      );
      expect(
        const ColorSchemeSpec(
          brightness: Brightness.dark,
          contrast: 0,
        ).isBaseline,
        isFalse,
      );
    });

    test('the app\'s own design makes it, wherever it is in the list', () {
      final ocean = _ocean();
      final sand = _sand();
      SpringColorScheme made(String appType, List<ThemeDesign> all) =>
          ThemeDesigns(
            all: all,
            appType: appType,
          ).colorScheme(_spec, property: 'p', value: 'v');
      expect(made('sand', [ocean, sand]).tertiary, _sandMark);
      expect(made('ocean', [ocean, sand]).tertiary, _oceanMark);
      final last = made('ocean', [sand, ocean]);
      expect(last.tertiary, _oceanMark);
      expect(last.primary, const Color(0xFF123456));
      expect(ocean.specs, [_spec, _spec]);
      expect(sand.specs, [_spec]);
    });

    test('an app of another type: the first design of the application', () {
      final ocean = _ocean();
      final sand = _sand();
      for (final appType in ['widgets', 'lava']) {
        expect(
          ThemeDesigns(
            all: [sand, ocean],
            appType: appType,
          ).colorScheme(_spec, property: 'p', value: 'v').tertiary,
          _sandMark,
          reason: appType,
        );
      }
      expect(ocean.specs, isEmpty);
    });

    test('no design: the property and its value, and what to add', () {
      expect(
        () => ThemeDesigns.none.colorScheme(
          _spec,
          property: 'spring.flutter.theme.seedcolor',
          value: '#123456',
        ),
        throwsA(
          isA<ThemePropertyException>()
              .having((e) => e.key, 'key', 'spring.flutter.theme.seedcolor')
              .having((e) => e.value, 'value', '#123456')
              .having(
                (e) => e.expected,
                'expected',
                allOf(
                  contains('a design starter in the dependencies'),
                  contains('spring_boot_starter_flutter_material'),
                  contains('spring_boot_starter_flutter_cupertino'),
                ),
              ),
        ),
      );
    });
  });

  group('scheme variants', () {
    test('as the design names it, the app\'s own design asked first', () {
      final ocean = _ocean();
      final sand = _sand();
      final designs = ThemeDesigns(all: [ocean, sand], appType: 'sand');
      expect(designs.schemeVariant('deep-sea'), 'deepSea');
      expect(designs.schemeVariant('DEEP_SEA'), 'deepSea');
      expect(designs.schemeVariant('deepsea'), 'deepSea');
      expect(designs.schemeVariant('dry'), 'dry');
      expect(designs.schemeVariant('lagoon'), 'lagoon');
      expect(designs.schemeVariant('swamp'), isNull);
      // For the message: sand's first, each once.
      expect(designs.schemeVariants, 'lagoon, dry, deepSea');
      expect(
        ThemeDesigns(all: [ocean, sand], appType: 'ocean').schemeVariants,
        'deepSea, lagoon, dry',
      );
      expect(
        ThemeDesigns(all: [ocean, sand]).schemeVariants,
        'deepSea, lagoon, dry',
      );
    });

    test('no design: no variant, and what to add in their place', () {
      expect(ThemeDesigns.none.schemeVariant('tonalSpot'), isNull);
      expect(
        ThemeDesigns.none.schemeVariants,
        contains('a design starter in the dependencies'),
      );
    });
  });

  group('theme properties', () {
    test('those of every design, by canonical name', () {
      final designs = ThemeDesigns(all: [_ocean(), _sand()]);
      expect(designs.themeProperties, {
        'waves',
        'tideheight',
        'dunes',
        'components',
      });
      for (final name in [
        'waves',
        'tide-height',
        'tideHeight',
        'TIDE_HEIGHT',
        'dunes',
        'components',
      ]) {
        expect(designs.reads(name), isTrue, reason: name);
      }
      expect(designs.reads('cupertino'), isFalse);
      expect(designs.reads('colors'), isFalse);
      expect(ThemeDesigns.none.reads('components'), isFalse);
    });

    test('those of the family\'s starters, and which of them go unread', () {
      expect(ThemeDesigns.familyProperties, {
        'components',
        'visualdensity',
        'taptargetsize',
        'splash',
        'cupertino',
      });
      // Asked by canonical name, listed by the name as written.
      const names = [
        'components',
        'visualdensity',
        'taptargetsize',
        'splash',
        'cupertino',
        'colors',
      ];
      expect(ThemeDesigns.none.unread(names), {
        'components': 'spring_boot_starter_flutter_material',
        'visual-density': 'spring_boot_starter_flutter_material',
        'tap-target-size': 'spring_boot_starter_flutter_material',
        'splash': 'spring_boot_starter_flutter_material',
        'cupertino': 'spring_boot_starter_flutter_cupertino',
      });
      // A design of the application reads components: read, not listed.
      expect(ThemeDesigns(all: [_sand()]).unread(names), {
        'visual-density': 'spring_boot_starter_flutter_material',
        'tap-target-size': 'spring_boot_starter_flutter_material',
        'splash': 'spring_boot_starter_flutter_material',
        'cupertino': 'spring_boot_starter_flutter_cupertino',
      });
      expect(ThemeDesigns.none.unread(const ['colors', 'waves']), isEmpty);
    });

    test('starterOf: what to add, for a message; nothing for the rest', () {
      expect(
        ThemeDesigns.starterOf('visual-density'),
        ' (visual-density is read by spring_boot_starter_flutter_material: '
        'add it to the dependencies)',
      );
      expect(
        ThemeDesigns.starterOf('cupertino'),
        contains('spring_boot_starter_flutter_cupertino'),
      );
      expect(ThemeDesigns.starterOf('waves'), isEmpty);
      expect(ThemeDesigns.starterOf('colors'), isEmpty);
    });
  });

  group('page transitions', () {
    test('the first design that has it, the app\'s own first', () {
      final ocean = _ocean();
      final sand = _sand();
      ThemeDesigns of(String appType) =>
          ThemeDesigns(all: [ocean, sand], appType: appType);
      expect(
        of('ocean').pageTransition(PageTransitionType.zoom),
        _named('ocean zoom'),
      );
      expect(
        of('sand').pageTransition(PageTransitionType.zoom),
        _named('sand zoom'),
      );
      expect(
        of('widgets').pageTransition(PageTransitionType.zoom),
        _named('ocean zoom'),
      );
      // Not the app's own design's: another design of the application's.
      expect(
        of('ocean').pageTransition(PageTransitionType.cupertino),
        _named('sand slide'),
      );
      expect(of('ocean').pageTransition(PageTransitionType.fade), isNull);
      expect(
        ThemeDesigns.none.pageTransition(PageTransitionType.zoom),
        isNull,
      );
    });
  });

  group('themes read with designs', () {
    test('the palette of the seed, the roles of colors over it; a theme '
        'has the seed of the shared part or its own', () {
      final ocean = _ocean();
      final themes = SpringThemes(
        const {
          'seed-color': '#112233',
          'scheme-variant': 'deep-sea',
          'contrast': '0.5',
          'colors.secondary': '#445566',
          'themes.night.brightness': 'dark',
          'themes.night.seed-color': '#AA0000',
          'themes.night.scheme-variant': 'LAGOON',
        },
        designs: ThemeDesigns(all: [ocean], appType: 'ocean'),
      );
      final light = themes.data('light');
      expect(light.designs.own, same(ocean));
      expect(light.seedColor, const Color(0xFF112233));
      expect(light.schemeVariant, 'deepSea');
      expect(light.contrast, 0.5);
      expect(light.colorScheme.primary, const Color(0xFF112233));
      expect(light.colorScheme.tertiary, _oceanMark);
      expect(light.colorScheme.secondary, const Color(0xFF445566));
      expect(light.colorScheme.brightness, Brightness.light);

      final night = themes.data('night');
      expect(night.schemeVariant, 'lagoon');
      expect(night.colorScheme.primary, const Color(0xFFAA0000));
      expect(night.colorScheme.secondary, const Color(0xFF445566));
      expect(
        night.colorScheme.surface,
        SpringColorScheme.baseline(Brightness.dark).surface,
      );

      // What the design was asked for, a palette per theme, once.
      expect(
        {
          for (final spec in ocean.specs)
            (
              spec.brightness,
              spec.seedColor,
              spec.schemeVariant,
              spec.contrast,
            ),
        },
        {
          (Brightness.light, const Color(0xFF112233), 'deepSea', 0.5),
          (Brightness.dark, const Color(0xFF112233), 'deepSea', 0.5),
          (Brightness.dark, const Color(0xFFAA0000), 'lagoon', 0.5),
        },
      );
      expect(ocean.specs, hasLength(3));
      light.colorScheme;
      expect(ocean.specs, hasLength(3));
    });

    test('a variant no design has names those there are', () {
      expect(
        () => SpringThemes(
          const {'scheme-variant': 'swamp'},
          designs: ThemeDesigns(all: [_ocean(), _sand()], appType: 'sand'),
        ),
        throwsA(
          isA<ThemePropertyException>()
              .having(
                (e) => e.key,
                'key',
                'spring.flutter.theme.schemevariant (theme light)',
              )
              .having((e) => e.value, 'value', 'swamp')
              .having((e) => e.expected, 'expected', 'lagoon, dry, deepSea'),
        ),
      );
    });

    test('a design\'s own properties are theme properties with it, and '
        'unknown keys without', () {
      final designs = ThemeDesigns(all: [_ocean()], appType: 'ocean');
      final theme = SpringThemes(const {
        'waves.height': '3',
        'tide-height': '2',
        'themes.storm.waves.height': '9',
      }, designs: designs).data('storm');
      expect(theme.properties['waves.height'], '9');
      expect(theme.properties['tideheight'], '2');
      expect(theme.unreadDesignProperties, isEmpty);

      expect(
        () => SpringThemes(const {'waves.height': '3'}),
        throwsA(
          isA<ThemePropertyException>()
              .having(
                (e) => e.key,
                'key',
                'spring.flutter.theme.waves.height (theme light)',
              )
              .having(
                (e) => e.expected,
                'expected',
                allOf(
                  startsWith('a theme property: brightness, seed-color'),
                  isNot(contains('waves')),
                ),
              ),
        ),
      );
      // The message lists the designs' properties with the starter's own.
      expect(
        () => SpringThemes(const {'wavs.height': '3'}, designs: designs),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            endsWith('frame-meter, waves, tide-height'),
          ),
        ),
      );
    });

    test('a design that reads components: read, not among the unread', () {
      final sand = _sand();
      final theme = SpringThemes(
        const {
          'components.card.shape': 'large',
          'visual-density': 'compact',
          'cupertino.primary-color': '#0057B8',
        },
        designs: ThemeDesigns(all: [sand], appType: 'sand'),
      ).data('light');
      expect(theme.unreadDesignProperties, {
        'visual-density': 'spring_boot_starter_flutter_material',
        'cupertino': 'spring_boot_starter_flutter_cupertino',
      });
      expect(sand.checked, ['light', 'dark']);
    });

    test('zoom and cupertino are the designs\' builders', () {
      final designs = ThemeDesigns(all: [_ocean(), _sand()], appType: 'ocean');
      SpringThemeData read(String type) => SpringThemes({
        'motion.page-transition': type,
      }, designs: designs).data('light');
      expect(read('zoom').pageTransition, _named('ocean zoom'));
      expect(read('cupertino').pageTransition, _named('sand slide'));
      expect(read('zoom').pageTransitions.type, PageTransitionType.zoom);
      // A design without the transition: the start fails as with none.
      expect(
        () => SpringThemes(
          const {'motion.page-transition': 'cupertino'},
          designs: ThemeDesigns(all: [_ocean()], appType: 'ocean'),
        ),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains('spring_boot_starter_flutter_cupertino'),
          ),
        ),
      );
    });
  });

  group('check', () {
    test('every design reads every theme at the start, in the order of '
        'the application', () {
      final log = <String>[];
      final ocean = _Design(
        'ocean',
        mark: _oceanMark,
        onCheck: (theme) => log.add('ocean ${theme.name}'),
      );
      final sand = _Design(
        'sand',
        mark: _sandMark,
        onCheck: (theme) => log.add('sand ${theme.name}'),
      );
      // The app's own design is not first here: each checks its part.
      final themes = SpringThemes(
        const {'themes.storm.brightness': 'dark'},
        designs: ThemeDesigns(all: [sand, ocean], appType: 'ocean'),
      );
      expect(log, [
        'sand light',
        'ocean light',
        'sand dark',
        'ocean dark',
        'sand storm',
        'ocean storm',
      ]);
      // Once: a theme read is not checked again.
      themes
        ..data('storm')
        ..data('light');
      expect(log, hasLength(6));
    });

    test('the theme is whole when it is checked', () {
      SpringThemeData? seen;
      SpringThemes(
        const {
          'colors.primary': '#112233',
          'spacing.m': '18',
          'waves.height': '3',
        },
        designs: ThemeDesigns(
          all: [
            _ocean(
              onCheck: (theme) {
                if (theme.name == 'light') {
                  seen = theme;
                  expect(theme.colorScheme.primary, const Color(0xFF112233));
                  expect(theme.space('m'), 18);
                  expect(theme.properties['waves.height'], '3');
                  expect(theme.unreadDesignProperties, isEmpty);
                }
              },
            ),
          ],
        ),
      );
      expect(seen, isNotNull);
    });

    test('a wrong value of a design fails the start, and a load changes '
        'nothing', () {
      void check(SpringThemeData theme) {
        final height = theme.properties['waves.height'];
        if (height != null && double.tryParse(height) == null) {
          throw ThemePropertyException(
            theme.properties.propertyName('waves.height'),
            height,
            'a number',
          );
        }
      }

      ThemeDesigns designs() => ThemeDesigns(
        all: [_ocean(onCheck: check)],
        appType: 'ocean',
      );
      Matcher wrong(String key) => throwsA(
        isA<ThemePropertyException>()
            .having((e) => e.key, 'key', key)
            .having((e) => e.value, 'value', 'high')
            .having((e) => e.expected, 'expected', 'a number'),
      );
      expect(
        () => SpringThemes(const {'waves.height': 'high'}, designs: designs()),
        wrong('spring.flutter.theme.waves.height (theme light)'),
      );
      expect(
        () => SpringThemes(const {
          'themes.storm.waves.height': 'high',
        }, designs: designs()),
        wrong('spring.flutter.theme.themes.storm.waves.height'),
      );

      final themes = SpringThemes(const {
        'waves.height': '3',
      }, designs: designs());
      final before = themes.data('light');
      var notified = 0;
      themes.addListener(() => notified++);
      expect(
        () => themes.load(const {'themes.storm.waves.height': 'high'}),
        wrong('spring.flutter.theme.themes.storm.waves.height'),
      );
      expect(themes.names, ['light', 'dark']);
      expect(themes.data('light'), same(before));
      expect(notified, 0);
      themes.load(const {'themes.storm.waves.height': '7'});
      expect(themes.data('storm').properties['waves.height'], '7');
      expect(notified, 1);
    });
  });

  group('the designs of an application', () {
    test('of: the ThemeDesigns among the factories, the app type of the '
        'environment', () {
      final ocean = _ocean();
      final sand = _sand();
      StandardEnvironment env(Map<String, String> properties) =>
          StandardEnvironment()
            ..propertySources.addFirst(MapPropertySource('test', properties));
      final designs = ThemeDesigns.of(
        SpringFactories([ocean, 'not a design', sand]),
        env({'spring.flutter.app.type': ' sand '}),
      );
      expect(designs.all, [ocean, sand]);
      expect(designs.appType, 'sand');
      expect(designs.own, same(sand));

      final plain = ThemeDesigns.of(const SpringFactories(), env({}));
      expect(plain.all, isEmpty);
      expect(plain.appType, isNull);
      expect(plain.own, isNull);

      // The type not set: the one design is the app's own; of several,
      // none is.
      final single = ThemeDesigns.of(SpringFactories([ocean]), env({}));
      expect(single.appType, isNull);
      expect(single.own, same(ocean));
      final several = ThemeDesigns.of(
        SpringFactories([ocean, sand]),
        env({'spring.flutter.app.type': ' '}),
      );
      expect(several.appType, isNull);
      expect(several.own, isNull);
    });

    // An application as the generator writes it for a starter with a
    // design among the factories of its module.
    SpringApplication application(
      _Design design, {
      bool autoConfiguration = false,
    }) {
      final starter = BeanModule('oceanAutoConfiguration', const []);
      return SpringApplication(
        [
          BeanModule(
            'test',
            const [],
            resources: {
              'application.properties': const EmbeddedResource.text(
                'spring.flutter.app.type=ocean\n'
                'spring.flutter.theme.remember=false\n'
                'spring.flutter.theme.seed-color=#112233\n'
                'spring.flutter.theme.waves.height=3\n'
                'logging.level.root=WARN',
              ),
            },
          ),
        ],
        autoConfigurations: [
          if (autoConfiguration) springBootStarterFlutterAutoConfiguration,
          starter,
        ],
        autoConfigurationMetadata: {
          starter: AutoConfigurationModule(factories: [design]),
        },
        bannerMode: BannerMode.off,
      );
    }

    test('designsOf: those of the application\'s factories', () async {
      final ocean = _ocean();
      final context = await application(ocean).runAsync(const []);
      addTearDown(context.close);
      final designs = SpringThemes.designsOf(context);
      expect(designs.all, [ocean]);
      expect(designs.appType, 'ocean');
      expect(designs.own, same(ocean));
      // The themes of a context without the starter's beans are read
      // with them.
      final themes = SpringThemes.of(context);
      expect(themes.designs.all, [ocean]);
      expect(themes.data('light').colorScheme.tertiary, _oceanMark);
      expect(themes.data('light').colorScheme.primary, const Color(0xFF112233));
    });

    test('the springThemes bean is read with them', () async {
      final ocean = _ocean();
      final context = await application(
        ocean,
        autoConfiguration: true,
      ).runAsync(const []);
      addTearDown(context.close);
      final themes = context.getBean<SpringThemes>();
      expect(themes.designs.all, [ocean]);
      expect(themes.designs.appType, 'ocean');
      expect(themes.data('dark').colorScheme.tertiary, _oceanMark);
      expect(ocean.checked, containsAll(['light', 'dark']));
    });

    test('an application without a design: none', () async {
      final context = await SpringApplication([
        BeanModule('test', const []),
      ], bannerMode: BannerMode.off).runAsync(const []);
      addTearDown(context.close);
      final designs = SpringThemes.designsOf(context);
      expect(designs.all, isEmpty);
      expect(designs.appType, isNull);
      expect(designs.own, isNull);
    });
  });
}
