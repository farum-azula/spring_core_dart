import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_screen_layout.dart';

const int _framebuffer = 0x8D40;
const int _drawFramebuffer = 0x8CA9;
const int _colorAttachment0 = 0x8CE0;
const int _texture2d = 0x0DE1;
const int _texture0 = 0x84C0;
const int _rgba = 0x1908;
const int _rgba8 = 0x8058;
const int _unsignedByte = 0x1401;
const int _linear = 0x2601;
const int _clampToEdge = 0x812F;
const int _textureMinFilter = 0x2801;
const int _textureMagFilter = 0x2800;
const int _textureWrapS = 0x2802;
const int _textureWrapT = 0x2803;
const int _colorBufferBit = 0x4000;
const int _blend = 0x0BE2;
const int _scissorTest = 0x0C11;
const int _depthTest = 0x0B71;
const int _cullFace = 0x0B44;
const int _stencilTest = 0x0B90;
const int _one = 1;
const int _oneMinusSrcAlpha = 0x0303;
const int _funcAdd = 0x8006;
const int _triangleStrip = 0x0005;
const int _vertexShader = 0x8B31;
const int _fragmentShader = 0x8B30;
const int _compileStatus = 0x8B81;
const int _linkStatus = 0x8B82;

const String _vertex = '''#version 300 es
uniform vec4 u_rect;
out vec2 v_uv;
void main() {
  vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
  v_uv = corner;
  gl_Position = vec4(mix(u_rect.xy, u_rect.zw, corner), 0.0, 1.0);
}
''';

const String _fragment = '''#version 300 es
precision mediump float;
uniform sampler2D u_frame;
in vec2 v_uv;
out vec4 color;
void main() {
  color = texture(u_frame, v_uv);
}
''';

@JS('OffscreenCanvas')
extension type _Offscreen._(JSObject _) implements JSObject {
  external factory _Offscreen(int width, int height);

  external JSObject? getContext(String type);

  external JSObject transferToImageBitmap();
}

JSObject? _canvas;
JSObject? _gl;
JSFunction? _realWidth;
JSFunction? _realHeight;
JSFunction? _resizeWidth;
JSFunction? _resizeHeight;
int _askedWidth = 1;
int _askedHeight = 1;
SceneScreenTarget? _drawing;
bool _drew = false;
_Offscreen? _stand;
JSObject? _program;
JSObject? _vao;
JSObject? _rect;
JSObject? _frame;

/// The engine's canvas, when the page shows it as it is
/// (`spring.flutter.scene.canvas: engine`); `null` otherwise.
JSObject? get sceneScreenCanvas => _canvas;

/// Runs [start], the engine's start, with the engine's canvas made one the
/// page shows: a canvas element, not an `OffscreenCanvas`, which the
/// browser puts on the screen as it puts a game's, its drawing buffer as
/// it is. Nothing is handed over from it: each scene's frame is kept in
/// a texture of the scene's own ([SceneScreenTarget]), and the scenes are
/// drawn from them where they stand ([composeSceneScreen]).
///
/// The engine makes its canvas the first time its GPU context is asked
/// for, as `new OffscreenCanvas(1, 1)`: while [start] runs, that one call
/// is answered with the canvas element.
Future<void> startOnEngineCanvas(Future<void> Function() start) async {
  final restore = _catchEngineCanvas();
  try {
    await start();
  } finally {
    restore();
  }
  if (_canvas == null) {
    throw StateError(
      'The engine made no canvas of its own while it started: its scenes '
      'cannot be drawn on it.',
    );
  }
}

void Function() _catchEngineCanvas() {
  final original = globalContext['OffscreenCanvas']! as JSObject;
  final reflect = globalContext['Reflect']! as JSObject;
  var restored = false;
  void restore() {
    if (!restored) {
      restored = true;
      globalContext['OffscreenCanvas'] = original;
    }
  }

  final handler = JSObject()
    ..['construct'] =
        ((JSObject target, JSArray<JSAny?> arguments, JSAny? newTarget) {
          if (_canvas == null && _unit(arguments)) {
            restore();
            return _make();
          }
          return reflect.callMethod<JSObject>(
            'construct'.toJS,
            target,
            arguments,
            newTarget,
          );
        }).toJS;
  globalContext['OffscreenCanvas'] = (globalContext['Proxy']! as JSFunction)
      .callAsConstructor<JSObject>(original, handler);
  return restore;
}

bool _unit(JSArray<JSAny?> arguments) {
  if (arguments.length != 2) {
    return false;
  }
  for (var i = 0; i < 2; i++) {
    final value = arguments[i];
    if (!value.isA<JSNumber>() || (value! as JSNumber).toDartInt != 1) {
      return false;
    }
  }
  return true;
}

