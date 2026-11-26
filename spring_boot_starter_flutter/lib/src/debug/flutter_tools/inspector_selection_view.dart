import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The widget the inspector selected (`WidgetInspectorService.selection`):
/// its type, its size and position on screen, and its ancestors, the
/// nearest first. Listens to the selection only while it shows.
class InspectorSelectionView extends StatelessWidget {
  /// The view of [selection], by default the inspector's.
  InspectorSelectionView({InspectorSelection? selection, super.key})
    : selection = selection ?? WidgetInspectorService.instance.selection;

  /// How many ancestors are listed.
  static const int ancestorLimit = 24;

  /// The selection shown.
  final InspectorSelection selection;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final element = selection.currentElement;
        if (element == null) {
          return Text(
            'Nothing selected: turn the inspector on, close the panel and '
            'tap the app.',
            style: style.text.copyWith(color: style.muted),
          );
        }
        final ancestors = <String>[];
        element.visitAncestorElements((ancestor) {
          ancestors.add('${ancestor.widget.runtimeType}');
          return ancestors.length < ancestorLimit;
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${element.widget.runtimeType}', style: style.title),
            Text(_geometry(selection.current), style: style.code),
            const SizedBox(height: 6),
            for (final ancestor in ancestors)
              Text('  $ancestor', style: style.code),
          ],
        );
      },
    );
  }

  static String _geometry(RenderObject? object) {
    if (object is! RenderBox || !object.hasSize || !object.attached) {
      return 'no box';
    }
    final size = object.size;
    final at = object.localToGlobal(Offset.zero);
    String n(double v) => v.toStringAsFixed(1);
    return '${n(size.width)} x ${n(size.height)} at (${n(at.dx)}, ${n(at.dy)})';
  }
}
