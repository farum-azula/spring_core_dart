import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show PageUnderlay;
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_screen_web.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_canvas_target.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_screen_layout.dart';

/// Whether the scenes are drawn on the engine's canvas
/// (`spring.flutter.scene.canvas: engine`, the engine started so).
bool get sceneScreenOn => sceneScreenCanvas != null;

/// A view's place on the engine's canvas.
///
/// The canvas is as large as the first view of the page (one no other view
/// is around). When that view fills the screen (a scene behind the whole
/// page) the canvas stands behind Flutter's, and the theme's background
/// steps aside for it ([PageUnderlay]): Flutter draws the page on one
/// canvas. Otherwise it stands in that view, under the page, as a platform
/// view, and Flutter draws the page on one canvas under it and one over
/// it (an iPhone scrolling a page with two scenes drew 52 frames a second
/// so, 60 with the canvas behind). Every view's frame is kept in a
/// texture of its own, and the canvas is drawn anew from them where the
/// views stand: after each beat that drew, and on each frame of Flutter
/// (the page scrolls, a view moves). Nothing is handed over from the
/// engine's canvas to another.
final class SceneScreenPlace implements SceneCanvasTarget {
  /// The place of [view], built again by [rebuild] (it holds the canvas
  /// now, or no longer).
  SceneScreenPlace(this._view, this._rebuild) {
    _screen._join(this);
  }

  final BuildContext _view;
  final void Function() _rebuild;
  final SceneScreenTarget _target = SceneScreenTarget();
  BuildContext? _box;
  bool _visible = true;
  double _ratio = 1;
  Size _screenSize = Size.zero;

  /// The box the scene fills.
  set box(BuildContext? context) => _box = context;

  /// Whether the view is shown (an inactive route's is not).
  set visible(bool value) {
    if (value != _visible) {
      _visible = value;
      _screen._moved();
    }
  }

  /// The device's pixels in a logical one.
  set ratio(double value) => _ratio = value;

  /// The size of the screen the view is on, in logical pixels.
  set screen(Size value) => _screenSize = value;

  @override
  Widget build() => _screen._build(this);

  @override
  bool present(void Function() draw) {
    if (!drawSceneOnScreen(_target, draw)) {
      return false;
    }
    _screen._changed();
    return true;
  }

  @override
  void dispose() {
    _screen._leave(this);
    _target.dispose();
  }

  RenderBox? get _renderBox {
    final context = _box;
    if (context == null || !context.mounted) {
      return null;
    }
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }
}

final _SceneScreen _screen = _SceneScreen();

final class _SceneScreen {
  final List<SceneScreenPlace> _places = [];
  SceneScreenPlace? _host;
  JSObject? _box;
  bool _composing = false;
  bool _dirty = true;
  bool _measured = false;
  bool _behind = false;
  Rect _area = Rect.zero;
  List<SceneScreenPiece> _last = const [];
  int _lastWidth = 0;
  int _lastHeight = 0;
  bool _electing = false;
  bool _following = false;

