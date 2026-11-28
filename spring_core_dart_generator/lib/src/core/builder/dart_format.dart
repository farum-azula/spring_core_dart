import 'dart:io' as io;

import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_directory.dart';
import 'package:yaml/yaml.dart';

/// Formats a generated Dart file as `dart format` formats the files of its
/// package, so the file never changes when the package is formatted: with
/// the package's language version (from its package config; the
/// formatter's latest without one), and the `formatter:` options of the
/// `analysis_options.yaml` nearest to the file (`page_width`,
/// `trailing_commas`, the files its `include:` names followed as `dart format`
/// follows them).
///
/// The code is first formatted with the trailing commas automated, so the
/// output does not depend on where the code writer put commas, then, in a
/// package that preserves them, once more as `dart format` would; that
/// second pass finds the code formatted already. Then the doc comments a
/// line of which is longer than the page are wrapped to it, which
/// `dart format` leaves as they are written: a generated comment holds
/// names of any length.
///
/// ```dart
/// final formatter = await DartFormat.forOutput(buildStep, output);
/// await buildStep.writeAsString(output, formatter.format(source));
/// ```
final class DartFormat {
  /// The format of code at [languageVersion] with the options of an
  /// `analysis_options.yaml`: [pageWidth] and [trailingCommas] (`null`:
  /// the formatter's defaults, 80 and automated).
  DartFormat({
    required this.languageVersion,
    this.pageWidth,
    this.trailingCommas,
  });

  /// The language version the code is formatted at; the style changes at
  /// 3.7 (the tall style).
  final Version languageVersion;

  /// The line length, `formatter: page_width` (`null`: 80).
  final int? pageWidth;

  /// `formatter: trailing_commas` (`null`: automated).
  final TrailingCommas? trailingCommas;

  /// The format of the generated file [output]: the language version of its
  /// package in [buildStep]'s package config (else in the one on disk,
  /// through [directories]), the options of the
  /// `analysis_options.yaml` nearest to it on disk (through [directories];
  /// none when its package's directory is not known, as in tests with
  /// files in memory).
  static Future<DartFormat> forOutput(
    BuildStep buildStep,
    AssetId output, {
    PackageDirectories? directories,
  }) async {
    final config = await buildStep.packageConfig;
    final version = config[output.package]?.languageVersion;
    final packages = directories ?? PackageDirectories.current;
    return await forFile(
      packages.file(output),
      languageVersion: version == null
          ? packages.languageVersionOf(output.package)
          : Version(version.major, version.minor, 0),
      directories: packages,
    );
  }

  /// The format of [file] (which need not exist yet) at [languageVersion]
  /// (`null`: the formatter's latest), with the options of the
  /// `analysis_options.yaml` in its directory or the closest one above it;
  /// a `package:` include is found through [directories].
  static Future<DartFormat> forFile(
    io.File? file, {
    Version? languageVersion,
    PackageDirectories? directories,
  }) async {
    final options = file == null
        ? const <Object?, Object?>{}
        : await _nearestAnalysisOptions(
            file.parent,
            directories ?? PackageDirectories.current,
          );
    final formatter = options['formatter'];
    return DartFormat(
      languageVersion: languageVersion ?? DartFormatter.latestLanguageVersion,
      pageWidth: switch (formatter) {
        {'page_width': final int width} => width,
        _ => null,
      },
      trailingCommas: switch (formatter) {
        {'trailing_commas': 'preserve'} => TrailingCommas.preserve,
        {'trailing_commas': 'automate'} => TrailingCommas.automate,
        _ => null,
      },
    );
  }

  /// [source], formatted, its long doc comments wrapped.
  String format(String source) {
    final automated = DartFormatter(
      languageVersion: languageVersion,
      pageWidth: pageWidth,
      trailingCommas: TrailingCommas.automate,
    ).format(source);
    final formatted = trailingCommas == TrailingCommas.preserve
        ? DartFormatter(
            languageVersion: languageVersion,
            pageWidth: pageWidth,
            trailingCommas: TrailingCommas.preserve,
          ).format(automated)
        : automated;
    return wrapDocComments(formatted, pageWidth ?? 80);
  }

  /// [code] with each paragraph of a `///` comment that has a line longer
  /// than [width] wrapped to it. A paragraph ends at an empty comment line
  /// and before a list item; the lines of a code block (fenced, or indented
  /// by four spaces), of a table and of a heading are left as they are, as
  /// is a word (a code span in backticks counts as one) longer than a line.
  static String wrapDocComments(String code, int width) {
    final lines = code.split('\n');
    final result = <String>[];
    var index = 0;
    while (index < lines.length) {
      final comment = _docLine.firstMatch(lines[index]);
      if (comment == null) {
        result.add(lines[index++]);
        continue;
      }
      final indent = comment[1]!;
      final texts = <String>[];
      while (index < lines.length) {
        final next = _docLine.firstMatch(lines[index]);
        if (next == null || next[1] != indent) {
          break;
        }
        texts.add(next[2] ?? '');
        index++;
      }
      result.addAll([
        for (final text in _wrapped(texts, width - indent.length - 4))
          if (text.isEmpty) '$indent///' else '$indent/// $text',
      ]);
    }
    return result.join('\n');
  }

  // A line of a doc comment: its indent and its text.
  static final _docLine = RegExp(r'^(\s*)///(?: (.*)|)$');

