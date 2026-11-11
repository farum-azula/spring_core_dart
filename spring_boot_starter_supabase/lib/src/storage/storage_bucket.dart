import 'dart:async';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_supabase/src/expression/call_template.dart';
import 'package:spring_boot_starter_supabase/src/storage/storage_exception.dart';
import 'package:spring_boot_starter_supabase/src/storage/storage_template.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Marks an interface whose methods read and write the objects of one
/// bucket of Storage; the generator writes the bean.
///
/// ```dart
/// @StorageBucket('avatars')
/// abstract interface class Avatars {
///   @Upload('#{authentication.name}/avatar.png', upsert: true)
///   Future<void> put(Uint8List bytes);
///
///   @Download('{userId}/avatar.png')
///   Stream<List<int>> get(String userId);
///
///   @SignedUrl('{userId}/avatar.png', expiresIn: Duration(hours: 1))
///   Future<Uri> link(String userId);
///
///   @StorageObject('{userId}/settings.json')
///   Future<Settings?> settings(String userId);
/// }
/// ```
///
/// The paths of a bucket are in one place (the policies of row-level
/// security on `storage.objects` depend on their shape), and the bean
/// takes AOP like any other (`@PreAuthorize`, `@Cacheable`).
///
/// A path takes `${property}` from the configuration, `{name}` from the
/// method's parameter of that name, and SpEL in `#{...}` (the parameters
/// as `#name`, `authentication` and `principal` as in `@PreAuthorize`,
/// beans as `@name`). What a parameter or an expression gives is one
/// segment of the path: a value with a `/`, `.`, `..` or nothing in it is
/// refused, so a call never leaves its folder.
///
/// For what is not known when the application is built (listings, moves,
/// buckets), use `StorageTemplate`.
@InterfaceProxy(primary: true)
class StorageBucket {
  /// Marks the interface of the bucket [bucket] (`${...}` allowed).
  const StorageBucket(
    this.bucket, {
    this.qualifiers = const [],
    this.primary = true,
  });

  /// The bucket's id.
  final String bucket;

  /// More names the bean can be injected by.
  final List<String> qualifiers;

  /// Whether the bean is the primary one of its type.
  final bool primary;
}

/// Writes the object at [path]: the method takes the content (a
/// `Uint8List`, a `List<int>`, a `Stream<List<int>>`, or the parameter
/// marked `@RequestBody()`) and returns `Future<void>`.
@BeanMethodAnnotation()
class Upload {
  /// An upload to [path].
  const Upload(
    this.path, {
    this.contentType,
    this.upsert = false,
    this.cacheControl,
  });

  /// The object's path in the bucket (see [StorageBucket]).
  final String path;

  /// The content type; `application/octet-stream` unless given.
  final String? contentType;

  /// Whether an object already there is replaced.
  final bool upsert;

  /// How long browsers and the CDN may keep the object.
  final Duration? cacheControl;
}

/// Reads the object at [path]: the method returns `Stream<List<int>>`
/// (the bytes as they arrive) or `Future<Uint8List>`; a nullable
/// `Future<Uint8List?>` is `null` when there is no such object.
@BeanMethodAnnotation()
class Download {
  /// A download of [path].
  const Download(this.path);

  /// The object's path in the bucket (see [StorageBucket]).
  final String path;
}

/// Gives an address that reads the object at [path] without a token for
/// a while: the method returns `Future<Uri>` or `Future<String>`.
@BeanMethodAnnotation()
class SignedUrl {
  /// A signed URL of [path].
  const SignedUrl(this.path, {this.expiresIn});

  /// The object's path in the bucket (see [StorageBucket]).
  final String path;

  /// How long the address works;
  /// `spring.supabase.storage.signed-url-expiry` unless given.
  final Duration? expiresIn;
}

/// Gives the address of the object at [path] of a public bucket, without
/// asking Storage: the method returns `Uri` or `String`.
@BeanMethodAnnotation()
class PublicUrl {
  /// The public URL of [path].
  const PublicUrl(this.path, {this.download = false});

  /// The object's path in the bucket (see [StorageBucket]).
  final String path;

