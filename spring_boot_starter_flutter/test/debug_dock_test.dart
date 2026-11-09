// The dock of the debug overlays: those of a corner one under the other
// when they fit, one at a time with dots when they do not (a swipe, a dot
// changes the page); hidden while the debug panel is open; a dragged one
// joins the nearest corner, or stays where it was dropped.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_dock.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay_drag.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';

final class _Overlay extends ChangeNotifier implements DebugOverlay {
  _Overlay(this.id, {this.order = 0});

  @override
  final String id;

  @override
  String get title => id;

  @override
  DebugOverlayCorner get corner => DebugOverlayCorner.topRight;

  @override
  final int order;

  @override
  Size get size => const Size(150, 60);

  bool _shown = true;

  @override
  bool get shown => _shown;

  @override
  set shown(bool value) {
    _shown = value;
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox.fromSize(size: size, child: Text(id));
}

Future<void> _pump(
  WidgetTester tester,
  List<DebugOverlay> overlays, {
  Size screen = const Size(1200, 800),
  DebugOverlayLayout layout = DebugOverlayLayout.auto,
  DebugOverlayPlacement? placement,
  ValueListenable<bool>? hiddenWhile,
}) async {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: screen),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DebugDock(
          overlays: overlays,
          settings: DebugDockSettings(layout: layout),
          placement: placement,
          hiddenWhile: hiddenWhile,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a stack when they fit, pages when they do not', (
    tester,
  ) async {
    final overlays = [_Overlay('meter'), _Overlay('timeline', order: 1)];
    await _pump(tester, overlays);
    expect(find.text('meter'), findsOneWidget);
    expect(find.text('timeline'), findsOneWidget);
    // A phone: 2 × 60 + 8 over 40 % of 240 does not fit.
    await _pump(tester, overlays, screen: const Size(360, 240));
    expect(find.text('meter'), findsOneWidget);
    expect(find.text('timeline'), findsNothing);
    await tester.fling(find.text('meter'), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('timeline'), findsOneWidget);
    expect(find.text('meter'), findsNothing);
  });

  testWidgets('pages: a wheel turn changes the page', (tester) async {
    final overlays = [_Overlay('meter'), _Overlay('timeline', order: 1)];
    await _pump(tester, overlays, layout: DebugOverlayLayout.pages);
    expect(find.text('timeline'), findsNothing);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('meter'))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await tester.pump();
    expect(find.text('timeline'), findsOneWidget);
  });

  testWidgets('hidden while the debug panel is open', (tester) async {
    final open = ValueNotifier(false);
    await _pump(tester, [_Overlay('meter')], hiddenWhile: open);
    expect(find.text('meter'), findsOneWidget);
    open.value = true;
    await tester.pump();
    expect(find.text('meter'), findsNothing);
  });

  testWidgets('dragged with a mouse: the nearest corner', (tester) async {
    final drag = DebugOverlayDrag();
    final meter = _Overlay('meter');
    await _pump(tester, [meter], placement: drag);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('meter')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-900, 600));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 10));
    await gesture.up();
    await tester.pump();
    expect(drag.cornerOf(meter), DebugOverlayCorner.bottomLeft);
    expect(drag.freeOf(meter), isNull);
    drag.reset();
    expect(drag.cornerOf(meter), DebugOverlayCorner.topRight);
  });

  testWidgets('snap free: it stays where it was dropped', (tester) async {
    final drag = DebugOverlayDrag(snap: DebugOverlaySnap.free);
    final meter = _Overlay('meter');
    await _pump(tester, [meter], placement: drag);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('meter')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-500, 300));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 10));
    await gesture.up();
    await tester.pump();
    final at = drag.freeOf(meter)!;
    expect(at.dx, lessThan(0.6));
    expect(at.dy, greaterThan(0.3));
    expect(find.text('meter'), findsOneWidget);
  });
}
