// The desktop window of SpringApplicationWidget with a fake method channel:
// what the native side is asked, when, and what the widgets below see.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class Calls {
  final List<MethodCall> calls = [];
  Completer<void>? hold;
  Map<String, Object?> insets = {'left': 70.0, 'top': 28.0};

  List<MethodCall> named(String name) =>
      calls.where((c) => c.method == name).toList();
}

Calls installChannel(WidgetTester tester) {
  final calls = Calls();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel(DesktopWindowChannel.name),
    (call) async {
      calls.calls.add(call);
      await calls.hold?.future;
      if (call.method == 'apply') {
        return {'insets': calls.insets};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DesktopWindowChannel.name),
      null,
    ),
  );
  return calls;
}

SpringApplication app(Map<String, String> properties) => SpringApplication(
  [
    BeanModule(
      'test',
      const [],
      resources: {
        'application.properties': EmbeddedResource.text(
          properties.entries.map((e) => '${e.key}=${e.value}').join('\n'),
        ),
      },
    ),
  ],
  bannerMode: BannerMode.off,
);

class Probe extends StatelessWidget {
  const Probe({super.key});

  @override
  Widget build(BuildContext context) {
    final window = DesktopWindow.of(context);
    return Text(
      '${window.titleBar.propertyValue} '
      '${window.insets.left.round()}/${window.insets.top.round()}',
      textDirection: TextDirection.ltr,
    );
  }
}

Future<void> pump(
  WidgetTester tester,
  Map<String, String> properties, {
  Widget Function(BuildContext, Object)? failure,
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => app(properties),
      failure: failure,
      child: const Probe(),
    ),
  );
  await tester.pumpAndSettle();
}

const all = {
  'spring.flutter.desktop.window.title': 'NEON Books',
  'spring.flutter.desktop.window.title-bar': 'transparent',
  'spring.flutter.desktop.window.initial-size': '1280x800',
  'spring.flutter.desktop.window.min-size': '800x600',
  'spring.flutter.desktop.window.max-size': '1920x1080',
};

