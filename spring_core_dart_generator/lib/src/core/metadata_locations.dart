import 'package:analyzer/dart/element/element.dart';

/// The words of a camelCase name joined with `-`, in lower case:
/// `baseUrl` is `base-url`, `apiURL` is `api-url`.
String kebabCase(String name) => name
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
    .replaceAllMapped(RegExp('([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}-${m[2]}')
    .replaceAll('_', '-')
    .toLowerCase();

/// The first paragraph of the `///` comment of [element] on one line, or
/// `null` without a comment.
String? documentation(Element element) {
  final comment = element is PropertyAccessorElement && element.isOriginVariable
      ? element.variable.documentationComment
      : element.documentationComment;
  if (comment == null) {
    return null;
  }
  final lines = <String>[];
  for (var line in comment.split('\n')) {
    line = line
        .trim()
        .replaceFirst(RegExp(r'^(///|/\*\*|\*/|\*)\s?'), '')
        .replaceFirst(RegExp(r'\s*\*/$'), '')
        .trim();
    if (line.isEmpty) {
      if (lines.isNotEmpty) {
        break;
      }
      continue;
    }
    lines.add(line);
  }
  return lines.isEmpty ? null : lines.join(' ');
}

/// The message of `@Deprecated('...')` on [element] (`true` for a bare
/// `@deprecated`), or `null`.
Object? deprecation(Element element) {
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    if (value?.type?.element?.name == 'Deprecated') {
      return value?.getField('message')?.toStringValue() ?? true;
    }
  }
  return null;
}

/// Where [element] is declared: `package:pkg/path.dart` for a file in
/// `lib/`, else the path below the package root (`bin/main.dart`).
String? sourceOf(Element element) {
  final uri = element.firstFragment.libraryFragment?.source.uri;
  return uri == null ? null : sourceOfUri(uri);
}

/// [sourceOf] for the [uri] of a file.
String sourceOfUri(Uri uri) {
  if (uri.scheme == 'package') {
    return uri.toString();
  }
  if (uri.scheme == 'asset' && uri.pathSegments.length > 1) {
    final path = uri.pathSegments.skip(1).join('/');
    return path.startsWith('lib/')
        ? 'package:${uri.pathSegments.first}/${path.substring(4)}'
        : path;
  }
  return uri.toString();
}

/// The line (from 1) of the name of [element], or `null`.
int? lineOf(Element element) {
  final fragment = element.firstFragment;
  final offset = fragment.nameOffset;
  final unit = fragment.libraryFragment;
  if (offset == null || unit == null) {
    return null;
  }
  return unit.lineInfo.getLocation(offset).lineNumber;
}
