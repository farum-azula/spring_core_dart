import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';

/// The states of a per-state color: `{ default: ..., hovered: ... }`.
const _stateNames = {
  'default',
  'hovered',
  'focused',
  'pressed',
  'dragged',
  'selected',
  'scrolled-under',
  'disabled',
  'error',
};

/// A theme color written as an object: it needs a `color:` (what `alpha`
/// or `mix` apply to) unless it is a per-state map, and a `mix` needs both
/// `with:` and `amount:`. Errors, at the object's first key.
final class ColorObjectCheck implements ConfigDocumentCheck {
  /// The check.
  const ColorObjectCheck();

  @override
  void check(ConfigCheckPass pass, List<Problem> problems) {
    final objects = <String, Set<String>>{};
    final objectKeys = <String, ConfigKey>{};
    for (final resolved in pass.checked) {
      final prop = resolved.resolution.node?.prop;
      if (resolved.resolution.isUnknown ||
          !resolved.isTheme ||
          prop == null ||
          prop.type != 'color') {
        continue;
      }
      final key = resolved.key;
      final rest = resolved.resolution.rest;
      final objectPath = key.segments
          .sublist(0, key.segments.length - rest.length)
          .join('.');
      final parts = objects.putIfAbsent(objectPath, () => {});
      objectKeys.putIfAbsent(objectPath, () => key);
      if (rest.isNotEmpty) {
        parts.add(rest.join('.'));
      }
    }
    for (final MapEntry(key: objectPath, value: parts) in objects.entries) {
      if (parts.isNotEmpty) {
        _checkObject(pass, objectKeys[objectPath]!, parts, problems);
      }
    }
  }

  void _checkObject(
    ConfigCheckPass pass,
    ConfigKey key,
    Set<String> parts,
    List<Problem> problems,
  ) {
    final range = pass.document.range(
      key.line,
      key.spans.first.$1,
      key.spans.last.$2,
    );
    final hasColor = parts.any((p) => p == 'color' || p.endsWith('.color'));
    // A per-state map: `{ default: ..., hovered: ... }` written in one
    // line has the states as plain parts, a nested one has dotted parts.
    final states = {
      for (final part in parts)
        if (part.contains('.') || _stateNames.contains(part))
          part.split('.').first,
    };
    if (!hasColor && states.isEmpty && !parts.contains('color')) {
      problems.add(
        Problem(
          range,
          'A color object needs a `color:` (the color alpha or mix is '
          'applied to)',
          error: true,
        ),
      );
    }
    if (parts.contains('mix') ||
        parts.any((p) => p.endsWith('mix') || p.contains('mix.'))) {
      final hasWith = parts.any((p) => p.endsWith('mix.with'));
      final hasAmount = parts.any((p) => p.endsWith('mix.amount'));
      if (!(hasWith && hasAmount) && !parts.contains('mix')) {
        problems.add(
          Problem(
            range,
            '`mix` needs both `with:` and `amount:`',
            error: true,
          ),
        );
      }
    }
  }
}