JSObject _make() {
  final canvas = (globalContext['document']! as JSObject).callMethod<JSObject>(
    'createElement'.toJS,
    'canvas'.toJS,
  );
  final style = canvas['style']! as JSObject;
  for (final MapEntry(:key, :value) in const {
    'position': 'absolute',
    'left': '0',
    'top': '0',
    'width': '100%',
    'height': '100%',
    'display': 'block',
    'pointerEvents': 'none',
  }.entries) {
    style[key] = value.toJS;
  }
  canvas['width'] = 1.toJS;
  canvas['height'] = 1.toJS;
  _askedSize(canvas);
  _drawnAnewEachTime(canvas);
  canvas['transferToImageBitmap'] = _standIn.toJS;
  _canvas = canvas;
  return canvas;
}

// The canvas is drawn whole each time ([composeSceneScreen]): its buffer
// need not be kept after the browser shows it, which spares a copy of the
// whole canvas each time it is shown.
void _drawnAnewEachTime(JSObject canvas) {
  final object = globalContext['Object']! as JSObject;
  final getContext =
      _descriptor(
            object,
            object.callMethod<JSObject>('getPrototypeOf'.toJS, canvas),
            'getContext'.toJS,
          )['value']!
          as JSFunction;
  canvas['getContext'] = ((JSAny? type, JSAny? attributes) {
    final asked = JSObject();
    if (attributes.isA<JSObject>()) {
      object.callMethod<JSAny?>('assign'.toJS, asked, attributes);
    }
    asked['preserveDrawingBuffer'] = false.toJS;
    return getContext.callAsFunction(canvas, type, asked);
  }).toJS;
}

// The engine sizes its canvas to each scene it hands over; this one is
// the page's: the engine is told the size it set, and the canvas keeps
// the one [composeSceneScreen] gives it.
void _askedSize(JSObject canvas) {
  final object = globalContext['Object']! as JSObject;
  final prototype = object.callMethod<JSObject>(
    'getPrototypeOf'.toJS,
    canvas,
  );
  for (final width in [true, false]) {
    final name = (width ? 'width' : 'height').toJS;
    final own = _descriptor(object, prototype, name);
    if (width) {
      _realWidth = own['get']! as JSFunction;
      _resizeWidth = own['set']! as JSFunction;
    } else {
      _realHeight = own['get']! as JSFunction;
      _resizeHeight = own['set']! as JSFunction;
    }
    object.callMethod<JSAny?>(
      'defineProperty'.toJS,
      canvas,
      name,
      JSObject()
        ..['configurable'] = true.toJS
        ..['get'] = (() => (width ? _askedWidth : _askedHeight).toJS).toJS
        ..['set'] = ((JSNumber value) {
          if (width) {
            _askedWidth = value.toDartInt;
          } else {
            _askedHeight = value.toDartInt;
          }
        }).toJS,
    );
  }
}

// The descriptor of [name] on [prototype] or the first of its own
// prototypes that has it.
JSObject _descriptor(JSObject object, JSObject prototype, JSString name) {
  JSObject? current = prototype;
  while (current != null) {
    final own = object.callMethod<JSAny?>(
      'getOwnPropertyDescriptor'.toJS,
      current,
      name,
    );
    if (own.isA<JSObject>()) {
      return own! as JSObject;
    }
    final next = object.callMethod<JSAny?>('getPrototypeOf'.toJS, current);
    current = next.isA<JSObject>() ? next! as JSObject : null;
  }
  throw StateError('A canvas without its ${name.toDart}.');
}

// Flutter is handed a bitmap of one pixel for the frame it would have
// drawn: the scene is on the engine's canvas.
JSObject _standIn() {
  final stand = _stand ??= _Offscreen(1, 1)..getContext('2d');
  return stand.transferToImageBitmap();
}

JSObject _context() {
  final existing = _gl;
  if (existing != null) {
    return existing;
  }
  final gl = _canvas!.callMethod<JSObject>(
    'getContext'.toJS,
    'webgl2'.toJS,
    JSObject(),
  );
  final blit = gl['blitFramebuffer']! as JSFunction;
  // The engine's present: into the texture of the scene that draws, and
  // nowhere else (nothing but [composeSceneScreen] draws on the canvas).
  gl['blitFramebuffer'] =
      ((
            JSAny? x0,
            JSAny? y0,
            JSAny? x1,
            JSAny? y1,
            JSAny? toX0,
            JSAny? toY0,
            JSAny? toX1,
            JSAny? toY1,
            JSAny? mask,
            JSAny? filter,
          ) {
            final target = _drawing;
            if (target == null) {
              return;
            }
            target._fit(gl, _askedWidth, _askedHeight);
            gl.callMethodVarArgs<JSAny?>('bindFramebuffer'.toJS, [
              _drawFramebuffer.toJS,
              target._framebuffer,
            ]);
            blit.callMethodVarArgs<JSAny?>('call'.toJS, [
              gl,
              x0,
              y0,
              x1,
              y1,
              toX0,
              toY0,
              toX1,
              toY1,
              mask,
              filter,
            ]);
            gl.callMethodVarArgs<JSAny?>('bindFramebuffer'.toJS, [
              _drawFramebuffer.toJS,
              null,
            ]);
            target._drawn = true;
            _drew = true;
          })
          .toJS;
  _gl = gl;
  return gl;
}

