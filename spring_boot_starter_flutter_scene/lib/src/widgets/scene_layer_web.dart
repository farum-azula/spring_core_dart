import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_canvas_target.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_frame_transfer_web.dart';

/// Whether a scene can be a layer of its own here: on the web alone.
const bool sceneLayers = true;

/// A canvas of a scene's own, under the page's: a frame of the engine is
/// handed to it as it is (`bitmaprenderer`, no copy), and the browser
/// puts it together with the page. Flutter does not draw for it.
///
/// The frame is the engine's whole canvas, which may be larger than the
/// scene: the canvas is as much larger than the box it is in, which shows
/// the scene's corner of it alone.
final class SceneLayer implements SceneCanvasTarget {
  JSObject? _canvas;
  JSObject? _context;
  int _width = 0;
  int _height = 0;
  int _sceneWidth = 0;
  int _sceneHeight = 0;

  @override
  Widget build() =>
      HtmlElementView.fromTagName(tagName: 'div', onElementCreated: _created);

  void _created(Object element) {
    final box = element as JSObject;
    _style(box, {
      'width': '100%',
      'height': '100%',
      'position': 'relative',
      'overflow': 'hidden',
      'pointerEvents': 'none',
    });
    final canvas = (globalContext['document']! as JSObject)
        .callMethod<JSObject>('createElement'.toJS, 'canvas'.toJS);
    _style(canvas, {
      'position': 'absolute',
      'left': '0',
      'bottom': '0',
      'width': '100%',
      'height': '100%',
      'display': 'block',
      'pointerEvents': 'none',
    });
    box.callMethod<JSAny?>('appendChild'.toJS, canvas);
    _canvas = canvas;
    _context = canvas.callMethod<JSObject?>(
      'getContext'.toJS,
      'bitmaprenderer'.toJS,
    );
  }

  @override
  bool present(void Function() draw) {
    final canvas = _canvas;
    final context = _context;
    if (canvas == null || context == null) {
      return false;
    }
    final drawn = drawSceneFrame(draw);
    if (drawn == null || drawn.width <= 0 || drawn.height <= 0) {
      return false;
    }
    final frame = drawn.frame;
    final width = (frame['width']! as JSNumber).toDartInt;
    final height = (frame['height']! as JSNumber).toDartInt;
    if (width != _width ||
        height != _height ||
        drawn.width != _sceneWidth ||
        drawn.height != _sceneHeight) {
      _width = width;
      _height = height;
      _sceneWidth = drawn.width;
      _sceneHeight = drawn.height;
      _style(canvas, {
        'width': '${100 * width / drawn.width}%',
        'height': '${100 * height / drawn.height}%',
      });
    }
    context.callMethod<JSAny?>('transferFromImageBitmap'.toJS, frame);
    return true;
  }

  @override
  void dispose() {}

  static void _style(JSObject element, Map<String, String> values) {
    final style = element['style']! as JSObject;
    for (final MapEntry(:key, :value) in values.entries) {
      style[key] = value.toJS;
    }
  }
}
