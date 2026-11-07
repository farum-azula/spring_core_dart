import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The beans: every bean of the context, by name, with its type.
final class DebugBeansSection implements DebugPanelSection, Ordered {
  /// The section of [context].
  const DebugBeansSection(this.context);

  /// The application.
  final ApplicationContext context;

  @override
  String get title => 'Beans';

  @override
  int get order => 30;

  @override
  Widget build(BuildContext context) => _Beans(this.context);
}

class _Beans extends StatefulWidget {
  const _Beans(this.context);

  final ApplicationContext context;

  @override
  State<_Beans> createState() => _BeansState();
}

class _BeansState extends State<_Beans> {
  late final _all = [
    for (final name in [...widget.context.beanDefinitionNames]..sort())
      (name, '${widget.context.getType(name) ?? ''}'),
  ];
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final needle = _filter.toLowerCase();
    final shown = [
      for (final bean in _all)
        if (needle.isEmpty ||
            bean.$1.toLowerCase().contains(needle) ||
            bean.$2.toLowerCase().contains(needle))
          bean,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_all.length} beans', style: style.text),
        const SizedBox(height: 8),
        DebugFilter(onChanged: (text) => setState(() => _filter = text)),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: shown[i].$1,
                      style: style.code.copyWith(color: style.accent),
                    ),
                    TextSpan(
                      text: '  ${shown[i].$2}',
                      style: style.code.copyWith(color: style.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