/// A scene's last frame on the GPU, for [composeSceneScreen].
final class SceneScreenTarget {
  JSObject? _texture;
  JSObject? _framebuffer;
  int _width = 0;
  int _height = 0;
  bool _drawn = false;

  /// Whether it holds a frame.
  bool get drawn => _drawn;

  void _fit(JSObject gl, int width, int height) {
    if (_texture == null) {
      final texture = gl.callMethod<JSObject>('createTexture'.toJS);
      gl.callMethodVarArgs<JSAny?>('bindTexture'.toJS, [
        _texture2d.toJS,
        texture,
      ]);
      for (final (name, value) in const [
        (_textureMinFilter, _linear),
        (_textureMagFilter, _linear),
        (_textureWrapS, _clampToEdge),
        (_textureWrapT, _clampToEdge),
      ]) {
        gl.callMethodVarArgs<JSAny?>('texParameteri'.toJS, [
          _texture2d.toJS,
          name.toJS,
          value.toJS,
        ]);
      }
      final framebuffer = gl.callMethod<JSObject>('createFramebuffer'.toJS);
      _texture = texture;
      _framebuffer = framebuffer;
      _width = 0;
      _height = 0;
    }
    if (width == _width && height == _height) {
      return;
    }
    gl.callMethodVarArgs<JSAny?>('bindTexture'.toJS, [
      _texture2d.toJS,
      _texture,
    ]);
    gl.callMethodVarArgs<JSAny?>('texImage2D'.toJS, [
      _texture2d.toJS,
      0.toJS,
      _rgba8.toJS,
      width.toJS,
      height.toJS,
      0.toJS,
      _rgba.toJS,
      _unsignedByte.toJS,
      null,
    ]);
    gl.callMethodVarArgs<JSAny?>('bindTexture'.toJS, [_texture2d.toJS, null]);
    gl.callMethodVarArgs<JSAny?>('bindFramebuffer'.toJS, [
      _drawFramebuffer.toJS,
      _framebuffer,
    ]);
    gl.callMethodVarArgs<JSAny?>('framebufferTexture2D'.toJS, [
      _drawFramebuffer.toJS,
      _colorAttachment0.toJS,
      _texture2d.toJS,
      _texture,
      0.toJS,
    ]);
    _width = width;
    _height = height;
  }

  /// Frees its texture.
  void dispose() {
    final gl = _gl;
    if (gl != null) {
      gl.callMethodVarArgs<JSAny?>('deleteTexture'.toJS, [_texture]);
      gl.callMethodVarArgs<JSAny?>('deleteFramebuffer'.toJS, [_framebuffer]);
    }
    _texture = null;
    _framebuffer = null;
    _drawn = false;
  }
}

/// Has the engine draw [target]'s scene by [draw] (a render of the scene)
/// into [target]; `false` when it drew nothing.
bool drawSceneOnScreen(SceneScreenTarget target, void Function() draw) {
  _context();
  _drawing = target;
  _drew = false;
  try {
    draw();
  } finally {
    _drawing = null;
  }
  return _drew;
}

/// Where a scene's frame goes on the engine's canvas.
typedef SceneScreenPiece = ScenePiece<SceneScreenTarget>;

