import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart'
    show DebugOverlaySnap;

/// Where a moved debug overlay is kept: the keeper of the `drag` feature.
abstract interface class DebugOverlayPlaces {
  /// The places kept, as JSON; `null` when none.
  Future<String?> read();

  /// Keeps [places].
  Future<void> write(String places);
}

/// The places kept in the app's support files (`spring/debug-overlays`),
/// as the theme chosen is: a browser's storage on the web, a file on a
/// device.
final class FileDebugOverlayPlaces implements DebugOverlayPlaces {
  /// The places in [files].
  const FileDebugOverlayPlaces(this.files);

  /// The app's files.
  final FileTemplate files;

  static const _path = 'spring/debug-overlays';

  @override
  Future<String?> read() => files.support.readString(_path);

  @override
  Future<void> write(String places) => files.write(_path, places);
}

/// The debug feature `drag` (`spring.flutter.debug.drag.enabled`): a debug
/// overlay is moved by dragging it, with a mouse at once, on a touch screen
/// after a long press. Dropped, it joins the nearest corner (`snap:
/// corners`, the default) or stays where it was dropped (`free`); with
/// `remember` the place is kept for the next start. The debug panel's
/// overlays section puts them all back ([reset]).
///
/// Spring has no counterpart.
final class DebugOverlayDrag extends ChangeNotifier
    implements DebugOverlayPlacement {
  /// Moves overlays as [snap] says, keeping their places in [places] when
  /// given.
  DebugOverlayDrag({this.snap = DebugOverlaySnap.corners, this.places}) {
    unawaited(_restore());
  }

  /// Where a dropped overlay goes.
  final DebugOverlaySnap snap;

  /// Where the places are kept; `null`: for this run only.
  final DebugOverlayPlaces? places;

  final _corners = <String, DebugOverlayCorner>{};
  final _free = <String, Offset>{};
  // The overlay being dragged and where, from the top left, a fraction of
  // the screen each way.
  (String, Offset)? _dragging;

  @override
  DebugOverlayCorner cornerOf(DebugOverlay overlay) =>
      _corners[overlay.id] ?? overlay.corner;

  @override
  Offset? freeOf(DebugOverlay overlay) {
    if (_dragging case (final id, final at) when id == overlay.id) {
      return at;
    }
    return _free[overlay.id];
  }

  @override
  Widget movable(DebugOverlay overlay, Widget child) =>
      // One key per overlay: moved from its corner to under the finger
      // and back, it keeps its state, and the drag goes on.
      _Movable(
        key: GlobalObjectKey(overlay),
        drag: this,
        overlay: overlay,
        child: child,
      );

  @override
  void reset() {
    _corners.clear();
    _free.clear();
    _dragging = null;
    notifyListeners();
    unawaited(_keep());
  }

  void _move(DebugOverlay overlay, Offset at) {
    _dragging = (overlay.id, _clamped(at));
    notifyListeners();
  }

  void _drop(DebugOverlay overlay, Offset at, Size size) {
    _dragging = null;
    final clamped = _clamped(at);
    if (snap == DebugOverlaySnap.free) {
      _free[overlay.id] = clamped;
      _corners.remove(overlay.id);
    } else {
      // The corner nearest the overlay's middle.
      final middle = clamped + Offset(size.width / 2, size.height / 2);
      final top = middle.dy < 0.5;
      final left = middle.dx < 0.5;
      _corners[overlay.id] = top
          ? (left ? FrameMeterPosition.topLeft : FrameMeterPosition.topRight)
          : (left
                ? FrameMeterPosition.bottomLeft
                : FrameMeterPosition.bottomRight);
      _free.remove(overlay.id);
    }
    notifyListeners();
    unawaited(_keep());
  }

  static Offset _clamped(Offset at) =>
      Offset(at.dx.clamp(0, 0.9), at.dy.clamp(0, 0.9));

  Future<void> _restore() async {
    final text = await places?.read();
    if (text == null) {
      return;
    }
    try {
      final json = jsonDecode(text) as Map<String, Object?>;
      for (final MapEntry(:key, :value)
          in (json['corners'] as Map? ?? const {}).entries) {
        final corner = FrameMeterPosition.values
            .where((c) => c.name == value)
            .firstOrNull;
        if (corner != null) {
          _corners['$key'] = corner;
        }
      }
      for (final MapEntry(:key, :value)
          in (json['free'] as Map? ?? const {}).entries) {
        final xy = (value as List).cast<num>();
        _free['$key'] = Offset(xy[0].toDouble(), xy[1].toDouble());
      }
      notifyListeners();
    } on Object {
      // A place kept by another version: the overlays in their corners.
    }
  }

  Future<void> _keep() async => places?.write(
    jsonEncode({
      'corners': {
        for (final MapEntry(:key, :value) in _corners.entries) key: value.name,
      },
      'free': {
        for (final MapEntry(:key, :value) in _free.entries)
          key: [value.dx, value.dy],
      },
    }),
  );
}

// An overlay to drag: a mouse drags it at once, a finger after a long
// press, so a tap and a swipe between pages stay what they were.
class _Movable extends StatelessWidget {
  const _Movable({
    required this.drag,
    required this.overlay,
    required this.child,
    super.key,
  });

  final DebugOverlayDrag drag;
  final DebugOverlay overlay;
  final Widget child;

  Offset _at(BuildContext context, Offset global, Offset grab) {
    final screen = MediaQuery.sizeOf(context);
    final topLeft = global - grab;
    return Offset(topLeft.dx / screen.width, topLeft.dy / screen.height);
  }

  Size _size(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? overlay.size;
    return Size(size.width / screen.width, size.height / screen.height);
  }

  @override
  Widget build(BuildContext context) {
    var grab = Offset.zero;
    var last = Offset.zero;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
        onPanStart: (details) {
          grab = details.localPosition;
          last = details.globalPosition;
        },
        onPanUpdate: (details) {
          last = details.globalPosition;
          drag._move(overlay, _at(context, last, grab));
        },
        onPanEnd: (_) =>
            drag._drop(overlay, _at(context, last, grab), _size(context)),
        child: GestureDetector(
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
          },
          onLongPressStart: (details) {
            grab = details.localPosition;
            last = details.globalPosition;
          },
          onLongPressMoveUpdate: (details) {
            last = details.globalPosition;
            drag._move(overlay, _at(context, last, grab));
          },
          onLongPressEnd: (_) =>
              drag._drop(overlay, _at(context, last, grab), _size(context)),
          child: child,
        ),
      ),
    );
  }
}
