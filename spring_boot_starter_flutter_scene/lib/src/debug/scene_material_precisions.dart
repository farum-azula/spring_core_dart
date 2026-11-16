import 'dart:convert';

import 'package:spring_boot_starter_flutter_scene/src/materials/scene_material_precision.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show ResourceLoader;

/// The precision of each material, by its source, as the build hook found
/// it ([sceneMaterialPrecisionAsset]), read once when the debug tab first
/// asks. Empty when the app's hook made none (no hook, or no materials).
final class SceneMaterialPrecisions {
  /// What [resources] read of [sceneMaterialPrecisionAsset].
  SceneMaterialPrecisions(this._resources);

  final ResourceLoader _resources;
  Future<Map<String, SceneMaterialPrecision>>? _loaded;

  /// The precision of each material, by its source.
  Future<Map<String, SceneMaterialPrecision>> load() => _loaded ??= _read();

  Future<Map<String, SceneMaterialPrecision>> _read() async {
    final String text;
    try {
      text = await _resources
          .getResource('asset:$sceneMaterialPrecisionAsset')
          .readAsString();
    } on Object {
      return const {};
    }
    return {
      for (final MapEntry(:key, :value)
          in (jsonDecode(text) as Map<String, Object?>).entries)
        key: SceneMaterialPrecision.fromJson(
          (value! as Map).cast<String, Object?>(),
        ),
    };
  }
}