  /// Whether a browser saves the object instead of showing it.
  final bool download;
}

/// Reads or writes the object at [path] as JSON.
///
/// A method that returns a value (`Future<Settings?>`, `Future<Settings>`)
/// reads it (`null`, or for a non-nullable type an error, when there is
/// no such object). A method that returns `Future<void>` and takes a
/// value (its only parameter that is not in the path, or the one marked
/// `@RequestBody()`) writes it, replacing what is there unless [upsert]
/// is false.
@BeanMethodAnnotation()
class StorageObject {
  /// The JSON object at [path].
  const StorageObject(this.path, {this.upsert = true});

  /// The object's path in the bucket (see [StorageBucket]).
  final String path;

  /// Whether a write replaces an object already there.
  final bool upsert;
}

/// Removes the object at [path]: the method returns `Future<void>`.
/// Nothing there is no error.
@BeanMethodAnnotation()
class DeleteObject {
  /// A removal of [path].
  const DeleteObject(this.path);

  /// The object's path in the bucket (see [StorageBucket]).
  final String path;
}

/// What one kind of method of a [StorageBucket] interface does: an
/// application adds a kind of its own by declaring a bean of this type
/// (they are asked in `@Order`, before the built-in ones).
abstract interface class StorageBucketOperation {
  /// What a call of [method] does, or `null` when the method is not of
  /// this kind. Problems of a method of this kind go to
  /// [StorageBucketMethod.problem].
  FutureOr<Object?> Function(List<Object?> arguments)? plan(
    StorageBucketMethod method,
  );
}

/// A method of a [StorageBucket] interface, as a [StorageBucketOperation]
/// sees it.
final class StorageBucketMethod {
  StorageBucketMethod._(
    this.typeName,
    this.bucket,
    this.method,
    this.storage,
    this._templates,
    this._problems,
  );

  /// The interface's name.
  final String typeName;

  /// The bucket's id.
  final String bucket;

  /// The method.
  final ProxyMethod method;

  /// Storage.
  final StorageTemplate storage;

  final CallTemplates _templates;
  final List<String> _problems;

  /// Records what is wrong with the method; the application then fails
  /// to start, naming every problem of the interface.
  void problem(String text) => _problems.add('$typeName.${method.name}: $text');

  /// Reads the path [text] of an annotation of the method; `null` (and a
  /// [problem]) when it cannot be read.
  CallTemplate? path(String text) {
    try {
      return _templates.parse(
        text,
        method: method,
        encoder: const PathSegmentEncoder(encode: false),
      );
    } on ArgumentError catch (error) {
      problem('${error.message}');
      return null;
    }
  }

  /// The parameter that carries the content of a write: the one marked
  /// `@RequestBody()`, else the only parameter [path] does not use as
  /// `{name}`. `null` (and a [problem]) when there is not exactly one.
  int? content(CallTemplate path) {
    final marked = [
      for (final (index, parameter) in method.parameters.indexed)
        if (parameter.annotations.whereType<RequestBody>().isNotEmpty) index,
    ];
    if (marked.length == 1) {
      return marked.single;
    }
    final used = path.parameters.toSet();
    final free = [
      for (final (index, parameter) in method.parameters.indexed)
        if (!used.contains(parameter.name)) index,
    ];
    if (marked.isEmpty && free.length == 1) {
      return free.single;
    }
    problem(
      'needs one parameter for the content: mark it @RequestBody() '
      '(the parameters used as {name} in the path are not it)',
    );
    return null;
  }

  /// Whether the method returns `Future<void>`.
  bool get returnsFutureOfVoid => method.isFuture && method.isVoid;
}

/// Makes the beans of the [StorageBucket] interfaces (the bean
/// `storageBucketFactory`).
final class StorageBucketFactory implements InvocationHandlerFactory {
  /// A factory over [storage]; [operations] are the application's own
  /// kinds of methods, asked before the built-in ones.
  StorageBucketFactory({
    required this.storage,
    required this.templates,
    required this.environment,
    List<StorageBucketOperation> operations = const [],
  }) : operations = List.unmodifiable([...operations, ..._builtIn]);

  /// Storage.
  final StorageTemplate storage;

