import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  const loader = YamlPropertySourceLoader();

  Map<String, Object?> load(String yaml) =>
      (loader.load('application.yml', yaml).single as MapPropertySource).source;

  test('handles yml and yaml', () {
    expect(loader.fileExtensions, ['yml', 'yaml']);
  });

  test("flattens like Spring's YamlProcessor", () {
    final properties = load('''
server:
  port: 8080
  ssl:
    enabled: true
app:
  ratio: 1.5
  name: demo
  hosts:
    - a.example
    - b.example
  servers:
    - name: one
      tags: [x, y]
    - name: two
''');
    expect(properties, {
      'server.port': 8080,
      'server.ssl.enabled': true,
      'app.ratio': 1.5,
      'app.name': 'demo',
      'app.hosts[0]': 'a.example',
      'app.hosts[1]': 'b.example',
      'app.servers[0].name': 'one',
      'app.servers[0].tags[0]': 'x',
      'app.servers[0].tags[1]': 'y',
      'app.servers[1].name': 'two',
    });
  });

  test("empty values, ~ and null are '' (also empty lists and maps)", () {
    expect(
      load('''
a:
b: ~
c: null
d: []
e: {}
f: ""
'''),
      {'a': '', 'b': '', 'c': '', 'd': '', 'e': '', 'f': ''},
    );
  });

  test('block scalars and quoted strings stay as written', () {
    final properties = load('''
literal: |
  line one
  line two
folded: >
  folded
  text
quoted: "  spaced  "
single: 'it''s'
date: 2024-01-01
''');
    expect(properties['literal'], 'line one\nline two\n');
    expect(properties['folded'], 'folded text\n');
    expect(properties['quoted'], '  spaced  ');
    expect(properties['single'], "it's");
    // No timestamps, like Spring Boot's NoTimestampResolver.
    expect(properties['date'], '2024-01-01');
  });

  test('non-string keys go in brackets; bracketed keys keep their dots', () {
    expect(
      load('''
map:
  1: one
  true: yes
  "[a.b]": dotted
  "[X-Shop]": header
'''),
      {
        'map[1]': 'one',
        'map[true]': 'yes',
        'map[a.b]': 'dotted',
        'map[X-Shop]': 'header',
      },
    );
  });

  test('merge keys copy entries the mapping does not define', () {
    expect(
      load('''
defaults: &defaults
  timeout: 5s
  retries: 3
first: &first
  retries: 9
  region: eu
service:
  <<: [*first, *defaults]
  timeout: 10s
'''),
      {
        'defaults.timeout': '5s',
        'defaults.retries': 3,
        'first.retries': 9,
        'first.region': 'eu',
        'service.timeout': '10s',
        'service.retries': 9,
        'service.region': 'eu',
      },
    );
  });

  test('documents: one source each, empty ones skipped', () {
    final sources = loader.load('application.yml', '''
a: 1
---
---
spring.config.activate.on-profile: dev
a: 2
''');
    expect(
      [for (final s in sources) s.name],
      ['application.yml (document #0)', 'application.yml (document #1)'],
    );
    expect(sources[1].getProperty('spring.config.activate.on-profile'), 'dev');
    expect(loader.load('empty.yml', ''), isEmpty);
    expect(loader.load('comment.yml', '# nothing\n'), isEmpty);
  });

  test('a document that is a scalar is the property "document"', () {
    expect(load('just text'), {'document': 'just text'});
  });

  test('duplicate keys and invalid YAML fail', () {
    expect(() => loader.load('a.yml', 'a: 1\na: 2'), throwsFormatException);
    expect(() => loader.load('a.yml', 'a: [1'), throwsFormatException);
  });

  test('flatten is usable on decoded JSON', () {
    expect(
      YamlPropertySourceLoader.flatten({
        'a': {
          'b': [1, 2],
        },
      }),
      {'a.b[0]': 1, 'a.b[1]': 2},
    );
  });

  // The seventh review: a YAML nested thousands of levels deep overflowed
  // the stack, and the StackOverflowError crashed the start (and the web
  // dev config builder) instead of naming the file.
  test('nesting too deep to read is a FormatException', () {
    final deep = 'a: ${'[' * 20000}${']' * 20000}\n';
    expect(
      () => loader.load('application.yml', deep),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('nested too deeply'),
        ),
      ),
    );
  });
}
