// Flutter assets (spring_boot_starter_flutter's `asset:` resources): which
// files `flutter: assets:` of a pubspec.yaml declares, by the generator's
// and Flutter's rules.
import 'package:yaml/yaml.dart';

/// The entries of `flutter: assets:` in [pubspec]: plain strings and the
/// `path:` of map entries (`- path: assets/x/`, with `flavors:`); empty
/// when there are none or the YAML is invalid.
List<String> flutterAssets(String pubspec) {
  final Object? yaml;
  try {
    yaml = loadYaml(pubspec);
  } on YamlException {
    return const [];
  }
  final assets = yaml is Map && yaml['flutter'] is Map
      ? (yaml['flutter'] as Map)['assets']
      : null;
  if (assets is! List) {
    return const [];
  }
  return [
    for (final entry in assets)
      if (entry is String)
        entry
      else if (entry is Map && entry['path'] is String)
        entry['path'] as String,
  ];
}

/// Whether [key] is one of [entries]: the file itself, or a directory
/// entry (`assets/images/`) holding it directly — not in a subdirectory,
/// as in Flutter.
bool declaredAsset(List<String> entries, String key) {
  final slash = key.lastIndexOf('/');
  final directory = slash < 0 ? '' : key.substring(0, slash + 1);
  for (var entry in entries) {
    if (entry.startsWith('./')) {
      entry = entry.substring(2);
    }
    if (entry == key || entry.endsWith('/') && entry == directory) {
      return true;
    }
  }
  return false;
}
