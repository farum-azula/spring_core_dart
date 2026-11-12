// SpringTextSelectionControls: the selection handles of the starter's own
// selectable text in an app without a design library. None where a mouse
// selects, two round handles in the theme's primary color on a touch
// screen.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _touch = {
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.fuchsia,
};

const _mouse = {
  TargetPlatform.linux,
  TargetPlatform.macOS,
  TargetPlatform.windows,
};

/// Runs [body] as on [platform].
T on<T>(TargetPlatform platform, T Function() body) {
  debugDefaultTargetPlatformOverride = platform;
  try {
    return body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  final controls = SpringTextSelectionControls.instance;

  test('one instance, with handles and no toolbar of its own', () {
    expect(SpringTextSelectionControls.instance, same(controls));
    expect(controls, isA<TextSelectionControls>());
    expect(controls, isA<TextSelectionHandleControls>());
    expect(_touch.union(_mouse), TargetPlatform.values.toSet());
  });

  test('the size of a handle: 22 on a touch screen, none with a mouse', () {
    for (final platform in TargetPlatform.values) {
      for (final lineHeight in [0.0, 14.0, 40.0]) {
        expect(
          on(platform, () => controls.getHandleSize(lineHeight)),
          _touch.contains(platform) ? const Size(22, 22) : Size.zero,
          reason: '${platform.name} $lineHeight',
        );
      }
    }
  });

  test('the anchor of each handle: the corner that points at the text', () {
    for (final platform in TargetPlatform.values) {
      Offset anchor(TextSelectionHandleType type) =>
          on(platform, () => controls.getHandleAnchor(type, 20));
      final touch = _touch.contains(platform);
      expect(
        anchor(TextSelectionHandleType.left),
        touch ? const Offset(22, 0) : Offset.zero,
        reason: platform.name,
      );
      expect(
        anchor(TextSelectionHandleType.right),
        Offset.zero,
        reason: platform.name,
      );
      expect(
        anchor(TextSelectionHandleType.collapsed),
        touch ? const Offset(11, -4) : Offset.zero,
        reason: platform.name,
      );
    }
  });

  group('the handle', () {
    Widget handle(
      TextSelectionHandleType type, {
      SpringThemeData? theme,
      VoidCallback? onTap,
    }) {
      final built = Center(
        child: Builder(
          builder: (context) => controls.buildHandle(context, type, 20, onTap),
        ),
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: theme == null ? built : SpringTheme(data: theme, child: built),
      );
    }

    // A circle with the corner towards the text filled in.
    PaintPattern drawn(Color color) => paints
      ..circle(x: 11, y: 11, radius: 11, color: color)
      ..rect(rect: const Rect.fromLTWH(0, 0, 11, 11), color: color);

    testWidgets(
      'on a touch screen: a round handle in the theme\'s primary color',
      variant: TargetPlatformVariant(_touch),
      (tester) async {
        final themes = SpringThemes(const {
          'themes.sea.colors.primary': '#0000AA',
        });
        await tester.pumpWidget(
          handle(TextSelectionHandleType.right, theme: themes.data('sea')),
        );
        expect(tester.getSize(find.byType(CustomPaint)), const Size(22, 22));
        expect(find.byType(CustomPaint), drawn(const Color(0xFF0000AA)));

        // Another theme shown: its color.
        await tester.pumpWidget(
          handle(TextSelectionHandleType.right, theme: themes.data('dark')),
        );
        expect(find.byType(CustomPaint), drawn(const Color(0xFFD0BCFF)));

        // Outside a SpringTheme: a blue of its own.
        await tester.pumpWidget(handle(TextSelectionHandleType.right));
        expect(find.byType(CustomPaint), drawn(const Color(0xFF2196F3)));
      },
    );

    testWidgets(
      'turned by its side: the corner at the text',
      variant: TargetPlatformVariant(_touch),
      (tester) async {
        for (final (type, angle) in [
          (TextSelectionHandleType.left, math.pi / 2),
          (TextSelectionHandleType.collapsed, math.pi / 4),
        ]) {
          await tester.pumpWidget(handle(type));
          final transform = tester.widget<Transform>(find.byType(Transform));
          final expected = Matrix4.rotationZ(angle);
          for (var i = 0; i < 16; i++) {
            expect(
              transform.transform.storage[i],
              closeTo(expected.storage[i], 1e-9),
              reason: '${type.name} [$i]',
            );
          }
          expect(transform.alignment, Alignment.center, reason: type.name);
          expect(tester.getSize(find.byType(Transform)), const Size(22, 22));
        }
        // The right handle is as drawn.
        await tester.pumpWidget(handle(TextSelectionHandleType.right));
        expect(find.byType(Transform), findsNothing);
      },
    );

    testWidgets(
      'a tap on it is told',
      variant: TargetPlatformVariant(_touch),
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          handle(TextSelectionHandleType.left, onTap: () => taps++),
        );
        await tester.tap(find.byType(CustomPaint));
        expect(taps, 1);
      },
    );

    testWidgets(
      'with a mouse: nothing',
      variant: TargetPlatformVariant(_mouse),
      (tester) async {
        for (final type in TextSelectionHandleType.values) {
          await tester.pumpWidget(handle(type));
          expect(find.byType(CustomPaint), findsNothing, reason: type.name);
          expect(find.byType(GestureDetector), findsNothing);
          final box = tester.widget<SizedBox>(find.byType(SizedBox));
          expect((box.width, box.height), (0, 0), reason: type.name);
        }
      },
    );
  });

  group('in selectable text', () {
    const text = 'Select some of these words';

    Widget app(SpringThemeData data, Widget page) => WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, page) => SpringTheme(data: data, child: page!),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: Align(alignment: Alignment.topLeft, child: page),
    );

    // The handles among what the app paints (its debug banner is a
    // CustomPaint too).
    final handles = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          '${widget.painter.runtimeType}' == '_HandlePainter',
    );

    Offset inText(WidgetTester tester) =>
        tester.getTopLeft(find.text(text, findRichText: true)) +
        const Offset(20, 8);

    testWidgets(
      'a long press selects a word and shows the two handles',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        final data = SpringThemes(const {
          'colors.primary': '#0000AA',
        }).data('light');
        await tester.pumpWidget(
          app(
            data,
            SelectableRegion(
              selectionControls: controls,
              contextMenuBuilder: (context, region) => const SizedBox.shrink(),
              child: const Text(text),
            ),
          ),
        );
        expect(handles, findsNothing);

        await tester.longPressAt(inText(tester));
        await tester.pumpAndSettle();
        expect(handles, findsNWidgets(2));
        for (final handle in tester.renderObjectList(handles)) {
          expect(handle, paints..circle(color: const Color(0xFF0000AA)));
        }
      },
    );

    testWidgets(
      'in a MarkdownView: a drag of the mouse selects, with no handle',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        final data = SpringThemes(const {}).data('light');
        await tester.pumpWidget(app(data, const MarkdownView(text)));
        final gesture = await tester.startGesture(
          inText(tester) - const Offset(18, 0),
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(handles, findsNothing);
        // No menu: the platform's shortcut copies what was selected.
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(copied, isNotEmpty);
        expect(text, startsWith(copied!));
      },
    );

    testWidgets(
      'in a MarkdownView: a long press selects a word, with the handles',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        final data = SpringThemes(const {}).data('light');
        await tester.pumpWidget(app(data, const MarkdownView(text)));
        await tester.longPressAt(inText(tester));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(handles, findsNWidgets(2));
      },
    );

    testWidgets(
      'in a MarkdownView: a right click shows no menu and breaks nothing',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        final data = SpringThemes(const {}).data('light');
        await tester.pumpWidget(app(data, const MarkdownView(text)));
        final gesture = await tester.startGesture(
          inText(tester),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(handles, findsNothing);
        expect(find.text(text, findRichText: true), findsOneWidget);
      },
    );
  });
}
