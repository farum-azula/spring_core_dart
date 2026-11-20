// The values of properties where code reads them: inlay hints after a
// `${key}` of an annotation string and after a field of a
// `@ConfigurationProperties` class, with the value for the active profiles
// as the framework resolves it.
import 'dart:io';

import 'package:dart_spring_language_server/src/config/properties_format.dart';
import 'package:dart_spring_language_server/src/config/yaml_entries.dart';
import 'package:dart_spring_language_server/src/features/inlay_hints.dart';
import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/properties/property_values.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

final class _Editor implements Editor {
  final requests = <String>[];

  @override
  void notify(String method, Map<String, Object?> params) {}

  @override
  void request(String method, [Map<String, Object?>? params]) =>
      requests.add(method);
}

void main() {
  group('the value of a property', () {
    PropertyValues values(
      Map<String, String> files, {
      List<String> profiles = const [],
    }) {
      final entries = [
        for (final MapEntry(key: name, value: content) in files.entries)
          ...(name.endsWith('.properties')
              ? parseProperties('/app/lib/resources/$name', content)
              : parseYamlProperties('/app/lib/resources/$name', content)),
      ];
      return PropertyValues(
        (key) => [
          for (final entry in entries)
            if (entry.key == key) entry,
        ],
        ActiveProfiles(profiles),
      );
    }

    test('a profile file wins over application, a later profile over an '
        'earlier one', () {
      final files = {
        'application.yaml': 'shop:\n  name: Farum\n',
        'application-dev.yaml': 'shop:\n  name: Dev\n',
        'application-local.properties': 'shop.name=Local\n',
      };
      expect(values(files).valueOf('shop.name')?.text, 'Farum');
      expect(
        values(files, profiles: ['dev']).valueOf('shop.name')?.text,
        'Dev',
      );
      expect(
        values(files, profiles: ['dev', 'local']).valueOf('shop.name')?.text,
        'Local',
      );
      expect(
        values(files, profiles: ['local', 'dev']).valueOf('shop.name')?.text,
        'Dev',
      );
    });

    test('a document of application.yaml activated on a profile', () {
      final files = {
        'application.yaml':
            'shop:\n  name: Farum\n'
            '---\n'
            'spring:\n  config:\n    activate:\n      on-profile: prod & eu\n'
            'shop:\n  name: Farum EU\n',
      };
      expect(values(files).valueOf('shop.name')?.text, 'Farum');
      expect(
        values(files, profiles: ['prod']).valueOf('shop.name')?.text,
        'Farum',
      );
      expect(
        values(files, profiles: ['prod', 'eu']).valueOf('shop.name')?.text,
        'Farum EU',
      );
    });

    test('the profile file of a profile wins over its document in '
        'application.yaml', () {
      final files = {
        'application.yaml':
            'shop.name: Farum\n---\n'
            'spring.config.activate.on-profile: dev\nshop.name: Doc\n',
        'application-dev.yaml': 'shop.name: File\n',
      };
      expect(
        values(files, profiles: ['dev']).valueOf('shop.name')?.text,
        'File',
      );
    });

    test('the default profile is active when none is', () {
      final files = {
        'application.yaml': 'shop.name: Farum\n',
        'application-default.yaml': 'shop.name: Default\n',
      };
      expect(values(files).valueOf('shop.name')?.text, 'Default');
      expect(
        values(files, profiles: ['prod']).valueOf('shop.name')?.text,
        'Farum',
      );
    });

    test('placeholders in a value are resolved; unresolved ones and cycles '
        'stay', () {
      final files = {
        'application.yaml':
            'shop:\n'
            r'  url: http://${shop.host}:${shop.port:80}/${shop.path}'
            '\n'
            '  host: farum.org\n'
            r'  a: ${shop.b}'
            '\n'
            r'  b: ${shop.a}'
            '\n',
      };
      expect(
        values(files).valueOf('shop.url')?.text,
        r'http://farum.org:80/${shop.path}',
      );
      expect(values(files).valueOf('shop.a')?.text, r'${shop.a}');
    });

    test('a default when no entry gives the key, none without one', () {
      final shop = values({'application.yaml': 'shop.name: Farum\n'});
      final port = shop.valueOf('server.port', fallback: '8080');
      expect(port?.text, '8080');
      expect(port?.fromDefault, isTrue);
      expect(shop.valueOf('server.port'), isNull);
      expect(shop.valueOf('shop.name', fallback: 'x')?.fromDefault, isFalse);
    });
  });

  group('inlay hints', () {
    late Directory root;
    late SpringSession session;
    late _Editor editor;

    setUp(() {
      root = Directory.systemTemp.createTempSync('lsp_inlay_hints_');
      void write(String path, String content) => File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      write('pubspec.yaml', 'name: shop\n');
      write(
        'lib/resources/application.yaml',
        'spring:\n  profiles:\n    active: dev\n'
            'shop:\n  name: Farum\n  max-basket-size: 10\n',
      );
      write(
        'lib/resources/application-dev.yaml',
        'shop:\n  name: Farum (dev)\n',
      );
      write('other/pubspec.yaml', 'name: other\n');
      write('other/lib/resources/application.yaml', 'mail.host: other\n');
      editor = _Editor();
      session = SpringSession(SpringWorkspace([root.path]), editor, const {
        'capabilities': {
          'workspace': {
            'inlayHint': {'refreshSupport': true},
          },
        },
      })..workspace.refresh(force: true);
    });

    tearDown(() => root.deleteSync(recursive: true));

    /// `line:column label` of each hint of [text], written to
    /// lib/shop.dart.
    List<String> hints(String text, {String file = 'lib/shop.dart'}) {
      final path = '${root.path}/$file';
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      session.workspace.setOverlay(path, text);
      final result =
          InlayHints(session).requests['textDocument/inlayHint']!({
                'textDocument': {'uri': uriOf(path)},
                'range': {
                  'start': {'line': 0, 'character': 0},
                  'end': {'line': 1000, 'character': 0},
                },
              })!
              as List<Object?>;
      return [
        for (final hint in result.cast<Map<String, Object?>>()) _describe(hint),
      ];
    }

    test('after a placeholder, the value for the active profiles', () {
      expect(
        hints(
          "@Value(r'\${shop.name}')\n"
          'late final String name;\n'
          "@Value(r'\${server.port:8080}')\n"
          'late final int port;\n'
          "@Value(r'\${mail.host}')\n"
          'late final String host;\n',
        ),
        ['0:21 = Farum (dev)', '2:28 = 8080 (default)'],
        reason:
            'spring.profiles.active: dev of application.yaml; the key of '
            'another package has no value here',
      );
    });

    test('the profiles of the settings win over spring.profiles.active', () {
      session.settings = SessionSettings.from({
        'activeProfiles': ['prod'],
      });
      expect(hints("@Value(r'\${shop.name}')\nlate String n;\n"), [
        '0:21 = Farum',
      ]);
    });

    test('a test sets its own profiles and properties', () {
      expect(
        hints(
          "@ActiveProfiles(['prod'])\n"
          "@TestPropertySource(properties: {'shop.max-basket-size': '99'})\n"
          'class ShopTest {\n'
          "  @Value(r'\${shop.name}') late String name;\n"
          "  @Value(r'\${shop.max-basket-size}') late int size;\n"
          '}\n',
          file: 'test/shop_test.dart',
        ),
        ['3:23 = Farum', '4:34 = 99'],
      );
    });

    test('after the fields of a @ConfigurationProperties class', () {
      expect(
        hints(
          "@ConfigurationProperties('shop')\n"
          'class ShopProperties {\n'
          '  ShopProperties(this.name, this.maxBasketSize);\n'
          '  final String name;\n'
          '  final int maxBasketSize;\n'
          '  final Payment payment;\n'
          "  String currency = 'EUR';\n"
          '  static const unbound = 1;\n'
          '}\n',
        ),
        ['3:19 = Farum (dev)', '4:25 = 10', '6:17 = EUR (default)'],
      );
    });

    test('the hint goes to the entry its value comes from', () {
      final path = '${root.path}/lib/shop.dart';
      const text = "@Value(r'\${shop.name}')\nlate String name;\n";
      File(path).writeAsStringSync(text);
      session.workspace.setOverlay(path, text);
      final hint =
          (InlayHints(session).requests['textDocument/inlayHint']!({
                        'textDocument': {'uri': uriOf(path)},
                        'range': {
                          'start': {'line': 0, 'character': 0},
                          'end': {'line': 9, 'character': 0},
                        },
                      })!
                      as List)
                  .single
              as Map;
      final location =
          ((hint['label']! as List).single as Map)['location']! as Map;
      expect(location['uri'], endsWith('application-dev.yaml'));
      expect((hint['tooltip']! as Map)['value'], contains('application-dev'));
    });

    test('long and multi-line values are cut, empty ones quoted', () {
      expect(InlayHints.display(''), '""');
      expect(InlayHints.display('a\nb'), 'a…');
      expect(InlayHints.display('x' * 50), '${'x' * 40}…');
      expect(InlayHints.display(' padded '), '" padded "');
    });
  });
}

/// `line:column label` of [hint].
String _describe(Map<String, Object?> hint) {
  final position = hint['position']! as Map;
  final label = (hint['label']! as List).single as Map;
  return '${position['line']}:${position['character']} ${label['value']}';
}
