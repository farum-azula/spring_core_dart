import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// Turns offsets of Dart files into the ranges the editor gets, and
/// paths into the short form hovers show.
final class SourceLocations {
  /// Locations in [files]; [packages] shortens paths.
  SourceLocations(this.files, this.packages);

  /// The files of the workspace.
  final ProjectFiles files;

  /// The packages of the workspace.
  final PackageLayout packages;

  /// The span from offset [start] to offset [end] of [file], as zero-based
  /// lines and columns.
  SourceRange rangeOf(DartFile file, int start, int end) {
    final from = file.lineInfo.getLocation(start);
    final to = file.lineInfo.getLocation(end);
    return SourceRange(
      file.path,
      from.lineNumber - 1,
      from.columnNumber - 1,
      to.lineNumber - 1,
      to.columnNumber - 1,
    );
  }

  /// The span of [length] from [offset] of the Dart file [path]; `null`
  /// when the file cannot be read.
  SourceRange? declarationRange(String path, int offset, int length) {
    final file = files.dartFile(path);
    return file == null ? null : rangeOf(file, offset, offset + length);
  }

  /// Where [bean] is declared: the name of its class or `@Bean` method in
  /// the current text of its file, the line the metadata gives, else the
  /// start of the file.
  SourceRange beanRange(BeanInfo bean) {
    if (bean.line case final line?) {
      return SourceRange(bean.path, line, 0, line, 0);
    }
    final file = files.dartFile(bean.path);
    if (file == null) {
      return SourceRange(bean.path, 0, 0, 0, 0);
    }
    final at = bean.positionIn(file) ?? (offset: 0, length: 0);
    return rangeOf(file, at.offset, at.offset + at.length);
  }

  /// [path] relative to the workspace folder it is in.
  String shortPath(String path) => packages.shortPath(path);
}
