import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // The main builder declares `spring_gen/<name>.spring.dart` for every
  // source: a file another builder declares under that ending is written
  // twice as soon as an app has a source of that name (`lib/theme.dart`),
  // and build_runner refuses the whole build.
  test('no builder writes a fixed file where a source maps to', () {
    final root = Isolate.resolvePackageUriSync(
      Uri.parse('package:spring_core_dart_generator/'),
    )!.resolve('../build.yaml');
    final builders =
        (loadYaml(File.fromUri(root).readAsStringSync()) as YamlMap)['builders']
            as YamlMap;
    final fixed = <String>[
      for (final builder in builders.values)
        if (((builder as YamlMap)['build_extensions'] as YamlMap)[r'$package$']
            case final YamlList outputs)
          ...outputs.cast<String>(),
    ];
    expect(fixed, isNotEmpty);
    expect(fixed.where((path) => path.endsWith('.spring.dart')), isEmpty);
  });
}
