// `this` in a security expression on an HTTP service interface
// (@HttpExchange, @ImportHttpServices): the generated client, against a real
// local HTTP server. The application is built, written out and run in its
// own process.
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:test/test.dart';

import '../support/generated_app.dart';

const _library = '''
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_security_core/spring_security_core.dart';

@HttpExchange()
abstract interface class Api {
  @GetExchange('/owner')
  Future<String> owner();

  @PreAuthorize('#who == authentication.name')
  @GetExchange('/argument')
  Future<String> argument(@RequestParam('who') String who);

  @PreAuthorize('this.owner()')
  @GetExchange('/bare')
  Future<String> bare();

  @PreAuthorize('this.owner() != null')
  @GetExchange('/not-null')
  Future<String> notNull();

  @PreAuthorize("this.owner() != 'nobody'")
  @GetExchange('/not-equal')
  Future<String> notEqual();

  @PreAuthorize('this.owner() == authentication.name')
  @GetExchange('/equal')
  Future<String> equal();

  @PreAuthorize('this.nothing == 1')
  @GetExchange('/unreadable')
  Future<String> unreadable();

  @PreAuthorize('#root.this != null and #who == authentication.name')
  @GetExchange('/root')
  Future<String> throughRoot(@RequestParam('who') String who);

  @PostAuthorize('this != null and returnObject == authentication.name')
  @GetExchange('/after')
  Future<String> after();
}

@Configuration()
@ImportHttpServices(group: 'api', types: [Api])
class Clients {}
''';

const _main = r'''
import 'dart:convert';
import 'dart:io';

import 'package:pkg/app.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'spring_gen/main.spring.dart';

final hits = <String>[];

Future<Map<String, Object?>> call(Future<String> Function() body) async {
  hits.clear();
  String outcome;
  try {
    outcome = 'value:${await body()}';
  } on AuthorizationDeniedException {
    outcome = 'denied';
  } on ArgumentError catch (e) {
    outcome = '$e'.contains('asynchronous') ? 'refused:async' : 'refused';
  } on Object catch (e) {
    outcome = 'error:${e.runtimeType}:$e';
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return {'outcome': outcome, 'hits': [...hits]};
}

Future<T> as<T>(String name, Future<T> Function() body) {
  final user = User.withUsername(name).password(null).roles(['USER']).build();
  return SecurityContextHolder.runWithContext(
    body,
    SecurityContextImpl(
      UsernamePasswordAuthenticationToken.authenticated(
        user,
        null,
        user.authorities,
      ),
    ),
  );
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    hits.add(request.uri.path);
    request.response.headers.contentType = ContentType.text;
    request.response.write('ada');
    await request.response.close();
  });
  final context = await runApplicationAsync([
    '--spring.main.banner-mode=off',
    '--logging.level.root=off',
    '--spring.main.web-application-type=none',
    // The group's base URL; its host (a loopback address) is allowed by
    // itself.
    '--spring.http.serviceclient.api.base-url=http://127.0.0.1:${server.port}',
    ...args,
  ]);
  final api = context.getBean<Api>();
  Future<Map<String, Object?>> all(String me) async => {
    'argumentOwn': await call(() => api.argument(me)),
    'argumentOther': await call(() => api.argument('carol')),
    'bare': await call(api.bare),
    'notNull': await call(api.notNull),
    'notEqual': await call(api.notEqual),
    'equal': await call(api.equal),
    'unreadable': await call(api.unreadable),
    'rootOwn': await call(() => api.throughRoot(me)),
    'rootOther': await call(() => api.throughRoot('carol')),
    'after': await call(api.after),
  };
  final ada = await as('ada', () => all('ada'));
  final bob = await as('bob', () => all('bob'));
  print('RESULT ${jsonEncode({'ada': ada, 'bob': bob})}');
  context.close();
  await server.close(force: true);
  exit(0);
}
''';

Map<String, Object?> _call(String outcome, [List<String> hits = const []]) => {
  'outcome': outcome,
  'hits': hits,
};

void main() {
  test('this on a client: a denied call never reaches the server', () async {
    final refused = {
      'argumentOther': _call('denied'),
      'bare': _call('refused:async'),
      'notNull': _call('refused:async'),
      'notEqual': _call('refused:async'),
      'equal': _call('refused:async'),
      'unreadable': _call('refused'),
      'rootOther': _call('denied'),
    };
    final allowed = {
      'argumentOwn': _call('value:ada', ['/argument']),
      'rootOwn': _call('value:ada', ['/root']),
    };
    expect(
      await runGeneratedApp({
        'lib/app.dart': _library,
        'bin/main.dart': _main,
      }),
      {
        'ada': {
          ...refused,
          ...allowed,
          'after': _call('value:ada', ['/after']),
        },
        // After the call, as in Spring: the request was made, its answer
        // is withheld.
        'bob': {
          ...refused,
          ...allowed,
          'after': _call('denied', ['/after']),
        },
      },
    );
  }, timeout: const Timeout(Duration(minutes: 25)));
}
