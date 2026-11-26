import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_markers.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The outline of a widget tapped in the widgets layer, over the app: an
/// entry of the app's first `Overlay` (the navigator's) while a node is
/// selected, under the debug panel and over the app's pages, so it shows
/// with the console's pane; the widget selected in Flutter's inspector too
/// (the Flutter tab shows it). Nothing is in the tree while none is.
///
/// The outline follows the widget (a scroll, a layout change, an
/// animation): after each frame while it shows, its place is read again
/// and the outline moved when it changed; it goes when the widget leaves
/// the tree. No frame is asked for and nothing runs while none shows.
final class WidgetHighlight {
  OverlayEntry? _entry;
  Element? _element;
  OverlayState? _overlay;
  Rect _shown = Rect.zero;
  int _generation = 0;

  /// The outlined rectangle, in the app's coordinates.
  Rect? rect;

  /// Outlines [element], in the first overlay under [root].
  void show(Element element, Element? root) {
    hide();
    final placed = _place(element, null);
    if (placed == null) {
      return;
    }
    rect = placed.$1;
    try {
      WidgetInspectorService.instance.selection.currentElement = element;
    } on Object {
      // The inspector is not there in this build.
    }
    final overlay = _overlayUnder(root);
    if (overlay == null) {
      return;
    }
    _element = element;
    _overlay = overlay;
    _shown = _place(element, overlay)!.$2;
    final entry = _entry = OverlayEntry(
      builder: (context) {
        final style = DebugStyle.of(context);
        return Positioned.fromRect(
          key: const DebugToolSubtree(),
          rect: _shown.inflate(1),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.12),
                border: Border.all(color: style.accent, width: 2),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    _follow(_generation);
  }

  // The widget's rectangle in the app's coordinates and in [overlay]'s;
  // `null` when it has no box laid out.
  static (Rect, Rect)? _place(Element element, OverlayState? overlay) {
    if (!element.mounted) {
      return null;
    }
    final box = element.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    final global = box.localToGlobal(Offset.zero) & box.size;
    final overlayBox = overlay?.context.findRenderObject();
    final local = overlayBox is RenderBox && overlayBox.hasSize
        ? Rect.fromPoints(
            overlayBox.globalToLocal(global.topLeft),
            overlayBox.globalToLocal(global.bottomRight),
          )
        : global;
    return (global, local);
  }

  // After each frame while the outline of [generation] shows: moved with
  // its widget, taken away when the widget is gone.
  void _follow(int generation) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final element = _element;
      final entry = _entry;
      if (generation != _generation || element == null || entry == null) {
        return;
      }
      final placed = _place(element, _overlay);
      if (placed == null) {
        if (!element.mounted) {
          hide();
          return;
        }
      } else if (placed.$2 != _shown) {
        rect = placed.$1;
        _shown = placed.$2;
        entry.markNeedsBuild();
      }
      _follow(generation);
    });
  }

  /// Takes the outline away.
  void hide() {
    _generation++;
    final overlay = _overlay;
    _element = null;
    _overlay = null;
    rect = null;
    final entry = _entry;
    _entry = null;
    // Inserted, the entry is removed even before a frame has built it (two
    // taps within one frame); an overlay gone took its entries with it.
    if (entry != null && overlay != null && overlay.mounted) {
      entry
        ..remove()
        ..dispose();
    }
  }

  // The first overlay of the app, down from [root], past the debug tools.
  static OverlayState? _overlayUnder(Element? root) {
    if (root == null) {
      return null;
    }
    OverlayState? found;
    void visit(Element element) {
      if (found != null || element.widget.key is DebugToolSubtree) {
        return;
      }
      if (element is StatefulElement && element.state is OverlayState) {
        found = element.state as OverlayState;
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }
}