// A test that may set the platform: reset before the binding checks it.
void testDesktop(
  String description,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(description, (tester) async {
  try {
    await body(tester);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});

void main() {
  testDesktop('macOS: one apply call with all the values, insets reach '
      'the widgets', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = installChannel(tester);
    await pump(tester, all);

    expect(calls.calls, hasLength(1));
    expect(calls.calls.single.method, 'apply');
    expect(calls.calls.single.arguments, {
      'title': 'NEON Books',
      'titleBar': 'transparent',
      'initialWidth': 1280.0,
      'initialHeight': 800.0,
      'minWidth': 800.0,
      'minHeight': 600.0,
      'maxWidth': 1920.0,
      'maxHeight': 1080.0,
    });
    expect(find.text('transparent 70/28'), findsOneWidget);
  });

  testDesktop('only the keys that are set are sent', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = installChannel(tester);
    await pump(tester, {'spring.flutter.desktop.window.min-size': '800x600'});

    expect(calls.calls.single.arguments, {
      'titleBar': 'default',
      'minWidth': 800.0,
      'minHeight': 600.0,
    });
    // The title bar is the OS's: the widgets see the style as it is.
    expect(find.text('default 70/28'), findsOneWidget);
  });

  testDesktop('no properties: no call, no insets', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final calls = installChannel(tester);
    await pump(tester, {'spring.flutter.app.title': 'x'});

    expect(calls.calls, isEmpty);
    expect(find.text('default 0/0'), findsOneWidget);
  });

  testDesktop('the first frame waits for the window', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = installChannel(tester)..hold = Completer<void>();
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => app(all),
        child: const Probe(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.sendFramesToEngine, isFalse);

    calls.hold!.complete();
    await tester.pumpAndSettle();
    expect(tester.binding.sendFramesToEngine, isTrue);
  });

  testDesktop('the first frame is not held when the start fails', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    installChannel(tester);
    await pump(
      tester,
      {
        'spring.flutter.desktop.window.initial-size': '1280x',
      },
      failure: (_, error) =>
          Text('failed: $error', textDirection: TextDirection.ltr),
    );

    expect(tester.binding.sendFramesToEngine, isTrue);
  });

  testDesktop('a malformed value stops the start naming the key', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = installChannel(tester);
    await pump(
      tester,
      {
        'spring.flutter.desktop.window.initial-size': '1280x',
      },
      failure: (_, error) =>
          Text('failed: $error', textDirection: TextDirection.ltr),
    );

    expect(
      find.textContaining('spring.flutter.desktop.window.initial-size'),
      findsOneWidget,
    );
    expect(find.textContaining('<width>x<height>'), findsOneWidget);
    expect(calls.calls, isEmpty);
  });

  testDesktop('an initial size below the minimum stops the start', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    installChannel(tester);
    await pump(
      tester,
      {
        'spring.flutter.desktop.window.initial-size': '700x500',
        'spring.flutter.desktop.window.min-size': '800x600',
      },
      failure: (_, error) =>
          Text('failed: $error', textDirection: TextDirection.ltr),
    );

    expect(find.textContaining('initial-size=700x500'), findsOneWidget);
    expect(find.textContaining('min-size=800x600'), findsOneWidget);
  });

  testDesktop('a phone ignores the keys, even malformed ones', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = installChannel(tester);
    await pump(tester, {
      'spring.flutter.desktop.window.title-bar': 'glass',
      'spring.flutter.desktop.window.initial-size': '1280x',
    });

    expect(calls.calls, isEmpty);
    expect(find.text('default 0/0'), findsOneWidget);
    expect(tester.binding.sendFramesToEngine, isTrue);
  });

  testDesktop('a window without the plugin runs the app', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    // The engine answers a channel nobody listens to with "not implemented".
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      DesktopWindowChannel.name,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        DesktopWindowChannel.name,
        null,
      ),
    );
    await pump(tester, all);

    expect(find.text('default 0/0'), findsOneWidget);
  });

  testDesktop('a failing native call runs the app with no insets', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DesktopWindowChannel.name),
      (call) async => throw PlatformException(code: 'no_window'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DesktopWindowChannel.name),
        null,
      ),
    );
    await pump(tester, all);

    expect(find.text('default 0/0'), findsOneWidget);
  });

  group('WindowDragArea', () {
    Future<Calls> pumpArea(
      WidgetTester tester, {
      bool doubleClick = true,
    }) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final calls = installChannel(tester);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WindowDragArea(
              doubleClickMaximizes: doubleClick,
              child: const SizedBox(width: 300, height: 40),
            ),
          ),
        ),
      );
      return calls;
    }

    Future<void> click(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        const Offset(50, 20),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
    }

    testDesktop('a mouse drag starts the native window drag', (tester) async {
      final calls = await pumpArea(tester);
      final gesture = await tester.startGesture(
        const Offset(50, 20),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout);

      expect(calls.named('startDrag'), hasLength(1));
      expect(calls.named('toggleMaximize'), isEmpty);
    });

    testDesktop('a click alone moves nothing', (tester) async {
      final calls = await pumpArea(tester);
      await click(tester);
      await tester.pump(kDoubleTapTimeout);

      expect(calls.calls, isEmpty);
    });

    testDesktop('a double click maximizes or restores', (tester) async {
      final calls = await pumpArea(tester);
      await click(tester);
      await tester.pump(kDoubleTapMinTime);
      await click(tester);
      await tester.pump();

      expect(calls.named('toggleMaximize'), hasLength(1));
    });

    testDesktop('doubleClickMaximizes: false leaves the double click', (
      tester,
    ) async {
      final calls = await pumpArea(tester, doubleClick: false);
      await click(tester);
      await tester.pump(kDoubleTapMinTime);
      await click(tester);
      await tester.pump(kDoubleTapTimeout);

      expect(calls.calls, isEmpty);
    });

    testDesktop('on a phone it calls nothing', (tester) async {
      final calls = await pumpArea(tester);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final gesture = await tester.startGesture(
        const Offset(50, 20),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout);

      expect(calls.calls, isEmpty);
    });
  });

  test('DesktopWindowData compares by value', () {
    expect(
      const DesktopWindowData(
        titleBar: TitleBarStyle.hidden,
        insets: DesktopWindowInsets(left: 1),
      ),
      const DesktopWindowData(
        titleBar: TitleBarStyle.hidden,
        insets: DesktopWindowInsets(left: 1),
      ),
    );
    expect(
      DesktopWindowData.none,
      isNot(
        const DesktopWindowData(
          titleBar: TitleBarStyle.transparent,
        ),
      ),
    );
  });
}
