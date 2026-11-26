import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_markers.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel_menu.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// Puts the debug panel over the app, inside the app's own `builder`,
/// when it is open. Applied late, over the overlays, and inside the debug
/// theme's scope (`DebugThemeCustomizer`, applied last).
final class DebugPanelCustomizer implements FlutterAppCustomizer, Ordered {
  /// The panel [panel] with [sections].
  const DebugPanelCustomizer(this.panel, this.sections);

  /// The panel's state.
  final DebugPanel panel;

  /// Its sections, in order.
  final List<DebugPanelSection> sections;

  @override
  int get order => Ordered.lowestPrecedence - 1;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => DebugHost(
      panel: panel,
      sections: sections,
      child: inner == null ? child! : inner(context, child),
    );
  }
}

/// The app with the debug panel over it.
class DebugHost extends StatelessWidget {
  /// [child] under the panel [panel].
  const DebugHost({
    required this.panel,
    required this.sections,
    required this.child,
    super.key,
  });

  /// The panel's state.
  final DebugPanel panel;

  /// Its sections.
  final List<DebugPanelSection> sections;

  /// The app.
  final Widget child;

  /// The header's button that opens the menu on a phone.
  static const menuButtonKey = ValueKey('debug.panel.menu-button');

  /// The menu opened as a drawer on a phone.
  static const drawerKey = ValueKey('debug.panel.drawer');

  /// The scrim over the content while the drawer is open; a tap closes it.
  static const scrimKey = ValueKey('debug.panel.scrim');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: panel,
    child: child,
    builder: (context, app) => Stack(
      fit: StackFit.expand,
      children: [
        app!,
        if (panel.isOpen)
          Positioned.fill(
            key: const DebugToolSubtree(),
            child: _Panel(panel: panel, sections: sections),
          ),
      ],
    ),
  );
}

// The section shown is the panel's, so a closed panel opens on it again.
// A screen as wide as the console's phone width has the menu always open
// on the left; a narrower one opens it as a drawer from the header.
class _Panel extends StatefulWidget {
  const _Panel({required this.panel, required this.sections});

  final DebugPanel panel;
  final List<DebugPanelSection> sections;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  bool _drawer = false;

  // How far from the left edge a swipe opens the drawer.
  static const double _edge = 20;

  void _openDrawer() => setState(() => _drawer = true);

  void _closeDrawer() => setState(() => _drawer = false);

  void _pick(int index) {
    widget.panel.tab = index;
    _closeDrawer();
  }

  void _swipeOpen(DragEndDetails details) {
    if ((details.primaryVelocity ?? 0) > 0) {
      _openDrawer();
    }
  }

  void _swipeClosed(DragEndDetails details) {
    if ((details.primaryVelocity ?? 0) < 0) {
      _closeDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final sections = widget.sections;
    final selected = sections.isEmpty ? 0 : widget.panel.tab % sections.length;
    final shown = sections.isEmpty ? null : sections[selected];
    final content = shown == null
        ? Text('No sections', style: style.text)
        : KeyedSubtree(key: ValueKey(shown), child: shown.build(context));
    DebugPanelMenu menu() => DebugPanelMenu(
      sections: sections,
      selected: selected,
      onSelected: _pick,
    );
    return ColoredBox(
      color: style.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final phone = constraints.maxWidth < DebugLayout.phoneWidth;
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (phone)
                            DebugPanelMenuButton(
                              key: DebugHost.menuButtonKey,
                              onTap: _openDrawer,
                            ),
                          Expanded(child: Text('Debug', style: style.title)),
                          DebugChip('Close', onTap: widget.panel.close),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(height: 1, color: style.line),
                      const SizedBox(height: 12),
                      Expanded(
                        child: phone
                            ? content
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  menu(),
                                  Container(width: 1, color: style.line),
                                  const SizedBox(width: 12),
                                  Expanded(child: content),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                if (phone && !_drawer)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _edge,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _swipeOpen,
                    ),
                  ),
                if (phone && _drawer) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      key: DebugHost.scrimKey,
                      onTap: _closeDrawer,
                      onHorizontalDragEnd: _swipeClosed,
                      child: ColoredBox(
                        color: style.background.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onHorizontalDragEnd: _swipeClosed,
                      child: DecoratedBox(
                        key: DebugHost.drawerKey,
                        decoration: BoxDecoration(
                          color: style.background,
                          border: Border(right: BorderSide(color: style.line)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 16, 0, 16),
                          child: menu(),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
