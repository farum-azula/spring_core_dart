import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The configuration: the active profiles and every property with the
/// source that sets it, the first source winning. A value whose key names
/// a secret (`password`, `secret`, `token`, `key`, `credential`) shows as
/// `******`, as Spring Boot's actuator does.
final class DebugConfigurationSection implements DebugPanelSection, Ordered {
  /// The section of [environment].
  const DebugConfigurationSection(this.environment);

  /// The configuration read.
  final ConfigurableEnvironment environment;

  @override
  String get title => 'Configuration';

  @override
  int get order => 20;

  static final _secret = RegExp(
    'password|secret|token|key|credential',
    caseSensitive: false,
  );

  /// The properties, each once, from the source that wins.
  List<(String, String, String)> properties() {
    final seen = <String>{};
    return [
      for (final source in environment.propertySources)
        if (source is EnumerablePropertySource)
          for (final name in source.propertyNames)
            if (seen.add(name))
              (
                name,
                _secret.hasMatch(name)
                    ? '******'
                    : '${source.getProperty(name) ?? ''}',
                source.name,
              ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
  }

  @override
  Widget build(BuildContext context) => _Configuration(this);
}

class _Configuration extends StatefulWidget {
  const _Configuration(this.section);

  final DebugConfigurationSection section;

  @override
  State<_Configuration> createState() => _ConfigurationState();
}

class _ConfigurationState extends State<_Configuration> {
  late final _all = widget.section.properties();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final profiles = widget.section.environment.activeProfiles;
    final needle = _filter.toLowerCase();
    final shown = [
      for (final row in _all)
        if (needle.isEmpty ||
            row.$1.toLowerCase().contains(needle) ||
            row.$2.toLowerCase().contains(needle))
          row,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Profiles: ${profiles.isEmpty ? 'default' : profiles.join(', ')}',
          style: style.text,
        ),
        const SizedBox(height: 8),
        DebugFilter(onChanged: (text) => setState(() => _filter = text)),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final (key, value, source) = shown[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: key,
                        style: style.code.copyWith(color: style.accent),
                      ),
                      TextSpan(text: ' = $value', style: style.code),
                      TextSpan(
                        text: '\n$source',
                        style: style.code.copyWith(color: style.muted),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
