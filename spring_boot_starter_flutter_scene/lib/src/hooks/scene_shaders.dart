import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

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

/// Builds the engine's shader bundle with [shaders] alone, into the tree
/// of the app whose `hook/build.dart` calls this:
///
/// ```dart
/// // hook/build.dart of the app
/// import 'package:hooks/hooks.dart';
/// import 'package:spring_boot_starter_flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     await buildSceneShaders(buildInput: input, buildOutput: output);
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
///     - flutter_scene_generated/
///     - path: flutter_scene_generated/opengl_es/
///       platforms: [web]
/// ```
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
Future<void> buildSceneShaders({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  Set<String> shaders = unlitSceneShaders,
}) async {
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

  final packageRoot = buildInput.packageRoot.toFilePath();
  final manifest = <String, Object?>{
    for (final name in shaders)
      name: {
        ...(entries[name] as Map).cast<String, Object?>(),
        'file': _relative(
          engineRoot.resolve((entries[name] as Map)['file'] as String),
          packageRoot,
        ),
      },
  };
  File(p.join(packageRoot, _ownManifest))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

  await buildTargetShaderBundleJson(
    buildInput: buildInput,
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
