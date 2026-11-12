// The starter's beans, and its design among the factories of the
// application: the themes are read with it before any bean exists.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, hasSingleBean;

import 'support/application.dart';
import 'support/themes.dart';

final class _Compact implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) =>
      theme.copyWith(visualDensity: VisualDensity.compact);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterMaterialAutoConfiguration)
      .withBean<SpringFactories>(
        () => const SpringFactories([MaterialThemeDesign()]),
      );

  test('the themes, the app widget and the page routes', () {
    runner.run((assertable) {
      expect(assertable.startupFailure, isNull);
      expect(assertable, hasSingleBean<MaterialThemes>());
      expect(assertable, hasSingleBean<MaterialAppFactory>());
      expect(assertable, hasSingleBean<MaterialPageRoutes>());
      final context = assertable.context;
      expect(context.getBeanByName('materialThemes'), isA<MaterialThemes>());
      expect(
        context.getBeanByName('materialAppFactory'),
        isA<MaterialAppFactory>(),
      );
      expect(
        context.getBeanByName('materialPageRoutes'),
        isA<MaterialPageRoutes>(),
      );
      expect(
        SpringAppFactories.of(context).named('Material'),
        same(context.getBean<MaterialAppFactory>()),
      );
      expect(
        context.getBeansOfType<DesignPageRoutes>().values,
        contains(context.getBean<MaterialPageRoutes>()),
      );
      final material = context.getBean<MaterialThemes>();
      expect(MaterialThemes.of(context), same(material));
      expect(material.themes, same(context.getBean<SpringThemes>()));
    });
  });

  test(
    'the ThemeCustomizer beans and the ThemeData beans reach the themes',
    () {
      final light = ThemeData(colorSchemeSeed: Colors.teal);
      runner
          .withBean<ThemeCustomizer>(_Compact.new)
          .withBean<ThemeData>(() => light, name: 'theme')
          .withPropertyValues([
            'spring.flutter.theme.themes.ocean.seed-color=teal',
          ])
          .run((context) {
            expect(context.startupFailure, isNull);
            final material = context.getBean<MaterialThemes>();
            expect(material.customizers, hasLength(1));
            expect(material.theme('light').colorScheme, light.colorScheme);
            expect(
              material.theme('light').visualDensity,
              VisualDensity.compact,
            );
            expect(
              material.theme('ocean').visualDensity,
              VisualDensity.compact,
            );
            expect(
              material.theme('dark').colorScheme,
              ThemeData(brightness: Brightness.dark).colorScheme,
            );
          });
    },
  );

  test('an application: the design of the module\'s factories reads the '
      'themes', () async {
    final app = application(
      properties: {
        'spring.flutter.app.type': 'material',
        'spring.flutter.theme.seed-color': 'teal',
        'spring.flutter.theme.components.card.elevation': '2',
      },
    );
    expect(app.factories.load<ThemeDesign>(), [isA<MaterialThemeDesign>()]);
    final context = await app.runAsync(const []);
    addTearDown(context.close);
    final themes = context.getBean<SpringThemes>();
    expect(themes.designs.own, isA<MaterialThemeDesign>());
    expect(
      context.getBean<MaterialThemes>().theme('light').cardTheme.elevation,
      2,
    );
  });

  test('without the starter\'s design a component is accepted, not checked, '
      'and named with the starter that reads it', () {
    // A wrong value too: nothing reads it in an app without the starter.
    final light = SpringThemes(const {
      'components.card.elevation': 'high',
      'visual-density': 'compact',
      'splash': 'sparkle',
    }).data('light');
    expect(light.unreadDesignProperties, {
      'components': 'spring_boot_starter_flutter_material',
      'visual-density': 'spring_boot_starter_flutter_material',
      'splash': 'spring_boot_starter_flutter_material',
    });
    // With the design the same value fails the start.
    expect(
      () => themes(const {'components.card.elevation': 'high'}),
      throwsA(isA<ThemePropertyException>()),
    );
  });
}