  /// What reads the paths.
  final CallTemplates templates;

  /// Where `${...}` of the bucket's id is resolved.
  final Environment environment;

  /// The kinds of methods, in the order they are asked.
  final List<StorageBucketOperation> operations;

  static const List<StorageBucketOperation> _builtIn = [
    _UploadOperation(),
    _DownloadOperation(),
    _SignedUrlOperation(),
    _PublicUrlOperation(),
    _JsonOperation(),
    _DeleteOperation(),
  ];

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<StorageBucket>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final annotation = metadata.annotation<StorageBucket>()!;
    final problems = <String>[];
    var bucket = '';
    try {
      bucket = environment.resolveRequiredPlaceholders(annotation.bucket);
    } on Object catch (error) {
      problems.add('@StorageBucket("${annotation.bucket}"): $error');
    }
    final plans = <String, FutureOr<Object?> Function(List<Object?>)>{};
    for (final method in metadata.methods) {
      final described = StorageBucketMethod._(
        metadata.typeName,
        bucket,
        method,
        storage,
        templates,
        problems,
      );
      final before = problems.length;
      final plan = operations
          .map((operation) => operation.plan(described))
          .firstWhere((plan) => plan != null, orElse: () => null);
      if (plan != null) {
        plans[method.name] = plan;
      } else if (problems.length == before) {
        described.problem(
          'needs @Upload, @Download, @SignedUrl, @PublicUrl, '
          '@StorageObject or @DeleteObject',
        );
      }
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid @StorageBucket interface ${metadata.typeName}:\n'
        '${problems.map((problem) => '  - $problem').join('\n')}',
      );
    }
    return _StorageBucketHandler(plans);
  }
}

final class _StorageBucketHandler implements InvocationHandler {
  _StorageBucketHandler(this.plans);

  final Map<String, FutureOr<Object?> Function(List<Object?>)> plans;

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) {
    final plan = plans[method.name]!;
    if (!method.isFuture) {
      return plan(arguments);
    }
    // A refused path fails the returned future, like any other failure of
    // the call.
    return Future<Object?>.sync(() => plan(arguments));
  }
}

bool _isBytes(TypeInfo<Object?> type) =>
    type.type == Uint8List ||
    switch (type) {
      ListType(:final element) => element.type == int,
      _ => false,
    };

bool _isByteStream(TypeInfo<Object?> type) =>
    type is GenericType<Object?> &&
    type.isSubtypeOf<Stream<Object?>>() &&
    type.arguments.length == 1 &&
    _isBytes(type.arguments.single);

final class _UploadOperation implements StorageBucketOperation {
  const _UploadOperation();

  @override
  FutureOr<Object?> Function(List<Object?>)? plan(StorageBucketMethod method) {
    final upload = method.method.annotation<Upload>();
    if (upload == null) {
      return null;
    }
    final path = method.path(upload.path);
    if (!method.returnsFutureOfVoid) {
      method.problem('an @Upload method returns Future<void>');
    }
    if (path == null) {
      return null;
    }
    final content = method.content(path);
    if (content == null) {
      return null;
    }
    final type = method.method.parameters[content].type;
    if (!_isBytes(type) && !_isByteStream(type) && type.type != String) {
      method.problem(
        'the content of an @Upload is a Uint8List, a List<int>, a '
        'Stream<List<int>> or a String',
      );
      return null;
    }
    return (arguments) => method.storage.upload(
      method.bucket,
      path.expand(method.method, arguments),
      arguments[content] ??
          (throw ArgumentError('${method.method.name}: the content is null')),
      contentType: upload.contentType,
      upsert: upload.upsert,
      cacheControl: upload.cacheControl,
    );
  }
}

final class _DownloadOperation implements StorageBucketOperation {
  const _DownloadOperation();

