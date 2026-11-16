import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spring_boot_starter_flutter_scene/src/materials/scene_material_precision.dart';

/// Writes [sceneMaterialPrecisionFile] into [directory]: the precision of
/// each material of [sources] (their paths from [app], as the properties
/// name them).
void writeSceneMaterialPrecision(
  String directory,
  String app,
  Iterable<String> sources,
) {
  final entries = {
    for (final source in sources)
      source: SceneMaterialPrecision.of(
        File(p.join(app, p.normalize(source))).readAsStringSync(),
      ).toJson(),
  };
  File(p.join(directory, sceneMaterialPrecisionFile))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(entries));
}
