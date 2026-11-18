import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_starter_flutter_scene/src/engine/scene_screen_web.dart';

const int _colorBufferBit = 0x4000;
const int _texture2d = 0x0DE1;
const int _rgba = 0x1908;
const int _unsignedByte = 0x1401;
const int _framebuffer = 0x8D40;
const int _colorAttachment0 = 0x8CE0;
const int _unpackPremultiplyAlpha = 0x9241;

const List<int> _expected = [0, 102, 128, 128];
const List<int> _divided = [0, 204, 255, 128];

@JS('OffscreenCanvas')
extension type _Canvas._(JSObject _) implements JSObject {
  external factory _Canvas(int width, int height);

  external JSObject? getContext(String type, [JSAny? attributes]);

  external JSObject transferToImageBitmap();
}

extension type _Gl._(JSObject _) implements JSObject {
  external void clearColor(double r, double g, double b, double a);

  external void clear(int mask);

  external JSObject? createTexture();

  external void bindTexture(int target, JSObject? texture);

  external void pixelStorei(int name, int value);

  external void texImage2D(
    int target,
    int level,
    int internalFormat,
    int format,
    int type,
    JSObject source,
  );

  external JSObject? createFramebuffer();

  external void bindFramebuffer(int target, JSObject? framebuffer);

  external void framebufferTexture2D(
    int target,
    int attachment,
    int textarget,
    JSObject? texture,
    int level,
  );

  external void readPixels(
    int x,
    int y,
    int width,
    int height,
    int format,
    int type,
    JSUint8Array pixels,
  );
}

String? _transfer;

/// How this browser passes a frame of the engine's WebGL to the page:
/// `premultiplied` (as Flutter takes it), `unpremultiplied` (WebKit, with
/// Flutter's CanvasKit: the frames are given to CanvasKit as what they
/// are), `straight` (WebKit with another renderer: the engine's canvas
/// without premultiplied alpha, the faintest light losing some of its
/// colour), `screen` (the page shows the engine's canvas itself, and no
/// frame is passed), or `null` before the engine starts.
String? get sceneFrameTransfer => _transfer;

const String _mark = 'springSceneUnpremultiplied';

/// Runs [start], the engine's start, so that the engine's frames reach
/// Flutter as Flutter takes them.
///
/// `flutter_scene` hands each frame to Flutter by `transferToImageBitmap`
/// of its WebGL canvas, and Flutter's renderer takes the bitmap as
/// premultiplied. Which a bitmap of WebGL is, the standard leaves to the
/// browser: Chrome and Firefox keep it premultiplied, WebKit (Safari and
/// every browser of an iPhone) divides the colour by the alpha, and a
/// half-transparent glow comes out as solid colour. One pixel passed the
/// same way before the start says which this browser does.
///
/// For WebKit, where Flutter draws with CanvasKit, the bitmaps of the
/// engine's canvas are marked, and CanvasKit is told that a marked bitmap
/// is not premultiplied: it multiplies it itself, faint light exactly.
/// With another renderer the engine's canvas is made without
/// premultiplied alpha, which is right but for the faintest light. A
/// browser that passes a frame no way would draw nothing: the start
/// fails, and the scenes are their placeholders.
///
/// With [onScreen] the engine's canvas is one the page shows
/// ([startOnEngineCanvas]): no frame is passed, and there is nothing to
/// ask the browser.
Future<void> startWithFrameTransfer(
  Future<void> Function() start, {
  bool onScreen = false,
}) async {
  if (onScreen) {
    _transfer = 'screen';
    return startOnEngineCanvas(start);
  }
  final premultiplied = _probe(premultiplied: true);
  if (premultiplied == null || _close(premultiplied)) {
    _transfer = 'premultiplied';
    return _startCaught(start, made: (canvas) => _keepFrames(canvas));
  }
  final canvasKit = globalContext['flutterCanvasKit'];
  if (canvasKit.isA<JSObject>() && _close(premultiplied, _divided)) {
    _transfer = 'unpremultiplied';
    _readMarkedAsUnpremultiplied(canvasKit! as JSObject);
    return _startCaught(
      start,
      made: (canvas) => _keepFrames(canvas, mark: true),
    );
  }
  if (_probe(premultiplied: false) case final straight? when _close(straight)) {
    _transfer = 'straight';
    return _startCaught(
      start,
      ask: (attributes) => attributes['premultipliedAlpha'] = false.toJS,
      made: (canvas) => _keepFrames(canvas),
    );
  }
  throw StateError(
    'This browser does not pass a frame of WebGL to the page intact '
    '(a pixel of ${_expected.join(', ')} came back as '
    '${premultiplied.join(', ')}): its scenes would draw nothing.',
  );
}

