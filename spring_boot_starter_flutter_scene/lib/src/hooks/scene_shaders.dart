import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:spring_boot_starter_flutter_scene/src/hooks/scene_stage.dart';

const String _engine = 'flutter_scene';
const String _engineManifest = 'shaders/base.shaderbundle.json';
const String _ownManifest = 'build/spring_scene/base.shaderbundle.json';
const int _glesLanguageVersion = 300;

/// The engine shaders a scene of unlit and custom (`.fmat`, unlit)
/// materials draws with: six of the engine's 88.
const Set<String> unlitSceneShaders = {
  'UnskinnedVertex',
  'UnlitFragment',
  'FullscreenVertex',
  'ResolveFragment',
  'CopyFragment',
  'PrefilterRadianceCubeFragment',
};

/// Makes, for the app whose `hook/build.dart` calls this, everything of
/// its scenes that is made at build time, into the app's
/// `lib/spring_gen/flutter_scene_generated/`:
///
/// - the engine's shader bundle with [shaders] alone (`null`: no bundle
///   of the app's own, the engine's whole one is used);
/// - the app's materials ([materials]: the `.fmat` files under [sources]);
/// - its models and scenes ([models]: the `.glb` and `.fscene` files
///   under [sources]), loadable by the path of their source.
///
/// ```dart
/// // hook/build.dart of the app
/// import 'package:hooks/hooks.dart';
/// import 'package:spring_boot_starter_flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     await buildSceneAssets(buildInput: input, buildOutput: output);
///   });
/// }
/// ```
///
/// ```yaml
/// # pubspec.yaml of the app
/// dependencies:
///   hooks: ^2.0.0
/// flutter:
///   assets:
///     - lib/spring_gen/flutter_scene_generated/
///     - path: lib/spring_gen/flutter_scene_generated/opengl_es/
///       platforms: [web]
/// ```
///
/// The hook is the app's because Dart runs a build hook for one package
/// and lets it write into that package alone: a bundle that takes the
/// place of the engine's has to be in the app's own tree, and only the
/// app knows what its scenes draw with.
///
/// `flutter_scene` compiles every shader of its bundle before the first
/// frame, the lit materials and every effect among them: in a browser
/// that holds the page for 0.3 to 0.7 seconds, and over 3 seconds on a
/// first visit. A bundle in the app's own tree takes the place of the
/// engine's (the engine reads the app's tree first; a package's copy
/// never wins), so the engine compiles only what the app's scenes draw
/// with. A scene that draws with more names it:
/// `shaders: {...unlitSceneShaders, 'StandardFragment'}`.
///
/// A shader that is not in the bundle fails at draw time with no name in
/// the error: after changing the list, look at every scene of the app.
/// Without the hook everything works, with the engine's whole bundle.
///
/// The engine's own hooks write into a `flutter_scene_generated/` folder
/// at the app's root. Here they are run for a stand-in of the app under
/// `.dart_tool/spring_scene/` and their output is copied into
/// `lib/spring_gen/`, where the rest of the generated code is: the app's
/// root gets no folder for it ([SceneStage]).
Future<void> buildSceneAssets({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  Set<String>? shaders = unlitSceneShaders,
  bool materials = true,
  bool models = true,
  String sources = 'assets/',
}) async {
  final stage = SceneStage(buildInput);
  final staged = stage.prepare(
    sources: [p.posix.split(p.posix.normalize(sources)).first],
  );
  buildOutput.dependencies.add(buildInput.packageRoot.resolve('pubspec.yaml'));
  stage.renew(
    'shaders: ${shaders == null ? 'the engine\'s' : (shaders.toList()..sort()).join(' ')}; '
    'materials: $materials; models: $models; sources: $sources',
  );
  if (shaders != null) {
    await _engineShaders(stage, staged, buildOutput, shaders);
  }
  if (models) {
    buildScenes(
      buildInput: staged,
      buildOutput: buildOutput,
      discoveryRoot: sources,
    );
  }
  if (materials) {
    // Found here and named one by one: the engine's function has no
    // folder to search in where it stands in for the web, and a library
    // of the starter must compile there too.
    final found = _materials(stage, sources, buildOutput);
    if (found.isNotEmpty) {
      await buildMaterials(
        buildInput: staged,
        buildOutput: buildOutput,
        materials: found,
      );
    }
  }
  stage.publish();
}

// The `.fmat` files under [sources] of the app, by the address the app
// loads them with (`assets/materials/glow.fmat`), in a stable order. Each
// folder there is a dependency of the hook, so a material added or
// removed runs it again.
List<String> _materials(
  SceneStage stage,
  String sources,
  BuildOutputBuilder buildOutput,
) {
  final root = Directory(p.join(stage.app, p.normalize(sources)));
  if (!root.existsSync()) {
    return const [];
  }
  final found = <String>[];
  buildOutput.dependencies.add(root.uri);
  for (final entity in root.listSync(recursive: true)) {
    if (entity is Directory) {
      buildOutput.dependencies.add(entity.uri);
    } else if (entity is File && entity.path.endsWith('.fmat')) {
      found.add(
        p.posix.joinAll(p.split(p.relative(entity.path, from: stage.app))),
      );
    }
  }
  return found..sort();
}

/// The engine's shader bundle with [shaders] alone, and nothing else:
/// [buildSceneAssets] without the app's materials and models.
Future<void> buildSceneShaders({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  Set<String> shaders = unlitSceneShaders,
}) => buildSceneAssets(
  buildInput: buildInput,
  buildOutput: buildOutput,
  shaders: shaders,
  materials: false,
  models: false,
);

Future<void> _engineShaders(
  SceneStage stage,
  BuildInput staged,
  BuildOutputBuilder buildOutput,
  Set<String> shaders,
) async {
  final engineRoot = await _engineRoot();
  final source = File.fromUri(engineRoot.resolve(_engineManifest));
  buildOutput.dependencies.add(source.uri);

  final entries = (jsonDecode(source.readAsStringSync()) as Map)
      .cast<String, Object?>();
  final missing = shaders.difference(entries.keys.toSet());
  if (missing.isNotEmpty) {
    throw StateError(
      'flutter_scene has no shaders named ${missing.join(', ')}. '
      'It has: ${entries.keys.join(', ')}.',
    );
  }

  final manifest = <String, Object?>{
    for (final name in shaders)
      name: {
        ...(entries[name] as Map).cast<String, Object?>(),
        'file': _relative(
          engineRoot.resolve((entries[name] as Map)['file'] as String),
          stage.root,
        ),
      },
  };
  File(p.join(stage.root, _ownManifest))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

  await buildTargetShaderBundleJson(
    buildInput: staged,
    buildOutput: buildOutput,
    manifestFileName: _ownManifest,
    includeDirectories: [engineRoot.resolve('shaders/')],
    glesLanguageVersion: _glesLanguageVersion,
    owner: _engine,
  );
}

Future<Uri> _engineRoot() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/build_hooks.dart'),
  );
  if (library == null) {
    throw StateError('flutter_scene is not among the packages of this build');
  }
  return library.resolve('../');
}

String _relative(Uri file, String from) =>
    p.posix.joinAll(p.split(p.relative(file.toFilePath(), from: from)));
