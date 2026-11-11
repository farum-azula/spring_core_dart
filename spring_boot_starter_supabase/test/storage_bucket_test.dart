@Tags(['supabase'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';
import 'support.dart';

void main() {
  late MockHttpTransport transport;

  setUp(() => transport = MockHttpTransport());

  Future<void> withAvatars(
    Future<void> Function(Avatars avatars) body, [
    List<String> properties = const [],
  ]) => appRunner(transport, properties).runAsync((context) async {
    expect(context.startupFailure, isNull);
    await body(context.getBean<Avatars>());
  });

  test('an upload goes to the path of the current user', () async {
    transport
        .when(HttpMethod.post, '/storage/v1/object/avatars/ada/avatar.png')
        .respond(200);
    await withAvatars(
      (avatars) => asUser(
        'ada',
        () => avatars.put(Uint8List.fromList([1, 2])),
      ),
    );
    final request = transport.requests.single;
    expect(request.body, [1, 2]);
    expect(request.headers['x-upsert'], 'true');
  });

  test('nobody signed in: the upload is refused before any call', () async {
    await withAvatars((avatars) async {
      await expectLater(
        avatars.put(Uint8List.fromList([1])),
        throwsArgumentError,
      );
    });
    expect(transport.requests, isEmpty);
  });

  test('the bucket comes from the configuration', () async {
    transport
        .when(HttpMethod.delete, '/storage/v1/object/people')
        .respond(200, json: []);
    await withAvatars((avatars) => avatars.remove('u1'), [
      'app.buckets.avatars=people',
    ]);
    expect(jsonDecode(utf8.decode(transport.requests.single.body!)), {
      'prefixes': ['u1/avatar.png'],
    });
  });

  test('parameters, an expression and the marked content', () async {
    transport
        .when(HttpMethod.post, '/storage/v1/object/avatars/u1/note.txt')
        .respond(200);
    transport
        .when(HttpMethod.post, '/storage/v1/object/avatars/u1/stream.bin')
        .respond(200);
    transport
        .when(
          HttpMethod.get,
          '/storage/v1/object/authenticated/avatars/u1/large.png',
        )
        .respondStream(
          200,
          () => Stream.fromIterable([
            [7],
          ]),
        );
    await withAvatars((avatars) async {
      await avatars.putText('u1', 'note.txt', 'hello');
      await avatars.putStream(
        'u1',
        Stream.fromIterable([
          [1],
          [2],
        ]),
      );
      expect(await avatars.get('u1', AvatarKind.large).toList(), [
        [7],
      ]);
    });
    expect(utf8.decode(transport.requests[0].body!), 'hello');
    expect(transport.requests[0].headers['Content-Type'], 'text/plain');
    expect(transport.requests[0].headers['x-upsert'], 'false');
    expect(transport.requests[1].body, [1, 2]);
  });

  test('a value that would leave the folder is refused, no call', () async {
    await withAvatars((avatars) async {
      for (final userId in ['../admin', 'a/b', '..', '']) {
        await expectLater(avatars.remove(userId), throwsArgumentError);
        await expectLater(avatars.bytes(userId), throwsArgumentError);
        expect(() => avatars.publicLink(userId), throwsArgumentError);
        expect(
          () => avatars.get(userId, AvatarKind.small),
          throwsArgumentError,
        );
      }
    });
    expect(transport.requests, isEmpty);
  });

  test('bytes, and null for a nullable result when there is none', () async {
    transport
        .when(
          HttpMethod.get,
          '/storage/v1/object/authenticated/avatars/u1/avatar.png',
        )
        .respond(200, bytes: [9, 9]);
    transport
        .when(
          HttpMethod.get,
          '/storage/v1/object/authenticated/avatars/u2/avatar.png',
        )
        .respond(404, json: {'message': 'Object not found'});
    await withAvatars((avatars) async {
      expect(await avatars.bytes('u1'), [9, 9]);
      expect(await avatars.bytesOrNull('u2'), isNull);
      await expectLater(
        avatars.bytes('u2'),
        throwsA(isA<StorageObjectNotFoundException>()),
      );
    });
  });

  test('signed and public URLs, as Uri and as String', () async {
    transport
        .when(HttpMethod.post, '/storage/v1/object/sign/avatars/u1/avatar.png')
        .respond(
          200,
          json: {'signedURL': '/object/sign/avatars/u1/avatar.png?token=t'},
        );
    await withAvatars((avatars) async {
      const signed =
          '$projectUrl/storage/v1/object/sign/avatars/u1/avatar.png?token=t';
      expect('${await avatars.link('u1')}', signed);
      expect(await avatars.linkText('u1'), signed);
      expect(
        '${avatars.publicLink('u 1')}',
        '$projectUrl/storage/v1/object/public/avatars/u%201/avatar.png',
      );
      expect(
        avatars.publicDownload('u1'),
        '$projectUrl/storage/v1/object/public/avatars/u1/avatar.png'
        '?download=',
      );
    });
    expect(jsonDecode(utf8.decode(transport.requests[0].body!)), {
      'expiresIn': 300,
    });
    expect(jsonDecode(utf8.decode(transport.requests[1].body!)), {
      'expiresIn': 3600,
    });
    expect(transport.requests, hasLength(2));
  });

  test('a JSON object is read into its class and written from it', () async {
    transport
        .when(
          HttpMethod.get,
          '/storage/v1/object/authenticated/avatars/u1/settings.json',
        )
        .respond(200, json: {'theme': 'dark', 'fontSize': 16});
    transport
        .when(
          HttpMethod.get,
          '/storage/v1/object/authenticated/avatars/u2/settings.json',
        )
        .respond(404, json: {'message': 'Object not found'});
    transport
        .when(HttpMethod.post, '/storage/v1/object/avatars/u1/settings.json')
        .respond(200);
    await withAvatars((avatars) async {
      final settings = await avatars.settings('u1');
      expect(settings?.theme, 'dark');
      expect(settings?.fontSize, 16);
      expect((await avatars.requiredSettings('u1')).theme, 'dark');
      expect(await avatars.settings('u2'), isNull);
      await expectLater(
        avatars.requiredSettings('u2'),
        throwsA(isA<StorageObjectNotFoundException>()),
      );
      await avatars.saveSettings('u1', Settings(theme: 'light'));
    });
    final written = transport.requests.last;
    expect(jsonDecode(utf8.decode(written.body!)), {
      'theme': 'light',
      'fontSize': 14,
    });
    expect(written.headers['Content-Type'], 'application/json');
    expect(written.headers['x-upsert'], 'true');
  });
}
