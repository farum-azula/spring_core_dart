import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

// What the debug panel's Logs tab and the debug console's log pane share
// to select records: the long press that marks one, the keys of a click
// that marks one, and the menu of a text selection.

/// How long a press marks a record: before the text selection's own long
/// press (the platform's) would start selecting.
const debugLogPickPress = Duration(milliseconds: 400);

/// Whether a click now marks a record: ⇧, ⌘ or Ctrl is held.
bool get debugLogPickKeys {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isShiftPressed ||
      keyboard.isMetaPressed ||
      keyboard.isControlPressed;
}

/// A long press of [debugLogPickPress] on [child] calls [onPick]; with
/// [tap], a tap does too.
Widget debugLogPickGestures({
  required VoidCallback onPick,
  required bool tap,
  required Widget child,
}) => RawGestureDetector(
  behavior: HitTestBehavior.opaque,
  gestures: {
    LongPressGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: debugLogPickPress),
          (recognizer) => recognizer.onLongPress = onPick,
        ),
    if (tap)
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (recognizer) => recognizer.onTap = onPick,
          ),
  },
  child: child,
);

/// The menu of a text selection of records ([region]'s): a chip per item
/// (Copy, Select all) at the selection, in the overlay of [context].
Widget debugLogSelectionMenu(
  BuildContext context,
  SelectableRegionState region,
) {
  final anchor = region.contextMenuAnchors.primaryAnchor;
  final overlay = Overlay.of(context).context.findRenderObject();
  final at = overlay is RenderBox ? overlay.globalToLocal(anchor) : anchor;
  return Stack(
    children: [
      Positioned(
        left: at.dx,
        top: at.dy,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in region.contextMenuButtonItems)
              DebugChip(
                switch (item.type) {
                  ContextMenuButtonType.copy => 'Copy',
                  ContextMenuButtonType.selectAll => 'Select all',
                  _ => item.label ?? item.type.name,
                },
                onTap: item.onPressed ?? () {},
              ),
          ],
        ),
      ),
    ],
  );
}
