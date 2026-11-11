// The function built for AWS Lambda, run by Node: the entry file
// (index.mjs) is called with events as the Lambda runtime calls it
// (test/js/aws_runtime.mjs stands in for the runtime).
@Tags(['edge-node', 'integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

import 'platform_checks.dart';
import 'platform_support.dart';

void main() {
  final skip = hasNode ? null : 'node is not installed';
  late Directory directory;
  late LambdaFunctionClient client;
  late LambdaFunctionClient streaming;
  late LambdaFunctionClient wasm;
  late Directory wasmDirectory;
  final processes = <Background>[];

  Future<LambdaFunctionClient> run(Directory function, [String? mode]) async {
    final (process, match) = await Background.start(
      'node',
      ['$packageRoot/test/js/aws_runtime.mjs', function.path, ?mode],
      ready: RegExp(r'LISTENING (\d+)'),
      environment: {'GREETING': 'from-lambda'},
    );
    processes.add(process);
    return LambdaFunctionClient(
      Uri.parse(
        'http://127.0.0.1:${match.group(1)}'
        '/2015-03-31/functions/function/invocations',
      ),
    );
  }

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    directory = await buildFunction(EdgePlatform.aws);
    client = await run(directory);
    // The same compiled application behind the streaming entry.
    final other = Directory('${directory.path}_streaming')..createSync();
    for (final name in ['main.cjs', 'prelude.js']) {
      File('${directory.path}/$name').copySync('${other.path}/$name');
    }
    File(
      '${other.path}/index.mjs',
    ).writeAsStringSync(awsEntry(streaming: true));
    streaming = await run(other, 'streaming');
    wasmDirectory = await buildFunction(
      EdgePlatform.aws,
      target: EdgeTarget.wasm,
    );
    wasm = await run(wasmDirectory);
  });

  tearDownAll(() async {
    for (final process in processes) {
      await process.stop();
    }
    if (skip == null) {
      directory.deleteSync(recursive: true);
      Directory('${directory.path}_streaming').deleteSync(recursive: true);
      wasmDirectory.deleteSync(recursive: true);
    }
  });

  group('a function URL (payload 2.0)', skip: skip, () {
    platformChecks(
      () => client,
      platform: 'aws',
      greeting: 'from-lambda',
    );

    test('the address of the client is the sourceIp of the event', () async {
      final answer = lambdaAnswer(
        await client.invoke(
          lambdaEvent(
            'GET',
            '/hello',
            sourceIp: '192.0.2.44',
            headers: {'x-forwarded-for': '198.51.100.1'},
          ),
        ),
      );
      expect((answer.json! as Map)['remote'], '192.0.2.44');
    });

    test('text is text, anything else base64; cookies apart', () async {
      final json = await client.invoke(lambdaEvent('GET', '/hello'));
      expect(json['isBase64Encoded'], isFalse);
      expect(json['body'], startsWith('{"message"'));
      final bytes = await client.invoke(lambdaEvent('GET', '/download'));
      expect(bytes['isBase64Encoded'], isTrue);
      expect(base64.decode(bytes['body']! as String), [
        0,
        159,
        146,
        150,
        255,
        1,
        2,
      ]);
      final cookies = await client.invoke(lambdaEvent('GET', '/cookies'));
      expect(cookies['cookies'], ['a=1; Path=/; HttpOnly', 'b=2; Path=/']);
      expect(cookies['headers'], isNot(contains('set-cookie')));
    });

    test('the cookies of the event are the Cookie header', () async {
      final event = lambdaEvent(
        'POST',
        '/echo',
        headers: {'content-type': 'application/json'},
        body: utf8.encode('{}'),
      )..['cookies'] = ['a=1', 'b=2'];
      expect((await client.invoke(event))['statusCode'], 200);
    });
  });

  group('compiled to WebAssembly', skip: skip, () {
    platformChecks(() => wasm, platform: 'aws', greeting: 'from-lambda');

    test('the module and its loader are what was built', () {
      expect(
        [
          for (final file in wasmDirectory.listSync())
            file.uri.pathSegments.last,
        ],
        unorderedEquals([
          'app.wasm',
          'app.mjs',
          'main.mjs',
          'prelude.js',
          'index.mjs',
        ]),
      );
    });
  });

  group('an EventBridge schedule', skip: skip, () {
    Future<Object?> seen() async =>
        lambdaAnswer(await client.invoke(lambdaEvent('GET', '/scheduled')))
            .json;

    Future<HttpClientResponse> raw(Map<String, Object?> event) async {
      final request = await HttpClient().postUrl(client.invocations);
      request.add(utf8.encode(jsonEncode(event)));
      return await request.close();
    }

    test('the handlers of the application run', () async {
      final response = await raw({
        'version': '0',
        'detail-type': 'Scheduled Event',
        'source': 'aws.events',
        'time': '2026-11-11T03:00:00Z',
        'resources': ['arn:aws:events:eu-west-1:1:rule/nightly'],
        'detail': <String, Object?>{},
      });
      expect(response.statusCode, 200);
      await response.drain<void>();
      expect(
        await seen(),
        contains('aws:arn:aws:events:eu-west-1:1:rule/nightly'),
      );
    });

    test('a handler that fails fails the invocation', () async {
      final response = await raw({
        'detail-type': 'Scheduled Event',
        'source': 'aws.events',
        'resources': ['fail'],
      });
      expect(response.statusCode, 500);
      await response.drain<void>();
      // The function lives on.
      expect(await seen(), isA<List<Object?>>());
    });
  });

  group('API Gateway REST (payload 1.0)', skip: skip, () {
    test('the event becomes a request, the answer its result', () async {
      final result = await client.invoke({
        'httpMethod': 'GET',
        'path': '/hello',
        'multiValueQueryStringParameters': {
          'name': ['Ada L&x'],
        },
        'multiValueHeaders': {
          'Host': ['api.example.com'],
          'X-Forwarded-For': ['198.51.100.1'],
        },
        'requestContext': {
          'identity': {'sourceIp': '192.0.2.50'},
        },
        'body': null,
        'isBase64Encoded': false,
      });
      expect(result['statusCode'], 200);
      final body = jsonDecode(result['body']! as String) as Map;
      // API Gateway decoded the query: it is encoded again as a value.
      expect(body['message'], 'hello Ada L&x');
      expect(body['remote'], '192.0.2.50');
      expect(
        (result['multiValueHeaders']! as Map)['content-type'],
        ['application/json'],
      );
      expect(result, isNot(contains('cookies')));
    });

    test('every cookie in multiValueHeaders', () async {
      final result = await client.invoke({
        'httpMethod': 'GET',
        'path': '/cookies',
        'headers': {'Host': 'api.example.com'},
        'requestContext': {
          'identity': {'sourceIp': '192.0.2.50'},
        },
      });
      expect((result['multiValueHeaders']! as Map)['set-cookie'], [
        'a=1; Path=/; HttpOnly',
        'b=2; Path=/',
      ]);
    });

    test('a body in base64 is decoded', () async {
      final result = await client.invoke({
        'httpMethod': 'POST',
        'path': '/echo',
        'headers': {
          'Host': 'api.example.com',
          'Content-Type': 'application/json',
        },
        'requestContext': {
          'identity': {'sourceIp': '192.0.2.50'},
        },
        'body': base64.encode(utf8.encode('{"a":1}')),
        'isBase64Encoded': true,
      });
      expect(jsonDecode(result['body']! as String), {
        'body': {'a': 1},
        'trace': null,
      });
    });
  });

  group('an Application Load Balancer', skip: skip, () {
    test('the query as it was sent; the address the balancer added', () async {
      final result = await client.invoke({
        'requestContext': {
          'elb': {'targetGroupArn': 'arn:aws:elasticloadbalancing:x'},
        },
        'httpMethod': 'GET',
        'path': '/hello',
        'queryStringParameters': {'name': 'Ada%20L'},
        'headers': {
          'host': 'lb.example.com',
          // What the client sent, then what the balancer saw.
          'x-forwarded-for': '198.51.100.1, 192.0.2.60',
          'x-forwarded-proto': 'https',
        },
        'body': '',
        'isBase64Encoded': false,
      });
      expect(result['statusCode'], 200);
      final body = jsonDecode(result['body']! as String) as Map;
      expect(body['message'], 'hello Ada L');
      expect(body['remote'], '192.0.2.60');
      expect(body['secure'], isTrue);
    });
  });

  group('a response-streaming handler', skip: skip, () {
    test('the status and the headers first, then the body', () async {
      final result = await streaming.invoke(lambdaEvent('GET', '/events'));
      expect(result['statusCode'], 200);
      expect(
        (result['headers']! as Map)['content-type'],
        startsWith('text/event-stream'),
      );
      expect(result['ended'], isTrue);
      expect(result['chunks'], greaterThan(1));
      expect(result['body'], contains('data: {"tick":3}'));
    });

    test('a complete answer and its cookies', () async {
      final hello = await streaming.invoke(lambdaEvent('GET', '/hello'));
      expect(
        jsonDecode(hello['body']! as String),
        containsPair(
          'platform',
          'aws',
        ),
      );
      final cookies = await streaming.invoke(lambdaEvent('GET', '/cookies'));
      expect(cookies['cookies'], hasLength(2));
      final none = await streaming.invoke(lambdaEvent('GET', '/nothing'));
      expect(none['statusCode'], 204);
      expect(none['body'], isEmpty);
    });

    test('work given to waitUntil ends before the invocation does', () async {
      final before = jsonDecode(
        (await streaming.invoke(lambdaEvent('GET', '/later')))['body']!
            as String,
      );
      await streaming.invoke(lambdaEvent('POST', '/later'));
      final after = jsonDecode(
        (await streaming.invoke(lambdaEvent('GET', '/later')))['body']!
            as String,
      );
      expect(after, (before as int) + 1);
    });
  });
}
