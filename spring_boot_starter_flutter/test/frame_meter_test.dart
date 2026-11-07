// The frame meter: spring.flutter.frame-meter.* turns it on and puts it
// in a corner; the theme's frame-meter colors it; it counts the app's
// frames from Flutter's timings, not its own, and shows idle when nothing
// is drawn.
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const Text('home');
}

Future<void> _start(WidgetTester tester, [String properties = '']) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            const [],
            resources: {
              'application.properties': EmbeddedResource.text(properties),
            },
          ),
        ],
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ),
      home: const _Home(),
    ),
  );
  await tester.pumpAndSettle();
}

FrameMeterTheme _look(Map<String, String> values) =>
    SpringThemes(values).data('light').frameMeter;

// A frame that started at [start] µs and took [build] and [raster] µs.
FrameTiming _frame(int start, {int build = 2000, int raster = 3000}) =>
    FrameTiming(
      vsyncStart: start,
      buildStart: start,
      buildFinish: start + build,
      rasterStart: start + build,
      rasterFinish: start + build + raster,
      rasterFinishWallTime: start + build + raster,
    );

void main() {
  test("the theme's frame-meter: colors, a text style, wrong values", () {
    expect(_look(const {}), const FrameMeterTheme());
    final look = _look(const {
      'frame-meter.background': '#80000000',
      'frame-meter.good': 'green',
      'frame-meter.text-style': 'body-small',
    });
    expect(look.background, const Color(0x80000000));
    expect(look.good, isNotNull);
    expect(look.textStyle, 'bodysmall');
    for (final values in [
      const {'frame-meter.text-style': 'huge'},
      const {'frame-meter.colour': 'red'},
    ]) {
      expect(
        () => _look(values),
        throwsA(isA<ThemePropertyException>()),
        reason: '$values',
      );
    }
  });

  testWidgets('off by default; on, in the corner it is given', (
    tester,
  ) async {
    await _start(tester);
    expect(find.byType(FrameMeter), findsNothing);
    await tester.pumpWidget(const SizedBox());

    await _start(
      tester,
      'spring.flutter.app.type=material\n'
      'spring.flutter.frame-meter.enabled=true\n'
      'spring.flutter.frame-meter.position=bottom-left',
    );
    final meter = tester.widget<FrameMeter>(find.byType(FrameMeter));
    expect(meter.position, FrameMeterPosition.bottomLeft);
    expect(find.text('idle'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets("the app's frames a second and times; its own not counted", (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FrameMeter(child: SizedBox()),
      ),
    );
    final report = tester.binding.platformDispatcher.onReportTimings!;
    // 31 frames 1/60 s apart: 60 a second.
    report([for (var i = 0; i <= 30; i++) _frame(i * 16667)]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('60 fps'), findsOneWidget);
    expect(find.textContaining('build 2.0 ms'), findsOneWidget);
    expect(find.textContaining('raster 3.0 ms'), findsOneWidget);
    // The meter's repaint comes back as a frame: not the app's.
    report([_frame(31 * 16667)]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('60 fps'), findsOneWidget);
  });
}
