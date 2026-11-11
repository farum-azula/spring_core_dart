@Tags(['supabase'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late MockHttpTransport transport;
  late StorageTemplate storage;

  setUp(() {
    transport = MockHttpTransport();
    storage = StorageTemplate(
      http: http(transport, properties_: properties(serviceRole: true)),
      mapper: ObjectMapper(),
    );
  });

  group('upload', () {
    test('posts the bytes with the key, the token and the options', () async {
      transport
          .when(HttpMethod.post, '/storage/v1/object/avatars/u1/a b.png')
          .respond(200, json: {'Key': 'avatars/u1/a b.png'});
      await storage.upload(
        'avatars',
        'u1/a b.png',
        Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
        upsert: true,
        cacheControl: const Duration(hours: 1),
      );
      final request = transport.requests.single;
      expect(
        '${request.url}',
        '$projectUrl/storage/v1/object/avatars/u1/a%20b.png',
      );
      expect(request.body, [1, 2, 3]);
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(request.headers['Content-Type'], 'image/png');
      expect(request.headers['x-upsert'], 'true');
      expect(request.headers['Cache-Control'], 'max-age=3600');
      expect(request.followRedirects, isFalse);
    });

    test('reads a stream whole and sends text as UTF-8', () async {
      transport.when(HttpMethod.post, '/storage/v1/object/b/s').respond(200);
      transport.when(HttpMethod.post, '/storage/v1/object/b/t').respond(200);
      await storage.upload(
        'b',
        's',
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
      );
      await storage.upload('b', 't', 'é');
      expect(transport.requests[0].body, [1, 2, 3]);
      expect(transport.requests[1].body, utf8.encode('é'));
      expect(
        transport.requests[1].headers['Content-Type'],
        'text/plain;charset=utf-8',
      );
    });

    test('an object already there is its own exception', () async {
      transport
          .when(HttpMethod.post, '/storage/v1/object/b/p')
          .respond(
            400,
            json: {
              'statusCode': '409',
              'error': 'Duplicate',
              'message': 'The resource already exists',
            },
          );
      await expectLater(
        storage.upload('b', 'p', const [1]),
        throwsA(
          isA<StorageObjectAlreadyExistsException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'Duplicate'),
        ),
      );
    });

    test('a refused policy is a permission failure', () async {
      transport
          .when(HttpMethod.post, '/storage/v1/object/b/p')
          .respond(
            400,
            json: {
              'statusCode': '403',
              'error': 'Unauthorized',
              'message': 'new row violates row-level security policy',
            },
          );
      await expectLater(
        storage.upload('b', 'p', const [1]),
        throwsA(isA<StoragePermissionDeniedException>()),
      );
    });
  });

  group('paths', () {
    test('a path that could leave its bucket is refused before any call', () {
      for (final path in ['', '/a', 'a/', 'a//b', '../x', 'a/../b', './a']) {
        expect(
          () => storage.publicUrl('b', path),
          throwsArgumentError,
          reason: path,
        );
      }
      for (final bucket in ['', 'a/b', '..', '.']) {
        expect(
          () => storage.publicUrl(bucket, 'p'),
          throwsArgumentError,
          reason: bucket,
        );
      }
      expect(transport.requests, isEmpty);
    });

    test('a segment is percent-encoded, a "/" inside one cannot be made', () {
      expect(
        '${storage.publicUrl('b', 'a?b/c#d%2F.png')}',
        '$projectUrl/storage/v1/object/public/b/a%3Fb/c%23d%252F.png',
      );
    });
  });

  group('download', () {
    test('gives the bytes as they arrive', () async {
      transport
          .when(HttpMethod.get, '/storage/v1/object/authenticated/b/p')
          .respondStream(
            200,
            () => Stream.fromIterable([
              [1, 2],
              [3],
            ]),
          );
      expect(await storage.download('b', 'p').toList(), [
        [1, 2],
        [3],
      ]);
      expect(await storage.downloadBytes('b', 'p'), [1, 2, 3]);
    });

    test('no such object: the body says 404 under a 400', () async {
      transport
          .when(HttpMethod.get, '/storage/v1/object/authenticated/b/p')
          .respond(
            400,
            json: {
              'statusCode': '404',
              'error': 'not_found',
              'message': 'Object not found',
            },
          );
      await expectLater(
        storage.download('b', 'p').toList(),
        throwsA(isA<StorageObjectNotFoundException>()),
      );
      expect(await storage.read<Map<String, Object?>>('b', 'p'), isNull);
    });
  });

  test('JSON is written and read through the ObjectMapper', () async {
    transport
        .when(HttpMethod.post, '/storage/v1/object/c/app.json')
        .respond(
          200,
        );
    transport
        .when(HttpMethod.get, '/storage/v1/object/authenticated/c/app.json')
        .respond(200, json: {'theme': 'dark'});
    await storage.store('c', 'app.json', {'theme': 'dark'});
    expect(jsonDecode(utf8.decode(transport.requests.single.body!)), {
      'theme': 'dark',
    });
    expect(transport.requests.single.headers['x-upsert'], 'true');
    expect(await storage.read<Map<String, Object?>>('c', 'app.json'), {
      'theme': 'dark',
    });
  });

  group('signed URLs', () {
    test('the answer is completed to an address of the project', () async {
      transport
          .when(HttpMethod.post, '/storage/v1/object/sign/b/u1/a.png')
          .respond(
            200,
            json: {'signedURL': '/object/sign/b/u1/a.png?token=abc'},
          );
      final url = await storage.signedUrl(
        'b',
        'u1/a.png',
        expiresIn: const Duration(minutes: 5),
      );
      expect('$url', '$projectUrl/storage/v1/object/sign/b/u1/a.png?token=abc');
      expect(jsonDecode(utf8.decode(transport.requests.single.body!)), {
        'expiresIn': 300,
      });
    });

    test('the default expiry is the property', () async {
      transport
          .when(HttpMethod.post, '/storage/v1/object/sign/b/p')
          .respond(200, json: {'signedURL': '/object/sign/b/p?token=t'});
      await storage.signedUrl('b', 'p');
      expect(jsonDecode(utf8.decode(transport.requests.single.body!)), {
        'expiresIn': 3600,
      });
    });

    test('a signed upload URL carries its token', () async {
      transport
          .when(HttpMethod.post, '/storage/v1/object/upload/sign/b/p')
          .respond(
            200,
            json: {'url': '/object/upload/sign/b/p?token=up', 'token': 'up'},
          );
      final upload = await storage.signedUploadUrl('b', 'p');
      expect(
        '${upload.url}',
        '$projectUrl/storage/v1/object/upload/sign/b/p?token=up',
      );
      expect(upload.token, 'up');
    });
  });

  test('list, delete, move, copy, exists and info', () async {
    transport
        .when(HttpMethod.post, '/storage/v1/object/list/b')
        .respond(
          200,
          json: [
            {'name': 'folder', 'id': null},
            {
              'name': 'a.png',
              'id': 'i1',
              'metadata': {'size': 3, 'mimetype': 'image/png'},
            },
          ],
        );
    transport
        .when(HttpMethod.delete, '/storage/v1/object/b')
        .respond(
          200,
          json: [
            {'name': 'a.png'},
          ],
        );
    transport.when(HttpMethod.post, '/storage/v1/object/move').respond(200);
    transport.when(HttpMethod.post, '/storage/v1/object/copy').respond(200);
    transport
        .when(HttpMethod.get, '/storage/v1/object/info/b/no.png')
        .respond(
          400,
          json: {'statusCode': '404', 'message': 'Object not found'},
        );
    transport
        .when(HttpMethod.get, '/storage/v1/object/info/b/a.png')
        .respond(
          200,
          json: {'name': 'a.png', 'size': 3, 'content_type': 'image/png'},
        );

    final listed = await storage.list('b', prefix: 'u1', limit: 10);
    expect(listed.map((o) => o.name), ['folder', 'a.png']);
    expect(listed.first.isFolder, isTrue);
    expect(listed.last.size, 3);
    expect(listed.last.contentType, 'image/png');
    expect(jsonDecode(utf8.decode(transport.requests.last.body!)), {
      'prefix': 'u1',
      'limit': 10,
      'offset': 0,
      'sortBy': {'column': 'name', 'order': 'asc'},
    });

    expect(await storage.deleteAll('b', ['a.png']), 1);
    expect(jsonDecode(utf8.decode(transport.requests.last.body!)), {
      'prefixes': ['a.png'],
    });

    await storage.move('b', 'a.png', 'old/a.png');
    expect(jsonDecode(utf8.decode(transport.requests.last.body!)), {
      'bucketId': 'b',
      'sourceKey': 'a.png',
      'destinationKey': 'old/a.png',
    });
    await storage.copy('b', 'a.png', 'c.png', toBucket: 'other');
    expect(
      (jsonDecode(utf8.decode(transport.requests.last.body!))
          as Map<String, Object?>)['destinationBucket'],
      'other',
    );

    expect(await storage.exists('b', 'a.png'), isTrue);
    expect(await storage.exists('b', 'no.png'), isFalse);
    expect((await storage.info('b', 'a.png'))?.contentType, 'image/png');
  });

  test('asServiceRole sends the service role key, the template not', () async {
    transport
        .when(HttpMethod.post, '/storage/v1/bucket')
        .respond(200, json: {'name': 'reports'});
    transport.when(HttpMethod.get, '/storage/v1/bucket').respond(200, json: []);
    await storage.asServiceRole().createBucket('reports', isPublic: true);
    await storage.buckets();
    expect(transport.requests[0].headers['apikey'], 'service-key');
    expect(
      transport.requests[0].headers['Authorization'],
      'Bearer service-key',
    );
    expect(transport.requests[1].headers['apikey'], 'anon-key');
    expect(transport.requests[1].headers['Authorization'], 'Bearer anon-key');
  });

  test('no answer is SupabaseUnavailableException', () async {
    transport
        .when(HttpMethod.get, '/storage/v1/bucket')
        .fail(HttpTransportException('connection refused'));
    await expectLater(
      storage.buckets(),
      throwsA(isA<SupabaseUnavailableException>()),
    );
  });
}
