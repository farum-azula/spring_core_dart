// The build hook's check of the materials the configuration names: read
// from every application file (YAML nested or flat, properties,
// profiles), a missing one fails the build with the key, the file and
// what there is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spring_boot_starter_flutter_scene/src/hooks/scene_material_check.dart';

void main() {
  late Directory app;

  void write(String name, String text) {
    final file = File(p.join(app.path, 'lib', 'resources', name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  setUp(() => app = Directory.systemTemp.createTempSync('scene_materials'));
  tearDown(() => app.deleteSync(recursive: true));

  test('no configuration: none', () {
    expect(declaredSceneMaterials(app.path), isEmpty);
  });

  test('every application file, profiles too; placeholders left out', () {
    write('application.yml', '''
spring:
  flutter:
    scene:
      materials:
        glass:
          source: assets/materials/glass.fmat
          preload: eager
        later:
          source: \${materials.later}
''');
    write(
      'application-prod.yml',
      'spring.flutter.scene.materials.neon.source: assets/materials/neon.fmat\n',
    );
    write(
      'application.properties',
      'spring.flutter.scene.materials.wall.source=assets/materials/wall.fmat\n',
    );
    write('messages.properties', 'spring.flutter.scene.materials.x.source=y\n');

    final declared = declaredSceneMaterials(app.path);

    expect(
      [
        for (final material in declared)
          '${material.name} ${material.source} ${material.file}',
      ],
      unorderedEquals([
        'glass assets/materials/glass.fmat lib/resources/application.yml',
        'neon assets/materials/neon.fmat lib/resources/application-prod.yml',
        'wall assets/materials/wall.fmat lib/resources/application.properties',
      ]),
    );
  });

  test('a material that was compiled passes', () {
    write(
      'application.yml',
      'spring.flutter.scene.materials.glass.source: assets/glass.fmat\n',
    );

    checkSceneMaterials(
      declaredSceneMaterials(app.path),
      ['assets/glass.fmat'],
      sources: 'assets/',
    );
  });

  test('one that was not fails with the key, the file and what there is', () {
    write('application.yml', '''
spring.flutter.scene.materials:
  glass.source: assets/glas.fmat
  neon.source: asset:assets/neon.fmat
''');

    expect(
      () => checkSceneMaterials(
        declaredSceneMaterials(app.path),
        ['assets/glass.fmat', 'assets/neon.fmat'],
        sources: 'assets/',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains(
              'spring.flutter.scene.materials.glass.source '
              '(lib/resources/application.yml) is assets/glas.fmat',
            ),
            contains('asset:assets/neon.fmat: write the path without asset:'),
            contains(
              'The .fmat files under assets/: assets/glass.fmat, '
              'assets/neon.fmat.',
            ),
          ),
        ),
      ),
    );
    expect(
      () => checkSceneMaterials(
        declaredSceneMaterials(app.path),
        const [],
        sources: 'assets/',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('There is no .fmat file under assets/.'),
        ),
      ),
    );
  });
}