/// Draws the engine's canvas anew, [width] by [height] pixels: the frames
/// of [pieces], in their order, each over the ones before.
void composeSceneScreen(int width, int height, List<SceneScreenPiece> pieces) {
  final canvas = _canvas;
  if (canvas == null || width <= 0 || height <= 0) {
    return;
  }
  final gl = _context();
  if ((_realWidth!.callAsFunction(canvas)! as JSNumber).toDartInt != width) {
    _resizeWidth!.callAsFunction(canvas, width.toJS);
  }
  if ((_realHeight!.callAsFunction(canvas)! as JSNumber).toDartInt != height) {
    _resizeHeight!.callAsFunction(canvas, height.toJS);
  }
  final program = _program ??= _link(gl);
  void call(String name, [JSAny? a, JSAny? b, JSAny? c, JSAny? d]) {
    gl.callMethodVarArgs<JSAny?>(name.toJS, [?a, ?b, ?c, ?d]);
  }

  gl.callMethodVarArgs<JSAny?>('bindFramebuffer'.toJS, [
    _framebuffer.toJS,
    null,
  ]);
  call('viewport', 0.toJS, 0.toJS, width.toJS, height.toJS);
  call('disable', _scissorTest.toJS);
  call('disable', _depthTest.toJS);
  call('disable', _cullFace.toJS);
  call('disable', _stencilTest.toJS);
  call('colorMask', true.toJS, true.toJS, true.toJS, true.toJS);
  call('clearColor', 0.toJS, 0.toJS, 0.toJS, 0.toJS);
  call('clear', _colorBufferBit.toJS);
  if (pieces.isNotEmpty) {
    call('useProgram', program);
    gl.callMethodVarArgs<JSAny?>('bindVertexArray'.toJS, [_vao]);
    call('activeTexture', _texture0.toJS);
    gl.callMethodVarArgs<JSAny?>('uniform1i'.toJS, [_frame, 0.toJS]);
    call('enable', _blend.toJS);
    call('blendEquation', _funcAdd.toJS);
    call('blendFunc', _one.toJS, _oneMinusSrcAlpha.toJS);
    call('enable', _scissorTest.toJS);
    for (final piece in pieces) {
      if (!piece.target._drawn) {
        continue;
      }
      call(
        'scissor',
        piece.clipLeft.toJS,
        (height - piece.clipBottom).toJS,
        (piece.clipRight - piece.clipLeft).toJS,
        (piece.clipBottom - piece.clipTop).toJS,
      );
      gl.callMethodVarArgs<JSAny?>('bindTexture'.toJS, [
        _texture2d.toJS,
        piece.target._texture,
      ]);
      gl.callMethodVarArgs<JSAny?>('uniform4f'.toJS, [
        _rect,
        (piece.left / width * 2 - 1).toJS,
        (1 - piece.bottom / height * 2).toJS,
        (piece.right / width * 2 - 1).toJS,
        (1 - piece.top / height * 2).toJS,
      ]);
      call('drawArrays', _triangleStrip.toJS, 0.toJS, 4.toJS);
    }
    call('disable', _blend.toJS);
    call('disable', _scissorTest.toJS);
    gl.callMethodVarArgs<JSAny?>('bindTexture'.toJS, [_texture2d.toJS, null]);
    gl.callMethodVarArgs<JSAny?>('bindVertexArray'.toJS, [null]);
    gl.callMethodVarArgs<JSAny?>('useProgram'.toJS, [null]);
  }
}

JSObject _link(JSObject gl) {
  JSObject shader(int type, String source) {
    final shader = gl.callMethod<JSObject>('createShader'.toJS, type.toJS);
    gl.callMethodVarArgs<JSAny?>('shaderSource'.toJS, [shader, source.toJS]);
    gl.callMethodVarArgs<JSAny?>('compileShader'.toJS, [shader]);
    final compiled = gl.callMethodVarArgs<JSAny?>('getShaderParameter'.toJS, [
      shader,
      _compileStatus.toJS,
    ]);
    if (compiled.isA<JSBoolean>() && !(compiled! as JSBoolean).toDart) {
      throw StateError(
        'The engine canvas shader did not compile: '
        '${gl.callMethod<JSString?>('getShaderInfoLog'.toJS, shader)?.toDart}',
      );
    }
    return shader;
  }

  final program = gl.callMethod<JSObject>('createProgram'.toJS);
  gl.callMethodVarArgs<JSAny?>('attachShader'.toJS, [
    program,
    shader(_vertexShader, _vertex),
  ]);
  gl.callMethodVarArgs<JSAny?>('attachShader'.toJS, [
    program,
    shader(_fragmentShader, _fragment),
  ]);
  gl.callMethodVarArgs<JSAny?>('linkProgram'.toJS, [program]);
  final linked = gl.callMethodVarArgs<JSAny?>('getProgramParameter'.toJS, [
    program,
    _linkStatus.toJS,
  ]);
  if (linked.isA<JSBoolean>() && !(linked! as JSBoolean).toDart) {
    throw StateError(
      'The engine canvas program did not link: '
      '${gl.callMethod<JSString?>('getProgramInfoLog'.toJS, program)?.toDart}',
    );
  }
  _vao = gl.callMethod<JSObject>('createVertexArray'.toJS);
  _rect = gl.callMethod<JSObject>(
    'getUniformLocation'.toJS,
    program,
    'u_rect'.toJS,
  );
  _frame = gl.callMethod<JSObject>(
    'getUniformLocation'.toJS,
    program,
    'u_frame'.toJS,
  );
  return program;
}
