// The arithmetic of the engine's canvas (canvas: engine), on a real render
// tree: whether the first scene fills the screen (the canvas then stands
// behind the page), where a scene goes on the canvas in its pixels, what a
// scrolled list or a clip lets show of it, and in which order scenes are
// drawn.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_screen_layout.dart';

const _screen = Size(400, 800);

Future<void> _show(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = _screen
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

RenderBox _box(WidgetTester tester, Key key) =>
    tester.renderObject<RenderBox>(find.byKey(key));

void main() {
  const host = Key('host');
  const scene = Key('scene');

  testWidgets(
    'a scene behind the whole page fills the screen; a card does not',
    (
      tester,
    ) async {
      await _show(
        tester,
        const Stack(
          children: [
            Positioned.fill(child: SizedBox(key: host)),
            Positioned(
              left: 20,
              top: 40,
              width: 200,
              height: 100,
              child: SizedBox(key: scene),
            ),
          ],
        ),
      );
      expect(SceneScreenLayout.fills(_box(tester, host), _screen), isTrue);
      expect(SceneScreenLayout.fills(_box(tester, scene), _screen), isFalse);
      expect(
        SceneScreenLayout.fills(_box(tester, host), Size.zero),
        isFalse,
        reason: 'a screen of no size: not yet known',
      );
    },
  );

  testWidgets('a scene lands on whole pixels of the canvas', (tester) async {
    await _show(
      tester,
      const Stack(
        children: [
          Positioned(
            left: 10.3,
            top: 20.6,
            width: 100.2,
            height: 50,
            child: SizedBox(key: scene),
          ),
        ],
      ),
    );
    final piece = SceneScreenLayout.piece(
      #frame,
      _box(tester, scene),
      area: Offset.zero & _screen,
      ratio: 2,
    )!;
    expect(piece.target, #frame);
    expect(
      [piece.left, piece.top, piece.right, piece.bottom],
      [21, 41, 221, 141],
    );
    expect(
      [piece.clipLeft, piece.clipTop, piece.clipRight, piece.clipBottom],
      [20, 41, 221, 142],
      reason: 'the part that shows, its edges outward',
    );
  });

  testWidgets('the canvas over part of the screen: the scene from its corner', (
    tester,
  ) async {
    await _show(
      tester,
      const Stack(
        children: [
          Positioned(
            left: 50,
            top: 100,
            width: 300,
            height: 400,
            child: SizedBox(key: host),
          ),
          Positioned(
            left: 70,
            top: 120,
            width: 100,
            height: 100,
            child: SizedBox(key: scene),
          ),
          Positioned(
            left: 360,
            top: 700,
            width: 30,
            height: 30,
            child: SizedBox(key: Key('out')),
          ),
        ],
      ),
    );
    final area = SceneScreenLayout.areaOf(_box(tester, host));
    expect(area, const Rect.fromLTWH(50, 100, 300, 400));
    final piece = SceneScreenLayout.piece(
      #card,
      _box(tester, scene),
      area: area,
      ratio: 1,
    )!;
    expect(
      [piece.left, piece.top, piece.right, piece.bottom],
      [20, 20, 120, 120],
    );
    expect(
      SceneScreenLayout.piece(
        #out,
        _box(tester, const Key('out')),
        area: area,
        ratio: 1,
      ),
      isNull,
      reason: 'outside the canvas: nothing to draw',
    );
  });

  testWidgets('a scrolled list clips the scene it scrolls under its edge', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _show(
      tester,
      Column(
        children: [
          const SizedBox(height: 100),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              child: const Column(
                children: [
                  SizedBox(height: 50),
                  SizedBox(key: scene, height: 200, width: 400),
                  SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    controller.jumpTo(120);
    await tester.pump();
    final piece = SceneScreenLayout.piece(
      #frame,
      _box(tester, scene),
      area: Offset.zero & _screen,
      ratio: 1,
    )!;
    expect(piece.top, 30, reason: 'the scene itself, under the header');
    expect(piece.bottom, 230);
    expect(piece.clipTop, 100, reason: 'what shows starts at the list\'s edge');
    expect(piece.clipBottom, 230);

    controller.jumpTo(400);
    await tester.pump();
    expect(
      SceneScreenLayout.piece(
        #frame,
        _box(tester, scene),
        area: Offset.zero & _screen,
        ratio: 1,
      ),
      isNull,
      reason: 'scrolled away',
    );
  });

  testWidgets('a ClipRect lets its part of the scene show', (tester) async {
    await _show(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: ClipRect(
          child: SizedBox(
            width: 100,
            height: 100,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: 300,
              maxHeight: 300,
              child: SizedBox(key: scene, width: 300, height: 300),
            ),
          ),
        ),
      ),
    );
    final piece = SceneScreenLayout.piece(
      #glow,
      _box(tester, scene),
      area: Offset.zero & _screen,
      ratio: 1,
    )!;
    expect([piece.right, piece.bottom], [300, 300]);
    expect([piece.clipRight, piece.clipBottom], [100, 100]);
  });

  test('drawn in the order painted: around first, the rest as they came', () {
    final depths = {'card': 9, 'wall': 3, 'frame': 9, 'badge': 12};
    expect(
      SceneScreenLayout.painted([
        'card',
        'badge',
        'wall',
        'frame',
      ], (p) => depths[p]!),
      ['wall', 'card', 'frame', 'badge'],
    );
  });
}
