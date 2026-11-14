// The stand-in the engine's build hooks work in, and the move of what
// they made into the app's lib/spring_gen/ (build_hooks.dart): the asset
// entries read from the app's pubspec, the stand-in's own pubspec and
// links, the copy that leaves unchanged files alone and removes the ones
// no longer made.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:spring_boot_starter_flutter_scene/build_hooks.dart';

const _pubspec = '''
name: shop
flutter:
  assets:
    - assets/images/
    - lib/spring_gen/flutter_scene_generated/
    - path: lib/spring_gen/flutter_scene_generated/opengl_es/
      platforms: [web]
    # - lib/spring_gen/flutter_scene_generated/metal_ios/
''';

void main() {
  late Directory app;

  setUp(() {
    app = Directory.systemTemp.createTempSync('scene_stage_');
    File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync(_pubspec);
    File(p.join(app.path, 'assets', 'materials', 'glow.fmat'))
      ..createSync(recursive: true)
      ..writeAsStringSync('glow');
  });
  tearDown(() => app.deleteSync(recursive: true));

  SceneStage stage() => SceneStage(
    BuildInput({
      'package_name': 'shop',
      'package_root': '${app.path}${p.separator}',
      'out_dir_shared': p.join(app.path, '.dart_tool', 'out'),
      'out_file': p.join(app.path, '.dart_tool', 'out', 'output.json'),
      'config': {'build_asset_types': <String>[], 'linking_enabled': false},
    }),
  );

  test('the asset entries under lib/spring_gen, by the names the engine '
      'gives them; a comment is none', () {
    expect(SceneStage.entriesOf(_pubspec), {'', 'opengl_es'});
    expect(
      SceneStage.entriesOf('flutter:\n  assets:\n    - assets/\n'),
      isEmpty,
    );
    expect(
      SceneStage.entriesOf(
        "    - 'lib/spring_gen/flutter_scene_generated/' # scenes\n",
      ),
      {''},
    );
  });

  test('the stand-in: a pubspec with the entries as the engine expects '
      'them, the sources under their own name, the hook input rooted '
      'there', () {
    final made = stage();
    final staged = made.prepare();

    expect(made.root, p.join(app.path, '.dart_tool', 'spring_scene'));
    expect(p.equals(staged.packageRoot.toFilePath(), made.root), isTrue);
    expect(staged.packageName, 'shop');
    final pubspec = File(p.join(made.root, 'pubspec.yaml')).readAsStringSync();
    expect(pubspec, contains('    - flutter_scene_generated/\n'));
    expect(pubspec, contains('    - flutter_scene_generated/opengl_es/\n'));
    expect(pubspec, isNot(contains('metal_ios')));
    // A source keeps the address the app loads it by.
    expect(
      File(
        p.join(made.root, 'assets', 'materials', 'glow.fmat'),
      ).readAsStringSync(),
      'glow',
    );
    // Again: nothing to do, nothing broken.
    made.prepare();
    expect(
      File(p.join(made.root, 'assets', 'materials', 'glow.fmat')).existsSync(),
      isTrue,
    );
  });

  test('a pubspec without the entry says what to add', () {
    File(
      p.join(app.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: shop\nflutter:\n  assets:\n    - assets/\n');
    expect(
      () => stage().prepare(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('pubspec.yaml of shop'),
            contains('- lib/spring_gen/flutter_scene_generated/'),
          ),
        ),
      ),
    );
  });

  test('what the hooks made is copied into lib/spring_gen: new and changed '
      'files written, unchanged ones left alone, the ones no longer made '
      'removed; the app root gets no folder', () {
    final made = stage()..prepare();
    final from = p.join(made.root, 'flutter_scene_generated');
    File(p.join(from, 'manifest.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"entries": 1}');
    File(p.join(from, 'opengl_es', 'base.shaderbundle'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    File(p.join(from, 'opengl_es', 'old.shaderbundle')).writeAsBytesSync([9]);

    made.publish();

    final to = p.join(app.path, 'lib', 'spring_gen', 'flutter_scene_generated');
    expect(made.generated, to);
    expect(
      File(p.join(to, 'manifest.json')).readAsStringSync(),
      '{"entries": 1}',
    );
    expect(
      File(p.join(to, 'opengl_es', 'base.shaderbundle')).readAsBytesSync(),
      [1, 2, 3],
    );
    expect(
      Directory(p.join(app.path, 'flutter_scene_generated')).existsSync(),
      isFalse,
    );

    final untouched = File(p.join(to, 'opengl_es', 'base.shaderbundle'));
    final before = untouched.lastModifiedSync();
    File(p.join(from, 'manifest.json')).writeAsStringSync('{"entries": 2}');
    File(p.join(from, 'opengl_es', 'old.shaderbundle')).deleteSync();
    sleep(const Duration(milliseconds: 1100));
    made.publish();

    expect(
      File(p.join(to, 'manifest.json')).readAsStringSync(),
      '{"entries": 2}',
    );
    expect(
      File(p.join(to, 'opengl_es', 'old.shaderbundle')).existsSync(),
      isFalse,
    );
    expect(untouched.lastModifiedSync(), before);
  });
}
