import 'package:dart_spring_language_server/src/diagnostics/fix.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// The quick fixes of a placeholder whose key nothing defines: add the key
/// to the package's main config file, or give the placeholder a default.
final class MissingPropertyFixes {
  /// The fixes, over [model].
  const MissingPropertyFixes(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  /// The fixes of [key], read in [path]; [keyEnd] is the empty range just
  /// after the key in its placeholder, where `:` starts a default.
  List<Fix> of(String path, String key, SourceRange keyEnd) => [
    ?_addTo(_mainConfigFile(path), key),
    Fix('Give the placeholder a default (\${$key:...})', [
      TextEdit(keyEnd, ':'),
    ]),
  ];

  /// `key: ` (or `key=`) on a line of its own at the end of [config].
  Fix? _addTo(String? config, String key) {
    if (config == null) {
      return null;
    }
    final text = model.files.textOf(config);
    if (text == null) {
      return null;
    }
    final lines = text.split('\n');
    final end = SourceRange(
      config,
      lines.length - 1,
      lines.last.length,
      lines.length - 1,
      lines.last.length,
    );
    final entry = config.endsWith('.properties') ? '$key=' : '$key: ';
    final name = config.split(RegExp(r'[\\/]')).last;
    return Fix("Add '$key' to $name", [
      TextEdit(
        end,
        '${text.isEmpty || text.endsWith('\n') ? '' : '\n'}$entry\n',
      ),
    ]);
  }

  /// The config file a new key of [path]'s package goes to: its
  /// `application.yaml` (or `.yml`, `.properties`) without a profile, one
  /// under `resources/` first; `null` when it has none.
  String? _mainConfigFile(String path) {
    final candidates = [
      for (final file in model.properties.configFilesOf(path))
        if (_rank(file) case final rank?) (file, rank),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return candidates.isEmpty ? null : candidates.first.$1;
  }

  static const _names = [
    'application.yaml',
    'application.yml',
    'application.properties',
  ];

  static int? _rank(String file) {
    final segments = file.split(RegExp(r'[\\/]'));
    final name = _names.indexOf(segments.last);
    if (name < 0 || segments.contains('test')) {
      return null;
    }
    return (segments.contains('resources') ? 0 : 10) + name;
  }
}
