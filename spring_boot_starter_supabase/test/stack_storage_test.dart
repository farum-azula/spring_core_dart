@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, Storage: the declared bucket `Avatars` and the template
// against the real service, with the policies of the project (a user
// writes and reads only under the folder named after their id), URLs that
// really open, and what Storage answers for a missing object and for a
// duplicate.
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'stack_support.dart';

const _bucket = 'avatars';

Uint8List _bytes(int length, [int seed = 0]) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i + seed) % 256]);

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await stream.forEach(builder.add);
  return builder.takeBytes();
}

void main() {
  group('Storage of the stack', skip: Stack.skip, () {
    late StackApp ada;
    late StackApp bob;

    setUpAll(() async {
      Stack.require();
      ada = await StackApp.start();
      bob = await StackApp.start();
      await ada.signInAsNewUser();
      await bob.signInAsNewUser();
    });

    // Every object of a user is under their folder: removed after each
    // test, by the user themselves.
    Future<void> empty(StackApp app) => app.run(() async {
      Future<List<String>> under(String prefix) async => [
        for (final object in await app.storage.list(_bucket, prefix: prefix))
          if (object.isFolder)
            ...await under('$prefix/${object.name}')
          else
            '$prefix/${object.name}',
      ];
      await app.storage.deleteAll(_bucket, await under(app.userId));
    });

    // Waits until the bucket [id] has no object at its top.
    Future<void> emptied(StorageTemplate service, String id) async {
      for (var attempt = 0; attempt < 40; attempt++) {
        if ((await service.list(id)).isEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      fail('the bucket $id is not empty after 20 s');
    }

    tearDown(() async {
      await empty(ada);
      await empty(bob);
    });

    tearDownAll(() async {
      await ada.close();
      await bob.close();
    });

    group('the declared bucket', () {
      test('bytes go to the folder of #{authentication.name} and come '
          'back, whole and as a stream', () async {
        await ada.run(() async {
          final avatar = _bytes(70000);
          await ada.avatars.put(avatar);
          expect(await ada.avatars.bytes(ada.userId), avatar);
          expect(await ada.avatars.bytesOrNull(ada.userId), avatar);
          // Upsert: the second one replaces the first.
          final next = _bytes(1024, 7);
          await ada.avatars.put(next);
          expect(await ada.avatars.bytes(ada.userId), next);

          final info = await ada.storage.info(
            _bucket,
            '${ada.userId}/avatar.png',
          );
          expect(info?.size, next.length);

          // An upload from a stream, a download as a stream.
          final chunks = [_bytes(40000, 1), _bytes(40000, 2), _bytes(5, 3)];
          await ada.avatars.putStream(ada.userId, Stream.fromIterable(chunks));
          expect(
            await ada.storage.downloadBytes(
              _bucket,
              '${ada.userId}/stream.bin',
            ),
            [for (final chunk in chunks) ...chunk],
          );
          await ada.storage.upload(
            _bucket,
            '${ada.userId}/small.png',
            avatar,
            contentType: 'image/png',
          );
          expect(
            await _collect(ada.avatars.get(ada.userId, AvatarKind.small)),
            avatar,
          );
        });
      });

      test('text with its content type, and JSON as an object', () async {
        await ada.run(() async {
          await ada.avatars.putText(ada.userId, 'note.txt', 'héllo wörld');
          expect(
            utf8.decode(
              await ada.storage.downloadBytes(
                _bucket,
                '${ada.userId}/note.txt',
              ),
            ),
            'héllo wörld',
          );
          final info = await ada.storage.info(
            _bucket,
            '${ada.userId}/note.txt',
          );
          expect(info?.contentType, startsWith('text/plain'));

          expect(await ada.avatars.settings(ada.userId), isNull);
          await ada.avatars.saveSettings(
            ada.userId,
            Settings(theme: 'dark', fontSize: 16),
          );
          final settings = await ada.avatars.requiredSettings(ada.userId);
          expect(settings.theme, 'dark');
          expect(settings.fontSize, 16);
        });
      });

      test('the policies: a user writes and reads only under their own '
          'id', () async {
        await ada.run(() => ada.avatars.put(_bytes(64)));
        await bob.run(() async {
          await expectLater(
            bob.avatars.putText(ada.userId, 'intruder.txt', 'hi'),
            throwsA(isA<StoragePermissionDeniedException>()),
          );
          // An upsert over another user's object is no way around it.
          await expectLater(
            bob.storage.upload(
              _bucket,
              '${ada.userId}/avatar.png',
              _bytes(8),
              upsert: true,
            ),
            throwsA(isA<StoragePermissionDeniedException>()),
          );
          // The bucket is public: its objects are read by anyone who knows
          // the path, whatever the policies say (they decide the listing
          // and the writes).
          expect(await bob.avatars.bytes(ada.userId), hasLength(64));
          expect(
            await bob.storage.list(_bucket, prefix: ada.userId),
            isEmpty,
          );
          // Nothing there is no error, and nothing was removed.
          await bob.avatars.remove(ada.userId);
        });
        await ada.run(() async {
          expect(await ada.avatars.bytes(ada.userId), _bytes(64));
          expect(
            await ada.storage.exists(_bucket, '${ada.userId}/intruder.txt'),
            isFalse,
          );
        });
      });

      test('a public URL and a signed URL open without a token', () async {
        await ada.run(() async {
          final avatar = _bytes(2048, 3);
          await ada.avatars.put(avatar);

          final public = ada.avatars.publicLink(ada.userId);
          expect(
            '$public',
            startsWith('${Stack.url}/storage/v1/object/public/'),
          );
          final opened = await Stack.get(public);
          expect(opened.statusCode.value, 200);
          expect(opened.bodyBytes, avatar);

          final download = await Stack.get(
            Uri.parse(ada.avatars.publicDownload(ada.userId)),
          );
          expect(download.statusCode.value, 200);
          expect(
            download.headers['content-disposition'],
            contains('attachment'),
          );

          final signed = await ada.avatars.link(ada.userId);
          expect(signed.queryParameters['token'], isNotEmpty);
          final viaLink = await Stack.get(signed);
          expect(viaLink.statusCode.value, 200);
          expect(viaLink.bodyBytes, avatar);
          expect(
            (await Stack.get(
              Uri.parse(await ada.avatars.linkText(ada.userId)),
            )).bodyBytes,
            avatar,
          );

          // The token is the key: without it, or with another, nothing.
          final bare = await Stack.get(signed.replace(query: ''));
          expect(bare.isSuccess, isFalse);
          final forged = await Stack.get(
            signed.replace(
              queryParameters: {
                ...signed.queryParameters,
                'token': '${signed.queryParameters['token']}x',
              },
            ),
          );
          expect(forged.isSuccess, isFalse);
        });
      });

      test('a signed URL is refused after its expiry', () async {
        await ada.run(() async {
          final avatar = _bytes(128);
          await ada.avatars.put(avatar);
          final signed = await ada.storage.signedUrl(
            _bucket,
            '${ada.userId}/avatar.png',
            expiresIn: const Duration(seconds: 2),
          );
          expect((await Stack.get(signed)).bodyBytes, avatar);
          await Future<void>.delayed(const Duration(seconds: 4));
          final late_ = await Stack.get(signed);
          expect(late_.isSuccess, isFalse, reason: 'still open after expiry');
        });
      });

      test("a missing object and a duplicate are the starter's "
          'exceptions', () async {
        await ada.run(() async {
          await expectLater(
            ada.avatars.bytes(ada.userId),
            throwsA(isA<StorageObjectNotFoundException>()),
          );
          await expectLater(
            _collect(ada.avatars.get(ada.userId, AvatarKind.large)),
            throwsA(isA<StorageObjectNotFoundException>()),
          );
          expect(await ada.avatars.bytesOrNull(ada.userId), isNull);
          await expectLater(
            ada.avatars.link(ada.userId),
            throwsA(isA<StorageObjectNotFoundException>()),
          );
          expect(
            await ada.storage.info(_bucket, '${ada.userId}/avatar.png'),
            isNull,
          );
          expect(
            await ada.storage.exists(_bucket, '${ada.userId}/avatar.png'),
            isFalse,
          );

          // Without upsert the second upload is a duplicate.
          await ada.avatars.putText(ada.userId, 'once.txt', 'first');
          await expectLater(
            ada.avatars.putText(ada.userId, 'once.txt', 'second'),
            throwsA(isA<StorageObjectAlreadyExistsException>()),
          );
          expect(
            utf8.decode(
              await ada.storage.downloadBytes(
                _bucket,
                '${ada.userId}/once.txt',
              ),
            ),
            'first',
          );
        });
      });
    });

    group('the template', () {
      test('list, move, copy and delete as the user', () async {
        await ada.run(() async {
          final storage = ada.storage;
          final folder = ada.userId;
          await storage.upload(_bucket, '$folder/a.txt', 'a');
          await storage.upload(_bucket, '$folder/b.txt', 'bb');
          await storage.upload(_bucket, '$folder/docs/c.txt', 'ccc');

          final top = await storage.list(_bucket, prefix: folder);
          expect(top.map((o) => o.name).toSet(), {'a.txt', 'b.txt', 'docs'});
          expect(top.firstWhere((o) => o.name == 'docs').isFolder, isTrue);
          expect(top.firstWhere((o) => o.name == 'b.txt').size, 2);
          expect(
            (await storage.list(
              _bucket,
              prefix: folder,
              search: 'a.t',
            )).map((o) => o.name),
            ['a.txt'],
          );
          expect(
            (await storage.list(
              _bucket,
              prefix: '$folder/docs',
            )).map((o) => o.name),
            ['c.txt'],
          );

          await storage.move(_bucket, '$folder/a.txt', '$folder/moved.txt');
          expect(await storage.exists(_bucket, '$folder/a.txt'), isFalse);
          expect(
            utf8.decode(
              await storage.downloadBytes(_bucket, '$folder/moved.txt'),
            ),
            'a',
          );

          await storage.copy(_bucket, '$folder/b.txt', '$folder/copy.txt');
          expect(await storage.exists(_bucket, '$folder/b.txt'), isTrue);
          expect(
            utf8.decode(
              await storage.downloadBytes(_bucket, '$folder/copy.txt'),
            ),
            'bb',
          );

          // Out of the user's folder: the policies refuse the target.
          await expectLater(
            storage.move(
              _bucket,
              '$folder/moved.txt',
              '${bob.userId}/taken.txt',
            ),
            throwsA(isA<StorageException>()),
          );
          expect(await storage.exists(_bucket, '$folder/moved.txt'), isTrue);

          expect(
            await storage.deleteAll(_bucket, [
              '$folder/moved.txt',
              '$folder/copy.txt',
              '$folder/nothing-there.txt',
            ]),
            2,
          );
          await storage.delete(_bucket, '$folder/docs/c.txt');
          await storage.delete(_bucket, '$folder/b.txt');
          expect(await storage.list(_bucket, prefix: folder), isEmpty);
        });
      });

      test("buckets are the service role's: made, changed, emptied and "
          'deleted; a user may do none of it', () async {
        final id = Stack.unique('stack-');
        final service = ada.storage.asServiceRole();
        await ada.run(() async {
          await expectLater(
            ada.storage.createBucket(id),
            throwsA(isA<StorageException>()),
          );
          expect(await service.bucket(id), isNull);
        });

        await service.createBucket(
          id,
          fileSizeLimit: 1024,
          allowedMimeTypes: ['text/plain'],
        );
        try {
          final created = await service.bucket(id);
          expect(created?.id, id);
          expect(created?.isPublic, isFalse);
          expect(created?.fileSizeLimit, 1024);
          expect(created?.allowedMimeTypes, ['text/plain']);
          expect((await service.buckets()).map((b) => b.id), contains(id));
          expect(
            (await service.buckets()).map((b) => b.id),
            contains(_bucket),
          );

          await service.upload(
            id,
            'a/b.txt',
            'text',
            contentType: 'text/plain',
          );
          // The limits of the bucket are the server's to keep.
          await expectLater(
            service.upload(
              id,
              'too-large.txt',
              'x' * 4096,
              contentType: 'text/plain',
            ),
            throwsA(isA<StorageObjectTooLargeException>()),
          );
          // A private bucket without a policy: a user sees nothing in it.
          await ada.run(() async {
            await expectLater(
              ada.storage.downloadBytes(id, 'a/b.txt'),
              throwsA(isA<StorageObjectNotFoundException>()),
            );
          });

          await service.updateBucket(id, isPublic: true);
          expect((await service.bucket(id))?.isPublic, isTrue);
          final opened = await Stack.get(service.publicUrl(id, 'a/b.txt'));
          expect(opened.bodyText, 'text');

          // A bucket with objects is not deleted.
          await expectLater(
            service.deleteBucket(id),
            throwsA(isA<StorageException>()),
          );
          // Storage may empty a bucket in the background: waited for.
          await service.emptyBucket(id);
          await emptied(service, id);
        } finally {
          await service.deleteAll(id, ['a/b.txt']);
          await emptied(service, id);
          await service.deleteBucket(id);
        }
        expect(await service.bucket(id), isNull);
      });
    });
  });
}
