@TestOn('browser')
library;

// The browser's side of the scenes in a real browser: `flutter test
// --platform chrome test/scene_web_test.dart`. The VM run skips it.
//
// - The beat on the browser's frames (requestAnimationFrame).
// - The engine's canvas, `canvas: engine`: the engine's `new
//   OffscreenCanvas(1, 1)` answered with a canvas element the page shows,
//   its size the engine sets kept from the canvas, its present (a blit
//   into the canvas) going into the scene's own texture, and the canvas
//   drawn from those textures where the scenes stand, pixel for pixel.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_screen_web.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_ticks_web.dart';

const int _texture2d = 0x0DE1;
const int _rgba = 0x1908;
const int _unsignedByte = 0x1401;
const int _framebuffer = 0x8D40;
const int _readFramebuffer = 0x8CA8;
const int _colorAttachment0 = 0x8CE0;
const int _colorBufferBit = 0x4000;
const int _nearest = 0x2600;

JSObject get _window => globalContext;

JSAny? _call(JSObject target, String name, List<JSAny?> arguments) =>
    target.callMethodVarArgs<JSAny?>(name.toJS, arguments);

void main() {
  test('the beat comes on the browser\'s frames, and stops', () async {
    var beats = 0;
    final stop = startSceneTicks(Duration.zero, () => beats++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    stop();
    // Headless Chrome shows frames too, some 60 a second.
    expect(beats, greaterThan(5));
    final stopped = beats;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(beats, stopped, reason: 'no beat after the stop');
  });

  test(
    'the engine draws on a canvas the page shows, nothing handed over',
    () async {
      // What flutter_scene's start does: one OffscreenCanvas(1, 1), a WebGL2
      // context on it with the drawing buffer preserved and no antialiasing.
      late JSObject engineGl;
      late JSObject engineCanvas;
      await startOnEngineCanvas(() async {
        engineCanvas = (_window['OffscreenCanvas']! as JSFunction)
            .callAsConstructor<JSObject>(1.toJS, 1.toJS);
        engineGl =
            _call(engineCanvas, 'getContext', [
                  'webgl2'.toJS,
                  JSObject()
                    ..['antialias'] = false.toJS
                    ..['alpha'] = true.toJS
                    ..['depth'] = false.toJS
                    ..['stencil'] = false.toJS
                    ..['preserveDrawingBuffer'] = true.toJS,
                ])!
                as JSObject;
      });
      final canvas = sceneScreenCanvas!;
      expect(identical(canvas, engineCanvas), isTrue);
      expect(canvas.instanceOfString('HTMLCanvasElement'), isTrue);
      expect(
        (globalContext['OffscreenCanvas']! as JSObject)['prototype'],
        isNotNull,
        reason: 'the browser\'s OffscreenCanvas is back after the start',
      );
      final attributes =
          _call(engineGl, 'getContextAttributes', const [])! as JSObject;
      expect(
        (attributes['preserveDrawingBuffer']! as JSBoolean).toDart,
        isFalse,
        reason: 'drawn whole each time: the buffer need not be kept',
      );

      // The engine's present of a frame of 4 by 2: its texture in green.
      final scene = _call(engineGl, 'createTexture', const [])! as JSObject;
      _call(engineGl, 'bindTexture', [_texture2d.toJS, scene]);
      final green = JSUint8Array.withLength(4 * 2 * 4);
      for (var i = 0; i < 8; i++) {
        green.toDart.setAll(i * 4, [0, 255, 0, 255]);
      }
      _call(engineGl, 'texImage2D', [
        _texture2d.toJS,
        0.toJS,
        _rgba.toJS,
        4.toJS,
        2.toJS,
        0.toJS,
        _rgba.toJS,
        _unsignedByte.toJS,
        green,
      ]);
      final read = _call(engineGl, 'createFramebuffer', const [])! as JSObject;
      final target = SceneScreenTarget();
      final drew = drawSceneOnScreen(target, () {
        // flutter_scene's _blitTextureToCanvas: the canvas sized to the
        // frame, the texture read, a blit flipped onto the canvas.
        canvas['width'] = 4.toJS;
        canvas['height'] = 2.toJS;
        _call(engineGl, 'bindFramebuffer', [_readFramebuffer.toJS, read]);
        _call(engineGl, 'framebufferTexture2D', [
          _readFramebuffer.toJS,
          _colorAttachment0.toJS,
          _texture2d.toJS,
          scene,
          0.toJS,
        ]);
        _call(engineGl, 'bindFramebuffer', [0x8CA9.toJS, null]);
        _call(engineGl, 'blitFramebuffer', [
          0.toJS,
          0.toJS,
          4.toJS,
          2.toJS,
          0.toJS,
          2.toJS,
          4.toJS,
          0.toJS,
          _colorBufferBit.toJS,
          _nearest.toJS,
        ]);
        _call(engineGl, 'bindFramebuffer', [_framebuffer.toJS, null]);
      });
      expect(drew, isTrue);
      expect(target.drawn, isTrue);
      expect(
        (canvas['width']! as JSNumber).toDartInt,
        4,
        reason: 'the engine is told the size it set',
      );

      // The canvas, 20 by 10, drawn from the scene's texture at 8,4.
      composeSceneScreen(20, 10, [
        (
          target: target,
          left: 8,
          top: 4,
          right: 12,
          bottom: 6,
          clipLeft: 0,
          clipTop: 0,
          clipRight: 20,
          clipBottom: 10,
        ),
      ]);
      final pixels = JSUint8Array.withLength(20 * 10 * 4);
      _call(engineGl, 'bindFramebuffer', [_framebuffer.toJS, null]);
      _call(engineGl, 'readPixels', [
        0.toJS,
        0.toJS,
        20.toJS,
        10.toJS,
        _rgba.toJS,
        _unsignedByte.toJS,
        pixels,
      ]);
      List<int> at(int x, int y) {
        // readPixels counts rows from the bottom.
        final row = 10 - 1 - y;
        final i = (row * 20 + x) * 4;
        return pixels.toDart.sublist(i, i + 4);
      }

      expect(at(9, 5), [0, 255, 0, 255], reason: 'the scene where it stands');
      expect(at(2, 2), [0, 0, 0, 0], reason: 'transparent around it');
      expect(at(13, 5), [0, 0, 0, 0]);

      // Clipped by the list it scrolls in: nothing below row 5 of the canvas.
      composeSceneScreen(20, 10, [
        (
          target: target,
          left: 8,
          top: 4,
          right: 12,
          bottom: 6,
          clipLeft: 0,
          clipTop: 0,
          clipRight: 20,
          clipBottom: 5,
        ),
      ]);
      _call(engineGl, 'readPixels', [
        0.toJS,
        0.toJS,
        20.toJS,
        10.toJS,
        _rgba.toJS,
        _unsignedByte.toJS,
        pixels,
      ]);
      expect(at(9, 4), [0, 255, 0, 255]);
      expect(at(9, 5), [0, 0, 0, 0], reason: 'under the clip');

      // A blit outside a scene's draw goes nowhere: the canvas is the
      // composition's alone.
      _call(engineGl, 'bindFramebuffer', [_readFramebuffer.toJS, read]);
      _call(engineGl, 'blitFramebuffer', [
        0.toJS,
        0.toJS,
        4.toJS,
        2.toJS,
        0.toJS,
        0.toJS,
        4.toJS,
        2.toJS,
        _colorBufferBit.toJS,
        _nearest.toJS,
      ]);
      _call(engineGl, 'bindFramebuffer', [_framebuffer.toJS, null]);
      _call(engineGl, 'readPixels', [
        0.toJS,
        0.toJS,
        20.toJS,
        10.toJS,
        _rgba.toJS,
        _unsignedByte.toJS,
        pixels,
      ]);
      expect(at(0, 9), [0, 0, 0, 0]);

      target.dispose();
      expect(target.drawn, isFalse);
    },
  );
}
