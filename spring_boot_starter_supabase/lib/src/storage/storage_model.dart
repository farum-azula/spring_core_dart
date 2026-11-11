/// What Storage knows about one object (or, in a listing, a folder).
final class StorageObjectInfo {
  /// An object [name]d so, with what Storage said about it.
  const StorageObjectInfo({
    required this.name,
    this.id,
    this.size,
    this.contentType,
    this.etag,
    this.cacheControl,
    this.createdAt,
    this.updatedAt,
    this.metadata = const {},
  });

  /// From a row of a listing (`name`, `id`, `metadata` with `size`,
  /// `mimetype`, `eTag`, `cacheControl`) or an object's information
  /// (`name`, `size`, `content_type`, `etag`, `cache_control`).
  factory StorageObjectInfo.fromJson(Map<String, Object?> json) {
    final metadata = switch (json['metadata']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    Object? either(String own, String nested) => json[own] ?? metadata[nested];
    return StorageObjectInfo(
      name: '${json['name'] ?? ''}',
      id: json['id'] as String?,
      size: switch (either('size', 'size')) {
        final num value => value.toInt(),
        final String text => int.tryParse(text),
        _ => null,
      },
      contentType: either('content_type', 'mimetype') as String?,
      etag: either('etag', 'eTag') as String?,
      cacheControl: either('cache_control', 'cacheControl') as String?,
      createdAt: _time(json['created_at']),
      updatedAt: _time(json['updated_at'] ?? json['last_modified']),
      metadata: Map.unmodifiable(metadata),
    );
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// The name: the last segment in a listing, the whole path otherwise.
  final String name;

  /// The object's id; `null` for a folder of a listing.
  final String? id;

  /// The size in bytes, when known.
  final int? size;

  /// The content type, when known.
  final String? contentType;

  /// The entity tag, when known.
  final String? etag;

  /// The `Cache-Control` the object is served with, when known.
  final String? cacheControl;

  /// When the object was created, when known.
  final DateTime? createdAt;

  /// When the object was last written, when known.
  final DateTime? updatedAt;

  /// Everything else Storage keeps about the object.
  final Map<String, Object?> metadata;

  /// Whether this row of a listing is a folder (it has no id).
  bool get isFolder => id == null;

  @override
  String toString() => 'StorageObjectInfo($name, $size bytes)';
}

/// A bucket of Storage.
final class StorageBucketInfo {
  /// The bucket [id].
  const StorageBucketInfo({
    required this.id,
    required this.name,
    this.isPublic = false,
    this.fileSizeLimit,
    this.allowedMimeTypes,
  });

  /// From Storage's JSON (`id`, `name`, `public`, `file_size_limit`,
  /// `allowed_mime_types`).
  factory StorageBucketInfo.fromJson(Map<String, Object?> json) =>
      StorageBucketInfo(
        id: '${json['id']}',
        name: '${json['name'] ?? json['id']}',
        isPublic: json['public'] == true,
        fileSizeLimit: switch (json['file_size_limit']) {
          final num value => value.toInt(),
          _ => null,
        },
        allowedMimeTypes: switch (json['allowed_mime_types']) {
          final List<Object?> list => [
            for (final item in list)
              if (item is String) item,
          ],
          _ => null,
        },
      );

  /// The bucket's id, used in every path.
  final String id;

  /// The bucket's name (usually its id).
  final String name;

  /// Whether its objects can be read without a token, by their public
  /// URL.
  final bool isPublic;

  /// The largest object it takes, in bytes; `null` for the project's
  /// limit.
  final int? fileSizeLimit;

  /// The content types it takes; `null` for any.
  final List<String>? allowedMimeTypes;

  @override
  String toString() => 'StorageBucketInfo($id)';
}

/// An address an object can be uploaded to without a token of its own
/// (given, for example, to a browser by a server).
final class SignedUpload {
  /// The upload to [url] of the object at [path].
  const SignedUpload({
    required this.url,
    required this.token,
    required this.path,
  });

  /// Where to `PUT` the object's bytes.
  final Uri url;

  /// The token inside [url], for clients that send it apart.
  final String token;

  /// The object's path in its bucket.
  final String path;
}
