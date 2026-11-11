import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/storage/storage_exception.dart';
import 'package:spring_boot_starter_supabase/src/storage/storage_model.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Supabase Storage (the bean `storageTemplate`): objects in buckets,
/// read and written as the current user (`SupabaseCredentials`), so the
/// policies of row-level security on `storage.objects` decide what a call
/// may do.
///
/// ```dart
/// await storage.upload('avatars', 'u1/avatar.png', bytes,
///     contentType: 'image/png', upsert: true);
/// final link = await storage.signedUrl('avatars', 'u1/avatar.png');
/// final settings = await storage.read<Settings>('config', 'app.json');
/// ```
///
/// A path is the object's place in its bucket, with `/` between folders;
/// a path with an empty, `.` or `..` segment is refused. For the paths of
/// one bucket kept in one place, declare a `@StorageBucket` interface.
///
/// Spring (Java): no counterpart in Spring itself; Spring Cloud AWS has
/// `S3Template` of the same shape.
final class StorageTemplate {
  /// A template over [http], reading and writing JSON with [mapper].
  StorageTemplate({required this.http, required this.mapper})
    : _serviceRole = false;

  StorageTemplate._(this.http, this.mapper, this._serviceRole);

  /// The project.
  final SupabaseHttp http;

  /// What reads and writes JSON ([read], [store]).
  final ObjectMapper mapper;

  final bool _serviceRole;

  /// The same template with every call made as the service role, which
  /// passes the policies (and is the only one that manages buckets).
  /// Needs `spring.supabase.service-role-key`.
  StorageTemplate asServiceRole() => StorageTemplate._(http, mapper, true);

  Future<T> _run<T>(Future<T> Function() call) =>
      _serviceRole ? http.credentials.asServiceRole(call) : call();

  // Objects.

