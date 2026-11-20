import 'package:dart_spring_language_server/src/schema.dart';

/// Whether the key [segments] is a theme key (below
/// `spring.flutter.theme`).
bool isThemeKey(List<String> segments) {
  if (segments.length < themePrefix.length) {
    return false;
  }
  for (var i = 0; i < themePrefix.length; i++) {
    if (canonicalName(segments[i]) != themePrefix[i]) {
      return false;
    }
  }
  return true;
}

/// The name of the theme the key [segments] belongs to
/// (`spring.flutter.theme.themes.<name>...`); `null` for the root theme.
String? themeOf(List<String> segments) {
  final rest = segments.length > themePrefix.length
      ? segments.sublist(themePrefix.length)
      : const <String>[];
  if (rest.length >= 2 && canonicalName(rest[0]) == 'themes') {
    return rest[1];
  }
  return null;
}

/// The theme key [segments] without `spring.flutter.theme` and
/// `themes.<name>`, with the name of its theme; `null` for a key that is
/// no theme key.
({String? theme, List<String> rest})? themeRelative(List<String> segments) {
  if (!isThemeKey(segments)) {
    return null;
  }
  var rest = segments.sublist(themePrefix.length);
  String? theme;
  if (rest.length >= 2 && canonicalName(rest[0]) == 'themes') {
    theme = rest[1];
    rest = rest.sublist(2);
  }
  return (theme: theme, rest: rest);
}

/// Whether the values of the key [segments] are never resolved as `$`
/// references: headers and the image keys.
bool takesNoReferences(List<String> segments) =>
    segments.any((s) => canonicalName(s) == 'headers') ||
    const {'source', 'fallback', 'sourcesha256'}.contains(
      canonicalName(segments.last),
    );

/// Whether [segments] starts with [prefix].
bool startsWithSegments(List<String> segments, List<String> prefix) {
  if (segments.length < prefix.length) {
    return false;
  }
  for (var i = 0; i < prefix.length; i++) {
    if (segments[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// Whether [segments] is a path of the navigation:
/// `spring.flutter.navigation.initial`, `login` or `redirects.*`.
bool isNavigationPath(List<String> segments) {
  final canonical = [for (final segment in segments) canonicalName(segment)];
  if (canonical.length < 4 ||
      canonical[0] != 'spring' ||
      canonical[1] != 'flutter' ||
      canonical[2] != 'navigation') {
    return false;
  }
  return canonical.length == 4 &&
          (canonical[3] == 'initial' || canonical[3] == 'login') ||
      canonical[3].startsWith('redirects');
}