  void _join(SceneScreenPlace place) {
    _places.add(place);
    _measured = false;
    if (!_following) {
      _following = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (_places.isNotEmpty) {
          _measured = false;
          _compose();
        }
      });
    }
    _elect();
  }

  void _leave(SceneScreenPlace place) {
    _places.remove(place);
    if (identical(_host, place)) {
      _host = null;
      _box = null;
      _behind = false;
      PageUnderlay.showing = false;
    }
    _elect();
    _moved();
  }

  // After the frame: the first place no other place is around holds the
  // canvas.
  void _elect() {
    if (_electing) {
      return;
    }
    _electing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _electing = false;
      final views = {for (final place in _places) place._view};
      SceneScreenPlace? host;
      for (final place in _places) {
        if (!place._view.mounted) {
          continue;
        }
        var inside = false;
        place._view.visitAncestorElements((element) {
          inside = views.contains(element);
          return !inside;
        });
        if (!inside) {
          host = place;
          break;
        }
      }
      final previous = _host;
      if (identical(host, previous)) {
        return;
      }
      _host = host;
      _box = null;
      _measured = false;
      _behind = false;
      PageUnderlay.showing = false;
      if (host != null && _fills(host)) {
        _standBehind();
      }
      previous?._rebuild();
      host?._rebuild();
    });
  }

  Widget _build(SceneScreenPlace place) => !_behind && identical(place, _host)
      ? HtmlElementView.fromTagName(
          tagName: 'div',
          onElementCreated: (element) => _hosted(place, element as JSObject),
        )
      : const SizedBox.shrink();

  void _hosted(SceneScreenPlace place, JSObject box) {
    if (!identical(place, _host) || _behind) {
      return;
    }
    final canvasStyle = sceneScreenCanvas!['style']! as JSObject;
    for (final MapEntry(:key, :value) in const {
      'position': 'absolute',
      'left': '0',
      'top': '0',
      'width': '100%',
      'height': '100%',
    }.entries) {
      canvasStyle[key] = value.toJS;
    }
    final style = box['style']! as JSObject;
    for (final MapEntry(:key, :value) in const {
      'width': '100%',
      'height': '100%',
      'position': 'relative',
      'overflow': 'hidden',
      'pointerEvents': 'none',
    }.entries) {
      style[key] = value.toJS;
    }
    box.callMethod<JSAny?>('appendChild'.toJS, sceneScreenCanvas);
    _box = box;
    _changed();
  }

  // Whether the host fills the screen it is on.
  static bool _fills(SceneScreenPlace host) {
    final box = host._renderBox;
    return box != null && SceneScreenLayout.fills(box, host._screenSize);
  }

  // Behind the page, not in it: the first child of the page's body, under
  // Flutter's view (which comes after it), over the page's own color.
  void _standBehind() {
    final canvas = sceneScreenCanvas;
    if (canvas == null) {
      return;
    }
    _behind = true;
    final style = canvas['style']! as JSObject;
    style['position'] = 'fixed'.toJS;
    final body = (globalContext['document']! as JSObject)['body']! as JSObject;
    body.callMethod<JSAny?>('insertBefore'.toJS, canvas, body['firstChild']);
    _box = body;
    _area = Rect.zero;
    _changed();
  }

  void _placeBehind(Rect area) {
    if (!_behind || area == _area) {
      return;
    }
    _area = area;
    final style = sceneScreenCanvas!['style']! as JSObject;
    style['left'] = '${area.left}px'.toJS;
    style['top'] = '${area.top}px'.toJS;
    style['width'] = '${area.width}px'.toJS;
    style['height'] = '${area.height}px'.toJS;
  }

  // A place came, went or moved: measured again.
  void _moved() {
    _measured = false;
    _changed();
  }

  // A frame of Flutter that is coming draws the canvas anew; without one
  // it is drawn after the task that changed it. Once a frame either way.
  void _changed() {
    _dirty = true;
    if (_composing || SchedulerBinding.instance.hasScheduledFrame) {
      return;
    }
    _composing = true;
    scheduleMicrotask(_compose);
  }

  // Drawn anew when a scene drew or a place moved, not on every frame of
  // Flutter. The places are measured on a frame of Flutter (the page may
  // have moved) and when one came, went or changed; a beat of the scenes
  // draws them where they were.
  void _compose() {
    _composing = false;
    if (!_measured) {
      _measure();
    }
    if (!_dirty || _box == null) {
      return;
    }
    _dirty = false;
    composeSceneScreen(_lastWidth, _lastHeight, _last);
    // The theme's background steps aside once the scene behind the page
    // shows, not before: until then it is what the page stands on.
    if (_behind &&
        !PageUnderlay.shows.value &&
        (_host?._target.drawn ?? false)) {
      PageUnderlay.showing = true;
    }
  }

  void _measure() {
    final host = _host;
    final hostBox = host?._renderBox;
    if (host == null || hostBox == null || _box == null) {
      return;
    }
    _measured = true;
    if (_behind != _fills(host)) {
      // The host came to fill the screen, or no longer does.
      if (_behind) {
        _behind = false;
        _box = null;
        PageUnderlay.showing = false;
      } else {
        _standBehind();
      }
      host._rebuild();
      if (_box == null) {
        return;
      }
    }
    final ratio = host._ratio;
    final area = SceneScreenLayout.areaOf(hostBox);
    _placeBehind(area);
    final pieces = <SceneScreenPiece>[
      for (final place in SceneScreenLayout.painted(
        _places,
        (place) => place._view.mounted ? (place._view as Element).depth : 0,
      ))
        if (place._visible)
          if (place._renderBox case final box?)
            ?SceneScreenLayout.piece(
              place._target,
              box,
              area: area,
              ratio: ratio,
            ),
    ];
    final width = (area.width * ratio).round();
    final height = (area.height * ratio).round();
    if (width == _lastWidth && height == _lastHeight && _same(pieces, _last)) {
      return;
    }
    _dirty = true;
    _last = pieces;
    _lastWidth = width;
    _lastHeight = height;
  }

  static bool _same(List<SceneScreenPiece> a, List<SceneScreenPiece> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
