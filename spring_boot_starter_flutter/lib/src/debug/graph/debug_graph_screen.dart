import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_markers.dart';

/// Whether a widget is on the screen, for the application graph's "On
/// screen" scope: its box is laid out, attached and in the app's window,
/// once every clip above it (a scroll view, a `ClipRect`) has cut it; no
/// ancestor leaves it unpainted (`Offstage`, an `IndexedStack`'s other
/// children, an opacity of 0, a list's child out of its view) and no
/// `TickerMode` above it is off (a route under an opaque one, a hidden
/// tab). A widget under [PaintedElsewhere] (a 3D scene's, drawn on the
/// engine's canvas) counts by the place of the marked widget; a widget of
/// no box of its own counts by the nearest box above it; one in a tree of
/// its own, whose place cannot be read, as shown. What is drawn over it
/// does not hide it: the debug panel over the app leaves the app's widgets
/// on the screen.
///
/// Read only while the graph shows, a few times a second at most, outside
/// a frame's layout; each call walks from the widget to the root.
abstract final class DebugGraphScreen {
  /// Whether the widget of [context] is on the screen.
  static bool shows(BuildContext context) {
    if (context is Element && !context.mounted) {
      return false;
    }
    var off = false;
    Element? marked;
    context.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is TickerMode && !widget.enabled) {
        off = true;
        return false;
      }
      if (marked == null && widget.key is PaintedElsewhere) {
        marked = ancestor;
      }
      return true;
    });
    if (off) {
      return false;
    }
    RenderObject? object;
    try {
      object = (marked ?? context).findRenderObject();
      if (object is! RenderBox) {
        object = (marked ?? context)
            .findAncestorRenderObjectOfType<RenderBox>();
      }
    } on Object {
      return false;
    }
    if (object == null) {
      return true;
    }
    return boxShows(object);
  }

  /// Whether [object] is in the window once every clip above it has cut it
  /// and every ancestor paints it; a box of no size counts by its place.
  static bool boxShows(RenderObject object) {
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return false;
    }
    var rect =
        Offset.zero &
        Size(
          object.size.width < 1 ? 1 : object.size.width,
          object.size.height < 1 ? 1 : object.size.height,
        );
    RenderObject child = object;
    var parent = child.parent;
    while (parent != null) {
      if (parent is RenderView) {
        return rect.overlaps(Offset.zero & parent.size);
      }
      if (!parent.paintsChild(child)) {
        return false;
      }
      final transform = Matrix4.identity();
      parent.applyPaintTransform(child, transform);
      rect = MatrixUtils.transformRect(transform, rect);
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect.intersect(clip);
        if (rect.width <= 0 || rect.height <= 0) {
          return false;
        }
      }
      child = parent;
      parent = child.parent;
    }
    // Its tree's root is not the window's: a tree of its own.
    return true;
  }

  /// The render objects of the windows that are on the screen, in one pass
  /// from each window down (for many widgets at once, as the widgets layer
  /// reads them): a child is left out when its parent does not paint it,
  /// and is on the screen when its paint bounds, cut by every clip above,
  /// meet the window. What is not laid out yet is left out, with what is
  /// under it.
  static Set<RenderObject> shownObjects(Iterable<RenderView> views) {
    final shown = Set<RenderObject>.identity();
    for (final view in views) {
      final window = Offset.zero & view.size;
      view.visitChildren((child) {
        _visit(child, Matrix4.identity(), window, shown);
      });
    }
    return shown;
  }

  static void _visit(
    RenderObject object,
    Matrix4 transform,
    Rect clip,
    Set<RenderObject> shown,
  ) {
    // Not laid out yet (made in the frame being built): it has no place to
    // read, nor have its children; the next walk, after the frame, reads it.
    if (!object.attached ||
        (object is RenderBox && !object.hasSize) ||
        (object is RenderSliver && object.geometry == null)) {
      return;
    }
    final Rect bounds;
    try {
      bounds = object.paintBounds;
    } on Object {
      return;
    }
    final inWindow = MatrixUtils.transformRect(
      transform,
      bounds.isEmpty ? Rect.fromLTWH(bounds.left, bounds.top, 1, 1) : bounds,
    );
    if (inWindow.overlaps(clip)) {
      shown.add(object);
    }
    object.visitChildren((child) {
      if (!object.paintsChild(child)) {
        return;
      }
      final own = object.describeApproximatePaintClip(child);
      var childClip = clip;
      if (own != null) {
        childClip = clip.intersect(MatrixUtils.transformRect(transform, own));
        if (childClip.width <= 0 || childClip.height <= 0) {
          return;
        }
      }
      final childTransform = transform.clone();
      object.applyPaintTransform(child, childTransform);
      _visit(child, childTransform, childClip, shown);
    });
  }
}