Future<void> _startCaught(
  Future<void> Function() start, {
  void Function(JSObject attributes)? ask,
  required void Function(JSObject canvas) made,
}) async {
  final restore = _catchEngineCanvas(ask: ask, made: made);
  try {
    await start();
  } finally {
    restore();
  }
}

JSObject? _frame;
bool _layering = false;
_Canvas? _stand;
int _sceneWidth = 0;
int _sceneHeight = 0;
bool? _copies;
final List<double> _costs = [];
const int _measured = 12;
const double _copying = 0.5;

/// A frame of the engine for a layer: the engine's whole canvas, the
/// scene's [width] by [height] pixels in its lower left corner.
typedef SceneLayerFrame = ({JSObject frame, int width, int height});

/// The frame of the engine that [draw] makes it hand over, kept from
/// Flutter: a scene of a layer of its own puts it on its canvas. Flutter
/// is handed a bitmap of one pixel in its place (its renderer may take
/// the bitmap it is given to another thread, and would upload the frame
/// for an image nobody paints). `null` when [draw] hands nothing over.
///
/// The engine draws every scene on one canvas and sizes it to each: two
/// scenes of two sizes had it made anew twice a frame, a new drawing
/// buffer in the GPU each time (in Chrome, nine tenths of what a frame of
/// two scenes cost the page's thread). Where handing a frame over costs
/// nothing (Chrome gives the buffer away), the canvas only grows while a
/// layer draws: the engine is told the size it asked for and draws the
/// scene into that corner of it, and the layer shows that part. Where the
/// browser copies the frame as it hands it over (Firefox reads it back
/// from the GPU, WebKit copies it), the copy is of the whole canvas, and
/// the canvas stays the scene's size. Which, the first frames measure.
SceneLayerFrame? drawSceneFrame(void Function() draw) {
  _layering = true;
  _frame = null;
  try {
    draw();
  } finally {
    _layering = false;
  }
  final frame = _frame;
  _frame = null;
  return frame == null
      ? null
      : (frame: frame, width: _sceneWidth, height: _sceneHeight);
}

JSObject _standIn() {
  final stand = _stand ??= _Canvas(1, 1)..getContext('2d');
  return stand.transferToImageBitmap();
}

bool _close(List<int> pixel, [List<int> expected = _expected]) {
  for (var i = 0; i < expected.length; i++) {
    if ((pixel[i] - expected[i]).abs() > 3) {
      return false;
    }
  }
  return true;
}

// The probe's two contexts are let go, not lost (`WEBGL_lose_context`):
// each loss was a "context lost" line in the console of the page, and the
// collector frees them anyway; with the page's own and the engine's
// they are far below the browser's limit of active contexts (16).
List<int>? _probe({required bool premultiplied}) {
  final source = _Canvas(1, 1);
  final sourceGl = source.getContext('webgl2', _attributes(premultiplied));
  final target = _Canvas(1, 1).getContext('webgl2');
  if (sourceGl == null || target == null) {
    return null;
  }
  final gl = _Gl._(sourceGl);
  final read = _Gl._(target);
  try {
    gl.clearColor(0, 0.4, 0.5, 0.5);
    gl.clear(_colorBufferBit);
    return _upload(read, source.transferToImageBitmap());
  } on Object {
    return null;
  }
}

