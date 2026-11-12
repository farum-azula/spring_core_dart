// The example app as generated (example/spring_gen/example.spring.dart):
// a CupertinoApp from the properties, the palette's roles in Cupertino's
// theme, the customizer bean and the switch between the themes.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

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

    final app = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(app.title, 'Themes');
    CupertinoThemeData shown() =>
        CupertinoTheme.of(tester.element(find.byType(ThemePage)));
    expect(shown().brightness, Brightness.light);
    expect(shown().primaryColor, const Color(0xFF007AFF));
    expect(shown().barBackgroundColor, const Color(0xF0F9F9F9));
    expect(shown().scaffoldBackgroundColor, const Color(0xFFF2F2F7));
    // The customizer bean, on every theme: white on iOS blue.
    expect(shown().primaryContrastingColor, CupertinoColors.white);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(shown().brightness, Brightness.dark);
    expect(shown().primaryColor, const Color(0xFF0A84FF));
    expect(shown().barBackgroundColor, const Color(0xF01D1D1F));
    expect(shown().primaryContrastingColor, CupertinoColors.white);
    expect(find.text('Light'), findsOneWidget);
  });
}