  // The [texts] of one comment, each paragraph with a line longer than
  // [width] filled to it.
  static List<String> _wrapped(List<String> texts, int width) {
    final result = <String>[];
    var paragraph = <String>[];
    var hanging = '';
    void flush() {
      if (paragraph.isEmpty) {
        return;
      }
      if (paragraph.every((line) => line.length <= width)) {
        result.addAll(paragraph);
      } else {
        result.addAll(_filled(paragraph.join(' '), width, hanging));
      }
      paragraph = [];
      hanging = '';
    }

    var fenced = false;
    for (final text in texts) {
      final trimmed = text.trimLeft();
      if (trimmed.startsWith('```')) {
        flush();
        fenced = !fenced;
        result.add(text);
      } else if (fenced ||
          text.isEmpty ||
          text.startsWith('    ') ||
          trimmed.startsWith('|') ||
          trimmed.startsWith('#')) {
        flush();
        result.add(text);
      } else if (_listItem.firstMatch(text) case final item?) {
        flush();
        paragraph.add(text);
        hanging = ' ' * item[0]!.length;
      } else {
        paragraph.add(paragraph.isEmpty ? text : text.trimLeft());
      }
    }
    flush();
    return result;
  }

  /// [text] as `//` comment lines that fit in [width] columns, each ending
  /// with a line break; for the headers the builders write.
  ///
  /// ```dart
  /// DartFormat.lineComment('Generated by ... of a_long_file_name_test.dart.');
  /// // '// Generated by ... of\n// a_long_file_name_test.dart.\n'
  /// ```
  static String lineComment(String text, {int width = 80}) => [
    for (final line in _filled(text, width - 3, '')) '// $line\n',
  ].join();

  // The marker of a list item and the space after it: `- `, `* `, `1. `.
  static final _listItem = RegExp(r'^\s*(?:[-*+]|\d+\.) ');

  // [text] in lines of at most [width] (but a longer word), the lines after
  // the first indented by [hanging]; words are split at spaces outside
  // backticks.
  static List<String> _filled(String text, int width, String hanging) {
    final words = <String>[];
    final word = StringBuffer();
    var inCode = false;
    for (final char in text.split('')) {
      if (char == '`') {
        inCode = !inCode;
      }
      if (char == ' ' && !inCode) {
        if (word.isNotEmpty) {
          words.add(word.toString());
          word.clear();
        }
      } else {
        word.write(char);
      }
    }
    if (word.isNotEmpty) {
      words.add(word.toString());
    }
    final lines = <String>[];
    var line = '';
    for (final next in words) {
      final prefix = lines.isEmpty ? '' : hanging;
      if (line.isNotEmpty && line.length + 1 + next.length > width) {
        lines.add(line);
        line = '$hanging$next';
      } else {
        line = line.isEmpty ? '$prefix$next' : '$line $next';
      }
    }
    if (line.isNotEmpty) {
      lines.add(line);
    }
    return lines;
  }

  // The options of the `analysis_options.yaml` in [directory] or the
  // closest directory above it, merged with what it includes; empty
  // without one.
  static Future<Map<Object?, Object?>> _nearestAnalysisOptions(
    io.Directory directory,
    PackageDirectories packages,
  ) async {
    for (
      io.Directory? current = directory.absolute;
      current != null;
      current = current.parent.path == current.path ? null : current.parent
    ) {
      final file = io.File('${current.path}/analysis_options.yaml');
      if (file.existsSync()) {
        return await _readAnalysisOptions(file, packages, {});
      }
    }
    return const {};
  }

  // [file]'s options, after those it includes (a path relative to it or a
  // `package:` URI; a list is merged in order), as `dart format` reads
  // them. An include that cannot be read counts as empty.
  static Future<Map<Object?, Object?>> _readAnalysisOptions(
    io.File file,
    PackageDirectories packages,
    Set<String> seen,
  ) async {
    if (!seen.add(file.absolute.path) || !file.existsSync()) {
      return const {};
    }
    final Object? yaml;
    try {
      yaml = loadYaml(await file.readAsString());
    } on Object {
      return const {};
    }
    if (yaml is! Map) {
      return const {};
    }
    final options = <Object?, Object?>{...yaml}..remove('include');
    final includes = switch (yaml['include']) {
      final String include => [include],
      final List<Object?> list => [...list.whereType<String>()],
      _ => const <String>[],
    };
    var included = <Object?, Object?>{};
    for (final include in includes) {
      final includedFile = _includedFile(include, file, packages);
      if (includedFile != null) {
        included = _merge(
          included,
          await _readAnalysisOptions(includedFile, packages, seen),
        );
      }
    }
    return _merge(included, options);
  }

  // The file [include] names in [from]: a `package:` URI through the
  // package's directory, else a path relative to [from]'s directory.
  static io.File? _includedFile(
    String include,
    io.File from,
    PackageDirectories packages,
  ) {
    final uri = Uri.tryParse(include);
    if (uri == null || !uri.isScheme('package')) {
      return io.File.fromUri(from.absolute.uri.resolve(include));
    }
    return switch (uri.pathSegments) {
      [final package, ...final path] => packages.file(
        AssetId(package, 'lib/${path.join('/')}'),
      ),
      _ => null,
    };
  }

  // [overrides] over [defaults], maps merged key by key, as `dart format`
  // merges an options file over what it includes.
  static Map<Object?, Object?> _merge(
    Map<Object?, Object?> defaults,
    Map<Object?, Object?> overrides,
  ) => {
    ...defaults,
    for (final MapEntry(:key, :value) in overrides.entries)
      key: switch ((defaults[key], value)) {
        (final Map<Object?, Object?> before, final Map<Object?, Object?> now) =>
          _merge(before, now),
        (final before, null) => before,
        _ => value,
      },
  };
}
