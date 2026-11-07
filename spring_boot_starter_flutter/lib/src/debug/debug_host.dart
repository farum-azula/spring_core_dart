import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// Puts the debug panel over the app, inside the app's own `builder`: the
/// panel when it is open, the frame meter when it is on.
final class DebugPanelCustomizer implements FlutterAppCustomizer {
  /// The panel [panel] with [sections].
  const DebugPanelCustomizer(this.panel, this.sections);

  /// The panel's state.
  final DebugPanel panel;

  /// Its sections, in order.
  final List<DebugPanelSection> sections;

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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: panel,
    child: child,
    builder: (context, app) => Stack(
      fit: StackFit.expand,
      children: [
        if (panel.frameMeter)
          FrameMeter(position: panel.frameMeterPosition, child: app!)
        else
          app!,
        if (panel.isOpen)
          Positioned.fill(
            child: _Panel(panel: panel, sections: sections),
          ),
      ],
    ),
  );
}

class _Panel extends StatefulWidget {
  const _Panel({required this.panel, required this.sections});

  final DebugPanel panel;
  final List<DebugPanelSection> sections;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final sections = widget.sections;
    final shown = sections.isEmpty ? null : sections[_shown % sections.length];
    return ColoredBox(
      color: style.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Debug', style: style.title)),
                  DebugChip('Close', onTap: widget.panel.close),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, section) in sections.indexed)
                      DebugChip(
                        section.title,
                        selected: section == shown,
                        onTap: () => setState(() => _shown = i),
                      ),
                  ],
                ),
              ),
              Container(height: 1, color: style.line),
              const SizedBox(height: 12),
              Expanded(
                child: shown == null
                    ? Text('No sections', style: style.text)
                    : KeyedSubtree(
                        key: ValueKey(shown),
                        child: shown.build(context),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