  /// Writes [content] at [path] of [bucket]: bytes, a `String` (as UTF-8)
  /// or a `Stream<List<int>>` (read whole before it is sent).
  ///
  /// With [upsert] an object already there is replaced; without it, it is
  /// a [StorageObjectAlreadyExistsException]. [contentType] is
  /// `application/octet-stream` (`text/plain;charset=utf-8` for a
  /// `String`) unless given; [cacheControl] is how long browsers and the
  /// CDN may keep the object.
  Future<void> upload(
    String bucket,
    String path,
    Object content, {
    String? contentType,
    bool upsert = false,
    Duration? cacheControl,
  }) => _run(() async {
    final bytes = await _bytes(content);
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.post,
      '/object/${_bucket(bucket)}/${_path(path)}',
      headers: {
        HttpHeaders.contentTypeHeader:
            contentType ??
            (content is String
                ? 'text/plain;charset=utf-8'
                : 'application/octet-stream'),
        'x-upsert': '$upsert',
        if (cacheControl != null)
          HttpHeaders.cacheControlHeader: 'max-age=${cacheControl.inSeconds}',
      },
      body: bytes,
      timeout: _transfer,
    );
    _check(response, '$bucket/$path');
  });

  /// The bytes of the object at [path] of [bucket], as they arrive.
  ///
  /// The stream fails with a [StorageObjectNotFoundException] when there
  /// is no such object (or the caller may not read it).
  Stream<List<int>> download(String bucket, String path) async* {
    final response = await _run(
      () => http.stream(
        SupabaseService.storage,
        HttpMethod.get,
        '/object/authenticated/${_bucket(bucket)}/${_path(path)}',
      ),
    );
    if (!response.isSuccess) {
      _check(await response.read(), '$bucket/$path');
    }
    yield* response.body;
  }

  /// The whole object at [path] of [bucket] in memory.
  Future<Uint8List> downloadBytes(String bucket, String path) async {
    final builder = BytesBuilder(copy: false);
    await download(bucket, path).forEach(builder.add);
    return builder.takeBytes();
  }

  /// The object at [path] of [bucket] read as JSON into a `T`; `null`
  /// when there is no such object.
  ///
  /// [type] describes `T` when it is not a class of its own (a list, a
  /// map).
  Future<T?> read<T>(String bucket, String path, [TypeInfo<T>? type]) async {
    final Uint8List bytes;
    try {
      bytes = await downloadBytes(bucket, path);
    } on StorageObjectNotFoundException {
      return null;
    }
    return mapper.readValue<T>(utf8.decode(bytes), type);
  }

  /// Writes [value] as JSON at [path] of [bucket], replacing what is
  /// there unless [upsert] is false.
  Future<void> store(
    String bucket,
    String path,
    Object? value, {
    bool upsert = true,
  }) => upload(
    bucket,
    path,
    utf8.encode(mapper.writeValueAsString(value)),
    contentType: 'application/json',
    upsert: upsert,
  );

  /// The address of the object at [path] of a public [bucket]; anyone
  /// can read it without a token. Nothing is asked of Storage: the
  /// address exists whether the object does or not.
  ///
  /// With [download] the browser saves the object instead of showing it.
  Uri publicUrl(String bucket, String path, {bool download = false}) =>
      http.url(
        SupabaseService.storage,
        '/object/public/${_bucket(bucket)}/${_path(path)}',
        query: [if (download) const MapEntry('download', '')],
      );

  /// An address that reads the object at [path] of [bucket] without a
  /// token, for [expiresIn] (`spring.supabase.storage.signed-url-expiry`
  /// unless given).
  Future<Uri> signedUrl(String bucket, String path, {Duration? expiresIn}) =>
      _run(() async {
        final seconds =
            (expiresIn ?? http.properties.storage.signedUrlExpiry).inSeconds;
        if (seconds <= 0) {
          throw ArgumentError.value(expiresIn, 'expiresIn', 'must be positive');
        }
        final response = await http.send(
          SupabaseService.storage,
          HttpMethod.post,
          '/object/sign/${_bucket(bucket)}/${_path(path)}',
          json: {'expiresIn': seconds},
        );
        final json = _json(_check(response, '$bucket/$path'));
        final signed = json['signedURL'] ?? json['signedUrl'];
        if (signed is! String || signed.isEmpty) {
          throw StorageException(
            'Storage gave no signed URL for $bucket/$path',
            statusCode: response.statusCode.value,
          );
        }
        return _absolute(signed);
      });

  /// An address the object at [path] of [bucket] can be uploaded to once,
  /// with a `PUT`, without a token (for a browser, given by a server).
  Future<SignedUpload> signedUploadUrl(String bucket, String path) =>
      _run(() async {
        final response = await http.send(
          SupabaseService.storage,
          HttpMethod.post,
          '/object/upload/sign/${_bucket(bucket)}/${_path(path)}',
        );
        final json = _json(_check(response, '$bucket/$path'));
        final url = json['url'];
        if (url is! String || url.isEmpty) {
          throw StorageException(
            'Storage gave no upload URL for $bucket/$path',
            statusCode: response.statusCode.value,
          );
        }
        final absolute = _absolute(url);
        return SignedUpload(
          url: absolute,
          token: '${json['token'] ?? absolute.queryParameters['token'] ?? ''}',
          path: path,
        );
      });

  /// The objects and folders directly under [prefix] of [bucket] (its top
  /// when empty), [limit] of them from [offset], ordered by [sortBy]
  /// (`name`, `created_at`, `updated_at`, `last_accessed_at`).
  Future<List<StorageObjectInfo>> list(
    String bucket, {
    String prefix = '',
    int limit = 100,
    int offset = 0,
    String sortBy = 'name',
    bool descending = false,
    String? search,
  }) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.post,
      '/object/list/${_bucket(bucket)}',
      json: {
        'prefix': prefix,
        'limit': limit,
        'offset': offset,
        'sortBy': {'column': sortBy, 'order': descending ? 'desc' : 'asc'},
        'search': ?search,
      },
    );
    return [
      for (final item in _list(_check(response, bucket)))
        if (item is Map<String, Object?>) StorageObjectInfo.fromJson(item),
    ];
  });

  /// Removes the object at [path] of [bucket]. Nothing there is no error.
  Future<void> delete(String bucket, String path) => deleteAll(bucket, [path]);

  /// Removes the objects at [paths] of [bucket] and tells how many there
  /// were.
  Future<int> deleteAll(String bucket, List<String> paths) => _run(() async {
    if (paths.isEmpty) {
      return 0;
    }
    paths.forEach(_path);
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.delete,
      '/object/${_bucket(bucket)}',
      json: {'prefixes': paths},
    );
    return _list(_check(response, bucket)).length;
  });

  /// Moves the object at [from] of [bucket] to [to] (of [toBucket] when
  /// given).
  Future<void> move(
    String bucket,
    String from,
    String to, {
    String? toBucket,
  }) => _transferObject('move', bucket, from, to, toBucket);

  /// Copies the object at [from] of [bucket] to [to] (of [toBucket] when
  /// given).
  Future<void> copy(
    String bucket,
    String from,
    String to, {
    String? toBucket,
  }) => _transferObject('copy', bucket, from, to, toBucket);

  Future<void> _transferObject(
    String action,
    String bucket,
    String from,
    String to,
    String? toBucket,
  ) => _run(() async {
    _bucket(bucket);
    _path(from);
    _path(to);
    if (toBucket != null) {
      _bucket(toBucket);
    }
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.post,
      '/object/$action',
      json: {
        'bucketId': bucket,
        'sourceKey': from,
        'destinationKey': to,
        'destinationBucket': ?toBucket,
      },
    );
    _check(response, '$bucket/$from');
  });

  /// Whether there is an object at [path] of [bucket] that the caller may
  /// see.
  ///
  /// It asks for the object's information rather than its headers: an
  /// answer without a body (a `HEAD`) cannot tell "not there" from any
  /// other refusal.
  Future<bool> exists(String bucket, String path) async =>
      await info(bucket, path) != null;

  /// What Storage knows about the object at [path] of [bucket]; `null`
  /// when there is none.
  Future<StorageObjectInfo?> info(String bucket, String path) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.get,
      '/object/info/${_bucket(bucket)}/${_path(path)}',
    );
    try {
      return StorageObjectInfo.fromJson(
        _json(_check(response, '$bucket/$path')),
      );
    } on StorageObjectNotFoundException {
      return null;
    }
  });

  // Buckets (the service role's work, unless the project's policies say
  // otherwise).

  /// The buckets of the project.
  Future<List<StorageBucketInfo>> buckets() => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.get,
      '/bucket',
    );
    return [
      for (final item in _list(_check(response, 'buckets')))
        if (item is Map<String, Object?>) StorageBucketInfo.fromJson(item),
    ];
  });

  /// The bucket [id]; `null` when there is none.
  Future<StorageBucketInfo?> bucket(String id) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.get,
      '/bucket/${_bucket(id)}',
    );
    try {
      return StorageBucketInfo.fromJson(_json(_check(response, id)));
    } on StorageObjectNotFoundException {
      return null;
    }
  });

  /// Creates the bucket [id]. A bucket with that id is a
  /// [StorageObjectAlreadyExistsException].
  Future<void> createBucket(
    String id, {
    bool isPublic = false,
    int? fileSizeLimit,
    List<String>? allowedMimeTypes,
  }) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.post,
      '/bucket',
      json: {
        'id': _bucket(id),
        'name': id,
        'public': isPublic,
        'file_size_limit': ?fileSizeLimit,
        'allowed_mime_types': ?allowedMimeTypes,
      },
    );
    _check(response, id);
  });

  /// Changes the bucket [id].
  Future<void> updateBucket(
    String id, {
    required bool isPublic,
    int? fileSizeLimit,
    List<String>? allowedMimeTypes,
  }) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.put,
      '/bucket/${_bucket(id)}',
      json: {
        'id': id,
        'name': id,
        'public': isPublic,
        'file_size_limit': fileSizeLimit,
        'allowed_mime_types': allowedMimeTypes,
      },
    );
    _check(response, id);
  });

  /// Removes every object of the bucket [id].
  Future<void> emptyBucket(String id) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.post,
      '/bucket/${_bucket(id)}/empty',
    );
    _check(response, id);
  });

  /// Removes the bucket [id], which must be empty.
  Future<void> deleteBucket(String id) => _run(() async {
    final response = await http.send(
      SupabaseService.storage,
      HttpMethod.delete,
      '/bucket/${_bucket(id)}',
    );
    _check(response, id);
  });

  // Uploads are not cut off by the time limit of ordinary calls.
  static const _transfer = Duration(hours: 1);

  static Future<List<int>> _bytes(Object content) async => switch (content) {
    final String text => utf8.encode(text),
    final List<int> bytes => bytes,
    final Stream<List<int>> stream => await _collect(stream),
    _ => throw ArgumentError.value(
      content.runtimeType,
      'content',
      'must be bytes, a String or a Stream<List<int>>',
    ),
  };

  static Future<Uint8List> _collect(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await stream.forEach(builder.add);
    return builder.takeBytes();
  }

  // One segment, percent-encoded.
  static String _bucket(String bucket) {
    if (bucket.isEmpty ||
        bucket == '.' ||
        bucket == '..' ||
        bucket.contains('/') ||
        bucket.contains(r'\') ||
        _hasControl(bucket)) {
      throw ArgumentError.value(bucket, 'bucket', 'is not a bucket id');
    }
    return Uri.encodeComponent(bucket);
  }

  // Segments between `/`, each percent-encoded; none empty, `.` or `..`.
  static String _path(String path) {
    final segments = path.split('/');
    if (path.isEmpty ||
        _hasControl(path) ||
        path.contains(r'\') ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError.value(
        path,
        'path',
        'is not the path of an object (an empty, "." or ".." segment, a '
            'backslash or a control character)',
      );
    }
    return segments.map(Uri.encodeComponent).join('/');
  }

  static bool _hasControl(String text) =>
      text.runes.any((rune) => rune < 0x20 || rune == 0x7f);

  // Storage answers a signed URL as a path under its own address.
  Uri _absolute(String signed) {
    final relative = Uri.parse(signed.startsWith('/') ? signed : '/$signed');
    final base = http.url(SupabaseService.storage, '');
    return base.replace(
      path: '${base.path}${relative.path}',
      query: relative.hasQuery ? relative.query : null,
    );
  }

  static Map<String, Object?> _json(HttpResponse response) =>
      switch (_decode(response)) {
        final Map<String, Object?> map => map,
        _ => const {},
      };

  static List<Object?> _list(HttpResponse response) =>
      switch (_decode(response)) {
        final List<Object?> list => list,
        _ => const [],
      };

  static Object? _decode(HttpResponse response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(response.bodyText);
    } on FormatException {
      return null;
    }
  }

  // The response when it succeeded, else the exception of its failure.
  // Storage says its own status in the body (an object that is not there
  // has been answered with 400 and `"statusCode": "404"`): the body's
  // wins.
  static HttpResponse _check(HttpResponse response, String what) {
    if (response.isSuccess) {
      return response;
    }
    final json = _json(response);
    final http = response.statusCode.value;
    final status = switch (json['statusCode']) {
      final int value => value,
      final String text => int.tryParse(text) ?? http,
      _ => http,
    };
    final code = switch (json['error'] ?? json['code']) {
      final String text when text.isNotEmpty => text,
      _ => null,
    };
    final said = switch (json['message'] ?? json['error']) {
      final String text when text.isNotEmpty => text,
      _ => 'Storage answered $http',
    };
    final message = '$what: $said';
    final lower = '${code ?? ''} $said'.toLowerCase();
    if (status == 404 || lower.contains('not found') || code == 'NoSuchKey') {
      throw StorageObjectNotFoundException(
        message,
        statusCode: http,
        code: code,
      );
    }
    if (status == 409 ||
        lower.contains('duplicate') ||
        lower.contains('already exists')) {
      throw StorageObjectAlreadyExistsException(
        message,
        statusCode: http,
        code: code,
      );
    }
    if (status == 401 ||
        status == 403 ||
        lower.contains('row-level security') ||
        lower.contains('unauthorized')) {
      throw StoragePermissionDeniedException(
        message,
        statusCode: http,
        code: code,
      );
    }
    if (status == 413 || lower.contains('exceeded the maximum')) {
      throw StorageObjectTooLargeException(
        message,
        statusCode: http,
        code: code,
      );
    }
    throw StorageException(message, statusCode: http, code: code);
  }
}