JSObject _attributes(bool premultiplied) => JSObject()
  ..['antialias'] = false.toJS
  ..['alpha'] = true.toJS
  ..['depth'] = false.toJS
  ..['stencil'] = false.toJS
  ..['preserveDrawingBuffer'] = true.toJS
  ..['premultipliedAlpha'] = premultiplied.toJS;

// Until the engine's canvas is made: a WebGL2 context asked for as the
// engine asks (no antialiasing, the drawing buffer preserved) is given to
// [ask] before it is made and its canvas to [made] after; the browser's
// own getContext is put back after it, or when the start ends.
void Function() _catchEngineCanvas({
  void Function(JSObject attributes)? ask,
  void Function(JSObject canvas)? made,
}) {
  final prototype =
      (globalContext['OffscreenCanvas']! as JSObject)['prototype']! as JSObject;
  final original = prototype['getContext']! as JSFunction;
  var restored = false;
  void restore() {
    if (!restored) {
      restored = true;
      prototype['getContext'] = original;
    }
  }

  prototype['getContext'] = ((JSObject canvas, JSAny? type, JSAny? attributes) {
    if (type.isA<JSString>() &&
        (type! as JSString).toDart == 'webgl2' &&
        attributes.isA<JSObject>()) {
      final asked = attributes! as JSObject;
      if (_flag(asked, 'preserveDrawingBuffer') == true &&
          _flag(asked, 'antialias') == false) {
        restore();
        ask?.call(asked);
        final context = original.callAsFunction(canvas, type, attributes);
        made?.call(canvas);
        return context;
      }
    }
    return original.callAsFunction(canvas, type, attributes);
  }).toJSCaptureThis;
  return restore;
}

// Each bitmap the engine's canvas hands over is marked where [mark], or
// kept for a scene of a layer of its own while it draws.
void _keepFrames(JSObject canvas, {bool mark = false}) {
  _growOnly(canvas);
  final transfer =
      ((globalContext['OffscreenCanvas']! as JSObject)['prototype']!
              as JSObject)['transferToImageBitmap']!
          as JSFunction;
  canvas['transferToImageBitmap'] = (() {
    final measuring = _layering && _copies == null;
    final start = measuring ? _now() : 0.0;
    final bitmap = transfer.callAsFunction(canvas)! as JSObject;
    if (measuring) {
      _measure(bitmap, _now() - start);
    }
    if (_layering) {
      _frame = bitmap;
      return _standIn();
    }
    if (mark) {
      bitmap[_mark] = true.toJS;
    }
    return bitmap;
  }).toJS;
}

// CanvasKit makes an image of a bitmap by MakeLazyImageFromTextureSource,
// told by Flutter that the bitmap is premultiplied; for a marked one it is
// told the bitmap is not, so it multiplies the colour by the alpha itself.
// The image keeps what it is told and reads it again when it uploads its
// texture again: each image is told on an object of its own.
void _readMarkedAsUnpremultiplied(JSObject canvasKit) {
  final original = canvasKit['MakeLazyImageFromTextureSource']! as JSFunction;
  final colorType = (canvasKit['ColorType']! as JSObject)['RGBA_8888'];
  final alphaType = (canvasKit['AlphaType']! as JSObject)['Unpremul'];
  final colorSpace = (canvasKit['ColorSpace']! as JSObject)['SRGB'];
  canvasKit['MakeLazyImageFromTextureSource'] =
      ((JSAny? source, JSAny? given, JSAny? premultiplied) {
        if (source.isA<JSObject>() &&
            _flag(source! as JSObject, _mark) == true) {
          final bitmap = source as JSObject;
          return original.callAsFunction(
            canvasKit,
            bitmap,
            JSObject()
              ..['width'] = bitmap['width']
              ..['height'] = bitmap['height']
              ..['colorType'] = colorType
              ..['alphaType'] = alphaType
              ..['colorSpace'] = colorSpace,
            false.toJS,
          );
        }
        return original.callAsFunction(
          canvasKit,
          source,
          given,
          premultiplied,
        );
      }).toJS;
}

