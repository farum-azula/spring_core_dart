import 'package:build/build.dart' hide Resource;
import 'package:spring_core_dart_generator/src/core/builder/dart_format.dart';
import 'package:spring_core_dart_generator/src/core/builder/parts_owner_library.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/flutter/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/flutter/typed_theme_keys.dart';

/// Writes the typed keys of a Flutter app's configuration, so a renamed key
/// is a compile error instead of a run-time failure:
///
/// - `lib/spring_gen/theme.spring.keys.dart` (see `TypedThemeKeys`):
///   `context.theme`, the
///   colors, spacing, text styles, tokens, styles, motion, animations and
///   background declared under `spring.flutter.theme.*`, and `AppThemes`
///   with the theme names;
/// - `lib/spring_gen/messages.spring.keys.dart` (see `TypedMessageKeys`):
///   `context.messages`, the keys of `messages*.properties`.
///
/// Both are `part of` the `.spring.dart` of the package's only
/// `@SpringBootApplication` library, else the outermost `@ComponentScan`
/// (`spring_gen/main.spring.dart` in an app,
/// `spring_gen/spring_auto_configuration.spring.dart` in a library; nested scans in `lib/src/` do not matter): the main builder
/// writes their `part` directives and imports, and widgets get the
/// extensions by importing that file. Unrelated roots fail the build and
/// name them; none: nothing is written and the log says why.
///
/// It runs for a package that depends on `spring_boot_starter_flutter`
/// (or a package that brings it, such as the security starter), reads
/// `lib/resources/` as the web builder does (every `.yml`, `.yaml` and
/// `.properties` file, any profile, any theme, and the `resources:` files
/// that `spring.config.import` names from a dependency, as a library's
/// theme `resources:themes/neon.yml`) and writes nothing without
/// `spring.flutter.theme.*` properties and message files. The values are
/// not in the files, only the keys: they are read at run time from the
/// active theme and the message source.
///
/// Warnings (a message missing in a language) go to the build log; errors
/// (a message with a different number of arguments in two languages, a name
/// no Dart name can be made of, a token of two types, an unknown reference)
/// fail the build and none of the key files is written (build_runner removes
/// the outputs a step does not write).
///
/// Spring has nothing like it: Java reads these keys by string.
final class FlutterKeysBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [
      SpringKeyFiles.themeFile,
      SpringKeyFiles.messagesFile,
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    if (!await SpringKeyFiles.usesFlutterStarter(buildStep)) {
      return;
    }
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = await SpringKeyFiles.withImports(buildStep, {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    });
    final diagnostics = KeysDiagnostics();
    final parts = SpringKeyFiles.generate(
      texts,
      diagnostics,
      loaderKinds: await SpringKeyFiles.loaderKinds(buildStep),
    );
    diagnostics.warnings.forEach(log.warning);
    diagnostics.errors.forEach(log.severe);
    if (parts.theme == null && parts.messages == null) {
      return;
    }
    final scanLibraries = await PartsOwnerLibrary.scanLibrariesOf(buildStep);
    if (scanLibraries.isEmpty) {
      log.warning(
        'No library of $package has a @ComponentScan or '
        '@SpringBootApplication, so the typed keys of lib/resources/ have no '
        'library to be a part of: lib/spring_gen/theme.spring.keys.dart and '
        'lib/spring_gen/messages.spring.keys.dart are not written.',
      );
      return;
    }
    final owner = PartsOwnerLibrary.find(scanLibraries);
    if (owner == null) {
      log.severe(PartsOwnerLibrary.whyNotFound(scanLibraries));
      return;
    }
    Future<void> write(String path, String? code, String source) async {
      if (code == null) {
        return;
      }
      final output = AssetId(package, path);
      final format = await DartFormat.forOutput(buildStep, output);
      await buildStep.writeAsString(
        output,
        format.format(
          '${_header(source)}\n'
          "part of '${owner.partOfDirectivePath}';\n\n"
          '$code',
        ),
      );
    }

    await write(
      SpringKeyFiles.themeFile,
      parts.theme,
      'spring.flutter.theme.*',
    );
    await write(
      SpringKeyFiles.messagesFile,
      parts.messages,
      'messages*.properties',
    );
  }

  // The header of a file made from [source] (the keys it reads).
  static String _header(String source) =>
      '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
      '${DartFormat.lineComment('Generated by spring_core_dart_generator '
      'from the configuration of lib/resources/ ($source).')}\n'
      '// ignore_for_file: type=lint\n';
}
