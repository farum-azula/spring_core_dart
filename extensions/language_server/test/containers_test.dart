// Containers in tests (spring_boot_starter_test/containers.dart): the
// properties a @ServiceConnection container provides count as defined, the
// hover names the container, and misuse is reported.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _test = r'''
import 'package:spring_boot_starter_test/containers.dart';

@Testcontainers()
class DbTest {
  @Container()
  @ServiceConnection()
  static final postgres = PostgresContainer('postgres:17-alpine')..withReuse(true);

  @Container()
  @ServiceConnection()
  static final keycloak = KeycloakContainer().withProviderId('idp');

  @Container()
  static final plain = GenericContainer('redis:7');

  @Container()
  @ServiceConnection()
  static final generic = GenericContainer('redis:7');

  @Container()
  final notStatic = PostgresContainer();

  @Value(r'${spring.datasource.url}')
  late String url;

  @Value(r'${spring.security.oauth2.client.provider.idp.issuer-uri}')
  late String issuer;

  @Value(r'${spring.datasource.pool}')
  late String pool;
}
''';

const _unresolvedPool =
    "Cannot resolve property 'spring.datasource.pool' "
    'in any properties file';

void main() {
  late Directory root;
  late SpringWorkspace workspace;
  late String path;
  late String text;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('lsp_containers_');
    path = '${root.path}/test/db_test.dart';
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(_test);
    text = _test;
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  test('provided properties are not unresolved', () {
    expect(
      [
        for (final p in workspace.problems(path))
          if (p.message.startsWith('Cannot resolve')) p.message,
      ],
      [_unresolvedPool],
    );
  });

  test('hover names the container', () {
    final offset = text.indexOf('spring.datasource.url}') + 3;
    expect(
      workspace.hover(path, offset),
      contains('provided by `PostgresContainer postgres`'),
    );
    final issuer = text.indexOf('provider.idp.issuer-uri}') + 3;
    expect(
      workspace.hover(path, issuer),
      contains('provided by `KeycloakContainer keycloak`'),
    );
  });

  test('misuse is reported', () {
    final messages = [
      for (final p in workspace.problems(path))
        if (p.message.startsWith('@')) p.message,
    ];
    expect(messages, hasLength(2));
    expect(messages[0], contains("'generic'"));
    expect(messages[1], contains("'notStatic' must be static"));
  });
}
