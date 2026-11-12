// CupertinoThemes: every theme of the properties as a CupertinoThemeData,
// the customizers, the replacing bean, themes loaded at run time.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, hasSingleBean;

import 'support/themes.dart';

final class Blue implements CupertinoThemeCustomizer {
  @override
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  ) => theme.copyWith(primaryColor: CupertinoColors.activeBlue);
}

final class Logged implements CupertinoThemeCustomizer {
  Logged(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  ) {
    log.add('$name ${spring.name}');
    return theme.copyWith(barBackgroundColor: spring.colorScheme.surface);
  }
}

void main() {
  test('no properties: iOS\'s look, no primary color forced', () {
    final cupertino = CupertinoThemes(themes(const {}));
    expect(cupertino.theme('light').primaryColor, CupertinoColors.systemBlue);
    expect(cupertino.theme('dark').brightness, Brightness.dark);
  });

  test('the theme of the properties, made once, by any spelling', () {
    final spring = themes(const {
      'themes.ocean.cupertino.primary-color': '#00ACC1',
    });
    final cupertino = CupertinoThemes(spring);
    expect(cupertino.theme('ocean').primaryColor, const Color(0xFF00ACC1));
    expect(cupertino.theme('ocean'), same(spring.data('ocean').toCupertino()));
    expect(cupertino.theme('ocean'), same(cupertino.theme('Ocean')));
    expect(
      cupertino.cupertino(spring.data('ocean')),
      same(cupertino.theme('ocean')),
    );
  });

  test('customizers in order on every theme, once each', () {
    final log = <String>[];
    final spring = themes(const {'themes.ocean.seed-color': 'teal'});
    final cupertino = CupertinoThemes(
      spring,
      customizers: [Logged('first', log), Logged('second', log), Blue()],
    );
    final ocean = cupertino.theme('ocean');
    expect(ocean.primaryColor, CupertinoColors.activeBlue);
    expect(ocean.barBackgroundColor, spring.data('ocean').colorScheme.surface);
    cupertino.theme('ocean');
    expect(log, ['first ocean', 'second ocean']);
    expect(cupertino.theme('ocean'), same(cupertino.theme('Ocean')));
  });

  test('a replacing CupertinoThemeData is every theme, customized too', () {
    const replacing = CupertinoThemeData(
      primaryColor: CupertinoColors.systemPink,
    );
    final spring = themes(const {'themes.ocean.seed-color': 'teal'});
    expect(
      CupertinoThemes(spring, theme: replacing).theme('ocean'),
      replacing,
    );
    expect(
      CupertinoThemes(spring, theme: replacing).theme('light'),
      replacing,
    );
    final customized = CupertinoThemes(
      spring,
      theme: replacing,
      customizers: [Blue()],
    ).theme('ocean');
    expect(customized.primaryColor, CupertinoColors.activeBlue);
  });

  test('an unknown name throws', () {
    expect(
      () => CupertinoThemes(themes(const {})).theme('missing'),
      throwsArgumentError,
    );
  });

  test('themes loaded at run time are made Cupertino again', () {
    final log = <String>[];
    final spring = themes(const {
      'themes.ocean.cupertino.primary-color': '#00ACC1',
    });
    final cupertino = CupertinoThemes(
      spring,
      customizers: [Logged('seen', log)],
    );
    final before = cupertino.theme('ocean');
    expect(before.primaryColor, const Color(0xFF00ACC1));
    spring.load(const {'themes.ocean.cupertino.primary-color': '#FF9500'});
    final after = cupertino.theme('ocean');
    expect(after.primaryColor, const Color(0xFFFF9500));
    expect(cupertino.theme('ocean'), same(after));
    expect(log, ['seen ocean', 'seen ocean']);
  });

  group('the bean', () {
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterFlutterCupertinoAutoConfiguration,
        )
        .withBean<SpringFactories>(
          () => const SpringFactories([CupertinoThemeDesign()]),
        )
        .withPropertyValues([
          'spring.flutter.app.type=cupertino',
          'spring.flutter.theme.cupertino.primary-color=#0057B8',
        ]);

    test('cupertinoThemes, the app factory and the page routes', () async {
      await runner.runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(context, hasSingleBean<CupertinoThemes>());
        expect(context.containsBean('cupertinoThemes'), isTrue);
        expect(
          context.getBean<SpringAppFactory>(),
          isA<CupertinoAppFactory>(),
        );
        expect(context.containsBean('cupertinoAppFactory'), isTrue);
        expect(
          context.getBean<DesignPageRoutes>(),
          isA<CupertinoPageRoutes>(),
        );
        expect(context.containsBean('cupertinoPageRoutes'), isTrue);
        final cupertino = CupertinoThemes.of(context.context);
        expect(cupertino, same(context.getBean<CupertinoThemes>()));
        expect(cupertino.themes, same(context.getBean<SpringThemes>()));
        expect(cupertino.theme('light').primaryColor, const Color(0xFF0057B8));
      });
    });

    test(
      'the customizer beans in order, and the replacing theme bean',
      () async {
        final log = <String>[];
        const replacing = CupertinoThemeData(
          primaryColor: CupertinoColors.systemPink,
        );
        await runner
            .withBean<CupertinoThemeCustomizer>(
              () => Logged('bean', log),
              name: 'logged',
            )
            .withBean<CupertinoThemeData>(() => replacing)
            .runAsync((context) async {
              expect(context.startupFailure, isNull);
              final light = CupertinoThemes.of(context.context).theme('light');
              expect(light.primaryColor, CupertinoColors.systemPink);
              expect(
                light.barBackgroundColor,
                context
                    .getBean<SpringThemes>()
                    .data('light')
                    .colorScheme
                    .surface,
              );
              expect(log, ['bean light']);
            });
      },
    );

    test(
      'a context without the auto-configuration: its themes, once',
      () async {
        await const ApplicationContextRunner()
            .withAutoConfiguration(springBootAutoConfiguration)
            .withBean<SpringFactories>(
              () => const SpringFactories([CupertinoThemeDesign()]),
            )
            .withPropertyValues([
              'spring.flutter.app.type=cupertino',
              'spring.flutter.theme.cupertino.primary-color=#0057B8',
            ])
            .runAsync((context) async {
              expect(context.startupFailure, isNull);
              final cupertino = CupertinoThemes.of(context.context);
              expect(cupertino, same(CupertinoThemes.of(context.context)));
              expect(cupertino.themes, same(SpringThemes.of(context.context)));
              expect(
                cupertino.theme('light').primaryColor,
                const Color(0xFF0057B8),
              );
            });
      },
    );
  });
}
