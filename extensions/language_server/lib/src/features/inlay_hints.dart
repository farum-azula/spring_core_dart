import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/properties/property_values.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/protocol/line_index.dart';

/// The values of properties where code reads them: after `${shop.name}` in
/// an annotation string, and after a field of a `@ConfigurationProperties`
/// class, the value the property has for the active profiles (`= Farum`),
/// or a placeholder's default (`= 8080 (default)`). Clicking the value goes
/// to the entry it comes from; its tooltip says which file and profile.
final class InlayHints extends ServerFeature {
  /// The hints of [session].
  InlayHints(this.session);

  /// The session it serves.
  final SpringSession session;

  /// Values longer than this are cut, with an ellipsis.
  static const maxLength = 40;

  @override
  Map<String, Object?> get capabilities => const {'inlayHintProvider': true};

  @override
  Map<String, RequestHandler> get requests => {
    'textDocument/inlayHint': (params) {
      final workspace = session.workspace..refresh();
      final path = SpringSession.documentPath(params);
      final text = workspace.textOf(path);
      if (text == null || !path.endsWith('.dart')) {
        return null;
      }
      final lines = LineIndex(text);
      final range = params['range']! as Map;
      final from = _offset(lines, range['start']! as Map);
      final to = _offset(lines, range['end']! as Map);
      final profiles = workspace.activeProfilesOf(
        path,
        session.settings.activeProfiles,
      );
      final values = PropertyValues(
        (key) => workspace.propertyEntriesIn(path, key),
        profiles,
      );
      return [
        for (final reference in workspace.propertyReferences(path))
          if (reference.end >= from && reference.end <= to)
            if (values.valueOf(reference.key, fallback: reference.fallback)
                case final value?)
              _hint(lines, reference, value, profiles),
      ];
    },
  };

  static int _offset(LineIndex lines, Map<Object?, Object?> position) =>
      lines.offsetOf(position['line']! as int, position['character']! as int);

  static Map<String, Object?> _hint(
    LineIndex lines,
    PropertyReference reference,
    PropertyValue value,
    ActiveProfiles profiles,
  ) {
    final at = lines.positionOf(reference.end);
    final label =
        '= ${display(value.text)}'
        '${value.fromDefault ? ' (default)' : ''}';
    final entry = value.entry;
    return {
      'position': {'line': at.line, 'character': at.column},
      'label': [
        {
          'value': label,
          if (entry != null && !entry.path.endsWith('.dart'))
            'location': {
              'uri': uriOf(entry.path),
              'range': {
                'start': {'line': entry.line, 'character': entry.keyStart},
                'end': {'line': entry.line, 'character': entry.keyEnd},
              },
            },
        },
      ],
      'paddingLeft': true,
      'tooltip': {
        'kind': 'markdown',
        'value': _tooltip(reference, value, profiles),
      },
    };
  }

  /// [value] as shown in a hint: on one line, quoted when it is empty or
  /// has spaces at its ends, cut after [maxLength] characters.
  static String display(String value) {
    var shown = value.split('\n').first;
    if (shown.length > maxLength) {
      shown = '${shown.substring(0, maxLength)}…';
    } else if (shown != value) {
      shown = '$shown…';
    }
    return shown.isEmpty || shown.trim() != shown ? '"$shown"' : shown;
  }

  static String _tooltip(
    PropertyReference reference,
    PropertyValue value,
    ActiveProfiles profiles,
  ) {
    final entry = value.entry;
    final source = switch (entry) {
      null => "the placeholder's default: no config file sets it",
      final entry when entry.path.endsWith('.dart') => 'set by this test',
      final entry =>
        '${entry.fileName}, line ${entry.line + 1}'
            '${entry.profile == null ? '' : ' (profile ${entry.profile})'}',
    };
    return '`${reference.key}` = `${value.text}`\n\n'
        'From $source; active profiles: ${profiles.names.join(', ')}.';
  }
}