  @override
  FutureOr<Object?> Function(List<Object?>)? plan(StorageBucketMethod method) {
    final download = method.method.annotation<Download>();
    if (download == null) {
      return null;
    }
    final path = method.path(download.path);
    final type = method.method.returnType;
    final stream = !method.method.isFuture && _isByteStream(type);
    final bytes = method.method.isFuture && type.type == Uint8List;
    if (!stream && !bytes) {
      method.problem(
        'a @Download method returns Stream<List<int>> or '
        'Future<Uint8List>',
      );
      return null;
    }
    if (path == null) {
      return null;
    }
    String place(List<Object?> arguments) =>
        path.expand(method.method, arguments);
    if (stream) {
      return (arguments) =>
          method.storage.download(method.bucket, place(arguments));
    }
    if (!type.nullable) {
      return (arguments) =>
          method.storage.downloadBytes(method.bucket, place(arguments));
    }
    return (arguments) async {
      try {
        return await method.storage.downloadBytes(
          method.bucket,
          place(arguments),
        );
      } on StorageObjectNotFoundException {
        return null;
      }
    };
  }
}

final class _SignedUrlOperation implements StorageBucketOperation {
  const _SignedUrlOperation();

  @override
  FutureOr<Object?> Function(List<Object?>)? plan(StorageBucketMethod method) {
    final signed = method.method.annotation<SignedUrl>();
    if (signed == null) {
      return null;
    }
    final path = method.path(signed.path);
    final type = method.method.returnType.type;
    if (!method.method.isFuture || (type != Uri && type != String)) {
      method.problem(
        'a @SignedUrl method returns Future<Uri> or '
        'Future<String>',
      );
      return null;
    }
    if (path == null) {
      return null;
    }
    return (arguments) async {
      final url = await method.storage.signedUrl(
        method.bucket,
        path.expand(method.method, arguments),
        expiresIn: signed.expiresIn,
      );
      return type == String ? '$url' : url;
    };
  }
}

final class _PublicUrlOperation implements StorageBucketOperation {
  const _PublicUrlOperation();

  @override
  FutureOr<Object?> Function(List<Object?>)? plan(StorageBucketMethod method) {
    final public = method.method.annotation<PublicUrl>();
    if (public == null) {
      return null;
    }
    final path = method.path(public.path);
    final type = method.method.returnType.type;
    if (method.method.isFuture || (type != Uri && type != String)) {
      method.problem('a @PublicUrl method returns Uri or String');
      return null;
    }
    if (path == null) {
      return null;
    }
    return (arguments) {
      final url = method.storage.publicUrl(
        method.bucket,
        path.expand(method.method, arguments),
        download: public.download,
      );
      return type == String ? '$url' : url;
    };
  }
}

final class _JsonOperation implements StorageBucketOperation {
  const _JsonOperation();

  @override
  FutureOr<Object?> Function(List<Object?>)? plan(StorageBucketMethod method) {
    final object = method.method.annotation<StorageObject>();
    if (object == null) {
      return null;
    }
    final path = method.path(object.path);
    if (!method.method.isFuture) {
      method.problem('a @StorageObject method returns a Future');
      return null;
    }
    if (path == null) {
      return null;
    }
    String place(List<Object?> arguments) =>
        path.expand(method.method, arguments);
    if (method.method.isVoid) {
      final content = method.content(path);
      if (content == null) {
        return null;
      }
      return (arguments) => method.storage.store(
        method.bucket,
        place(arguments),
        arguments[content],
        upsert: object.upsert,
      );
    }
    final type = method.method.returnType;
    return (arguments) async {
      final value = await method.storage.read<Object?>(
        method.bucket,
        place(arguments),
        type,
      );
      if (value == null && !type.nullable) {
        throw StorageObjectNotFoundException(
          '${method.bucket}/${place(arguments)}: no such object',
        );
      }
      return value;
    };
  }
}

final class _DeleteOperation implements StorageBucketOperation {
  const _DeleteOperation();

  @override
  FutureOr<Object?> Function(List<Object?>)? plan(StorageBucketMethod method) {
    final delete = method.method.annotation<DeleteObject>();
    if (delete == null) {
      return null;
    }
    final path = method.path(delete.path);
    if (!method.returnsFutureOfVoid) {
      method.problem('a @DeleteObject method returns Future<void>');
    }
    if (path == null) {
      return null;
    }
    return (arguments) => method.storage.delete(
      method.bucket,
      path.expand(method.method, arguments),
    );
  }
}
