// The example app as generated (example/spring_gen/example.spring.dart):
// a MaterialApp from the properties, the palette from the seed, the
// components, the customizer bean and the switch between the themes.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

void main() {
  testWidgets('the example: its themes are the properties', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        home: const ThemePage(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Themes');
    final light = Theme.of(tester.element(find.byType(ThemePage)));
    final seeded = ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5));
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, seeded.primary);
    expect(light.cardTheme.elevation, 2);
    expect(light.appBarTheme.centerTitle, isTrue);
    expect(light.appBarTheme.backgroundColor, seeded.primaryContainer);
    // The customizer bean, on every theme.
    expect(light.extension<Brand>()!.accent, seeded.tertiary);

    await tester.tap(find.byTooltip('Dark theme'));
    await tester.pumpAndSettle();
    final dark = Theme.of(tester.element(find.byType(ThemePage)));
    expect(dark.brightness, Brightness.dark);
    expect(
      dark.colorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      ).primary,
    );
    expect(
      dark.extension<Brand>()!.accent,
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      ).tertiary,
    );
    expect(find.byTooltip('Light theme'), findsOneWidget);
  });
}