double _now() =>
    ((globalContext['performance']! as JSObject).callMethod<JSNumber>(
      'now'.toJS,
    )).toDartDouble;

// The time a hand-over took, by the pixels handed over: after the first
// frames of layers, whether this browser copies them (over half a
// nanosecond a pixel; Chrome hands a frame of a million over in tens of
// microseconds, Firefox and WebKit in milliseconds).
void _measure(JSObject bitmap, double milliseconds) {
  final pixels =
      (bitmap['width']! as JSNumber).toDartInt *
      (bitmap['height']! as JSNumber).toDartInt;
  if (pixels <= 1) {
    return;
  }
  _costs.add(milliseconds * 1e6 / pixels);
  if (_costs.length < _measured) {
    return;
  }
  _costs.sort();
  _copies = _costs[_costs.length ~/ 2] > _copying;
  _costs.clear();
}

// While a layer draws, the engine's canvas answers with the size the
// engine set and, unless the browser copies frames, is made larger only
// when that is larger; otherwise it is the browser's.
void _growOnly(JSObject canvas) {
  final object = globalContext['Object']! as JSObject;
  final prototype =
      (globalContext['OffscreenCanvas']! as JSObject)['prototype']! as JSObject;
  for (final width in [true, false]) {
    final name = (width ? 'width' : 'height').toJS;
    final own = object.callMethod<JSObject>(
      'getOwnPropertyDescriptor'.toJS,
      prototype,
      name,
    );
    final read = own['get']! as JSFunction;
    final write = own['set']! as JSFunction;
    object.callMethod<JSAny?>(
      'defineProperty'.toJS,
      canvas,
      name,
      JSObject()
        ..['configurable'] = true.toJS
        ..['get'] = (() {
          final real = read.callAsFunction(canvas);
          if (!_layering || _copies != false) {
            return real;
          }
          // Smaller than asked (a scene not of a layer sized it since):
          // the engine sets it again, and it grows.
          final asked = width ? _sceneWidth : _sceneHeight;
          return (real! as JSNumber).toDartInt >= asked ? asked.toJS : real;
        }).toJS
        ..['set'] = ((JSNumber value) {
          if (!_layering) {
            write.callAsFunction(canvas, value);
            return;
          }
          final size = value.toDartInt;
          if (width) {
            _sceneWidth = size;
          } else {
            _sceneHeight = size;
          }
          if (_copies != false ||
              size > (read.callAsFunction(canvas)! as JSNumber).toDartInt) {
            write.callAsFunction(canvas, value);
          }
        }).toJS,
    );
  }
}

List<int> _upload(_Gl read, JSObject source, {bool premultiply = false}) {
  final texture = read.createTexture();
  read.bindTexture(_texture2d, texture);
  read.pixelStorei(_unpackPremultiplyAlpha, premultiply ? 1 : 0);
  read.texImage2D(_texture2d, 0, _rgba, _rgba, _unsignedByte, source);
  read.bindFramebuffer(_framebuffer, read.createFramebuffer());
  read.framebufferTexture2D(
    _framebuffer,
    _colorAttachment0,
    _texture2d,
    texture,
    0,
  );
  final pixel = JSUint8Array.withLength(4);
  read.readPixels(0, 0, 1, 1, _rgba, _unsignedByte, pixel);
  return pixel.toDart.toList();
}

bool? _flag(JSObject object, String name) {
  final value = object[name];
  return value.isA<JSBoolean>() ? (value! as JSBoolean).toDart : null;
}
