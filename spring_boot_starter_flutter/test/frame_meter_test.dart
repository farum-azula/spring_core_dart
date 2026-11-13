// The frame meter: spring.flutter.frame-meter.* turns it on and puts it
// in a corner; the theme's frame-meter colors it; it counts the app's
// frames from Flutter's timings, not its own, and shows idle when nothing
// is drawn.
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
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

  group('few frames by choice are not late frames', () {
    Color? colorOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style?.color;

    testWidgets('an animation that asks for a frame now and then (a slow '
        'drift at 15 a second): its rate in the plain color, each frame '
        'measured by its own work', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FrameMeter(child: SizedBox()),
        ),
      );
      // Ten more frames, none asked for as the one before ended.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final report = tester.binding.platformDispatcher.onReportTimings!;
      report([for (var i = 0; i <= 10; i++) _frame(i * 66667)]);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('15 fps'), findsOneWidget);
      expect(colorOf(tester, '15 fps'), const Color(0xFFFFFFFF));
      // 2 ms of build and 3 of raster, not the 67 between the frames.
      expect(find.textContaining('worst 5 ms'), findsOneWidget);
    });

    testWidgets("the meter's own repaint between two of the app's frames "
        'does not make them look closer', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FrameMeter(child: SizedBox()),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final report = tester.binding.platformDispatcher.onReportTimings!;
      report([for (var i = 0; i < 4; i++) _frame(i * 66667)]);
      // The meter is drawn again: a frame of its own, half way to the
      // app's next one.
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      report([
        _frame(3 * 66667 + 33000),
        for (var i = 4; i < 7; i++) _frame(i * 66667),
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('15 fps'), findsOneWidget);
    });

    testWidgets('the same frames while something moves at every frame: '
        'the app was waiting for each, 20 a second is late', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FrameMeter(child: _Spinner()),
        ),
      );
      // The ticker asks for the next frame as each one ends.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final report = tester.binding.platformDispatcher.onReportTimings!;
      report([for (var i = 0; i <= 10; i++) _frame(i * 50000)]);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('20 fps'), findsOneWidget);
      expect(colorOf(tester, '20 fps'), const Color(0xFFF44336));
      expect(find.textContaining('worst 50 ms'), findsOneWidget);
    });

    testWidgets('a frame the app waited long for is late however long', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FrameMeter(child: _Spinner()),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final report = tester.binding.platformDispatcher.onReportTimings!;
      // The third came 400 ms after the second.
      report([_frame(0), _frame(16667), _frame(416667), _frame(433334)]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('worst 400 ms'), findsOneWidget);
    });
  });
}

// Something that moves at every frame.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _controller, child: const SizedBox());
}
