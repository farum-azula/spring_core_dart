// docs/configuration.md: every YAML and .properties example parses with
// the real loaders, and each side-by-side pair (YAML | .properties) means
// the same properties, so the two columns cannot drift apart.
@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

/// docs/configuration.md, from the package folder or the repository root.
final _doc = File('docs/configuration.md').existsSync()
    ? 'docs/configuration.md'
    : '../docs/configuration.md';

/// The fenced blocks of [markdown]: (language, code, line).
List<(String, String, int)> blocks(String markdown) {
  final result = <(String, String, int)>[];
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final open = RegExp(r'^```(\w+)\s*$').firstMatch(lines[i]);
    if (open == null) {
      continue;
    }
    final start = i + 1;
    final code = <String>[];
    for (i++; i < lines.length && lines[i] != '```'; i++) {
      code.add(lines[i]);
    }
    result.add((open[1]!, code.join('\n'), start));
  }
  return result;
}

/// The documents of [code] in [language], flattened like the config loader.
List<Map<String, String>> load(String language, String code) {
  final sources = language == 'yaml'
      ? YamlPropertySourceLoader().load('doc', code)
      : const PropertiesPropertySourceLoader().load('doc', code);
  return [
    for (final source in sources.cast<EnumerablePropertySource<Object>>())
      {
        for (final name in source.propertyNames)
          name: '${source.getProperty(name)}',
      },
  ];
}

String _normalized(String value) =>
    value.split(',').map((part) => part.trim()).join(',');

/// Whether [yaml] and [properties] hold the same properties: equal keys and
/// values, a YAML list matching a comma-separated value or indexed keys.
List<String> differences(
  Map<String, String> yaml,
  Map<String, String> properties,
) {
  final problems = <String>[];
  final listed = <String, List<String>>{};
  for (final MapEntry(:key, :value) in yaml.entries) {
    final match = RegExp(r'^(.*)\[(\d+)\]$').firstMatch(key);
    if (match != null) {
      (listed[match[1]!] ??= []).add(value);
    }
  }
  final seen = <String>{};
  for (final MapEntry(:key, :value) in properties.entries) {
    if (yaml[key] case final same?) {
      seen.add(key);
      if (_normalized(same) != _normalized(value)) {
        problems.add('$key: YAML "$same", .properties "$value"');
      }
    } else if (listed[key] case final list?) {
      seen.addAll([for (var i = 0; i < list.length; i++) '$key[$i]']);
      if (list.map((v) => v.trim()).join(',') != _normalized(value)) {
        problems.add('$key: YAML $list, .properties "$value"');
      }
    } else {
      problems.add('$key: only in .properties');
    }
  }
  for (final key in yaml.keys) {
    if (!seen.contains(key)) {
      problems.add('$key: only in YAML');
    }
  }
  return problems;
}

void main() {
  final markdown = File(_doc).readAsStringSync();
  final all = blocks(markdown);

  test('the page has side-by-side examples', () {
    expect(all.where((b) => b.$1 == 'yaml'), hasLength(greaterThan(20)));
  });

  for (final (language, code, line) in all) {
    if (language != 'yaml' && language != 'properties') {
      continue;
    }
    test('$language example at line $line parses', () {
      expect(() => load(language, code), returnsNormally);
    });
  }

  // A pair: a YAML block followed by a .properties block in one table.
  final tables = RegExp(r'<table>([\s\S]*?)</table>').allMatches(markdown);
  for (final table in tables) {
    final inside = blocks(table[1]!);
    if (inside.length != 2 ||
        inside[0].$1 != 'yaml' ||
        inside[1].$1 != 'properties') {
      continue;
    }
    final line = '\n'.allMatches(markdown.substring(0, table.start)).length + 1;
    test('the two columns of the table at line $line mean the same', () {
      final yaml = load('yaml', inside[0].$2);
      final properties = load('properties', inside[1].$2);
      expect(yaml.length, properties.length, reason: 'documents');
      for (var i = 0; i < yaml.length; i++) {
        expect(
          differences(yaml[i], properties[i]),
          isEmpty,
          reason: 'document ${i + 1}',
        );
      }
    });
  }
}
