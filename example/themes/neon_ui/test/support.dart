import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_ui/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// An app of type `widgets` with the NEON theme imported from the library,
/// as an application imports it. [extra] adds properties (a theme of the
/// test's own, for example).
SpringApplication neonApplication([Map<String, String> extra = const {}]) =>
    SpringApplication(
      [
        BeanModule(
          'test',
          const [],
          resources: {
            'application.properties': EmbeddedResource.text(
              [
                'spring.flutter.app.type=widgets',
                'spring.config.import=resources:themes/neon.yml',
                'spring.flutter.theme.active=neon',
                for (final MapEntry(:key, :value) in extra.entries)
                  '$key=$value',
              ].join('\n'),
            ),
          },
        ),
      ],
      autoConfigurations: [
        springBootStarterFlutterAutoConfiguration,
        neonUiAutoConfiguration,
      ],
      bannerMode: BannerMode.off,
    );

/// Shows [child] in the middle of a NEON app; the fonts are the package's.
Future<void> pumpNeon(
  WidgetTester tester,
  Widget child, {
  Map<String, String> properties = const {},
  Size size = const Size(800, 600),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => neonApplication(properties),
      home: Center(child: child),
    ),
  );
  // Fonts and the background image are read for real.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The decoration of the first box under [of].
BoxDecoration decorationOf(WidgetTester tester, Finder of) =>
    tester
            .widget<Container>(
              find.descendant(of: of, matching: find.byType(Container)).first,
            )
            .decoration!
        as BoxDecoration;

/// Moves the mouse over [target] and lets the hover and the 120 ms
/// transition of the style finish (the hover shows one frame after the move).
Future<void> hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
