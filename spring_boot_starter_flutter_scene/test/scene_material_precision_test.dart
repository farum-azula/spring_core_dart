// How precise a material computes: found by the build hook in the
// fragment code of its .fmat (flutter_scene's default is mediump, half
// precision on phones), written next to the generated assets and read by
// the debug tab; nothing to read leaves the tab without the line.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/hooks/scene_material_precision.dart';

import 'support/fakes.dart';

const _mediump = '''
material {
  name: "Glow",
  shading_model: unlit,
  parameters: [ { type: float, name: reach, default: 48 } ],
}

fragment {
  // precision highp float; would make it float32
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''';

const _declared = '''
material { name: "Glass", shading_model: unlit }

fragment {
  void Surface(inout MaterialInputs material) {
    highp vec2 p = GetUV0() * 700.0;
    highp float d = length(p);
    material.base_color = vec4(d);
  }
}
''';

const _highp = '''
material { name: "Neon", shading_model: unlit }

fragment {
  precision highp float;

  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''';

void main() {
  group('SceneMaterialPrecision.of', () {
    test('the default: mediump, a commented highp does not count', () {
      final precision = SceneMaterialPrecision.of(_mediump);
      expect(precision.highp, isFalse);
      expect(precision.declarations, 0);
    });

    test('mediump with the places written highp', () {
      final precision = SceneMaterialPrecision.of(_declared);
      expect(precision.highp, isFalse);
      expect(precision.declarations, 2);
    });

    test('precision highp float in the fragment code: float32', () {
      expect(SceneMaterialPrecision.of(_highp).highp, isTrue);
    });

    test('the same in JSON', () {
      for (final source in [_mediump, _declared, _highp]) {
        final precision = SceneMaterialPrecision.of(source);
        final read = SceneMaterialPrecision.fromJson(
          (jsonDecode(jsonEncode(precision.toJson())) as Map)
              .cast<String, Object?>(),
        );
        expect(read.highp, precision.highp);
        expect(read.declarations, precision.declarations);
      }
    });
  });

  group('the hook', () {
    late Directory app;

    setUp(() => app = Directory.systemTemp.createTempSync('scene_precision'));
    tearDown(() => app.deleteSync(recursive: true));

    test('writes each material by its source', () {
      for (final MapEntry(:key, :value) in {
        'assets/materials/glow.fmat': _mediump,
        'assets/materials/neon.fmat': _highp,
      }.entries) {
        File(p.join(app.path, key))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      final output = p.join(app.path, 'out');
      writeSceneMaterialPrecision(output, app.path, [
        'assets/materials/glow.fmat',
        'assets/materials/neon.fmat',
      ]);
      expect(
        jsonDecode(
          File(p.join(output, sceneMaterialPrecisionFile)).readAsStringSync(),
        ),
        {
          'assets/materials/glow.fmat': {'precision': 'mediump', 'highp': 0},
          'assets/materials/neon.fmat': {'precision': 'highp'},
        },
      );
    });
  });

  group('SceneMaterialPrecisions', () {
    test('reads the generated file once', () async {
      final resources = _CountingResources({
        'asset:$sceneMaterialPrecisionAsset': utf8.encode(
          jsonEncode({
            'assets/materials/glow.fmat': {'precision': 'mediump', 'highp': 3},
          }),
        ),
      });
      final precisions = SceneMaterialPrecisions(resources);
      final read = await precisions.load();
      await precisions.load();
      expect(read.keys, ['assets/materials/glow.fmat']);
      expect(read['assets/materials/glow.fmat']!.declarations, 3);
      expect(resources.reads, 1);
    });

    test('nothing generated: empty', () async {
      expect(await SceneMaterialPrecisions(FakeResources({})).load(), isEmpty);
    });
  });
}

final class _CountingResources implements ResourceLoader {
  _CountingResources(Map<String, List<int>> files)
    : _files = FakeResources(files);

  final FakeResources _files;
  int reads = 0;

  @override
  Resource getResource(String location) {
    reads++;
    return _files.getResource(location);
  }
}
