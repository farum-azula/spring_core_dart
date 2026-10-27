// Clients with multipart bodies (`@RequestPart`), with the code the
// generator writes for them.
import 'dart:typed_data';

import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

import 'catalog.dart';

enum Shelf { fiction, science }

@FeignClient('uploads', url: 'http://uploads.test')
abstract interface class UploadClient {
  @PostMapping.of(
    path: '/books/{isbn}/files',
    consumes: MediaType.multipartFormData,
  )
  Future<String> upload(
    @PathVariable() String isbn,
    @RequestPart('file') MultipartFile file,
    @RequestPart('meta') Book meta,
    @RequestPart('note') String note,
    @RequestParam('draft') bool draft,
  );

  // No consumes: the @RequestPart parameters make it multipart.
  @PostMapping('/kinds')
  Future<String> kinds(
    @RequestPart('files') List<MultipartFile> files,
    @RequestPart('raw') Uint8List raw,
    @RequestPart('ints') List<int> ints,
    @RequestPart('count') int count,
    @RequestPart('shelf') Shelf shelf,
    @RequestPart('at') DateTime at,
    @RequestPart('tags') List<String> tags,
    @RequestPart('labels') Map<String, Object?> labels,
    @RequestPart('books') List<Book> books,
  );

  @PostMapping('/optional')
  Future<String> optional(
    @RequestPart('file') MultipartFile file, {
    @RequestPart('note') String? note,
    @RequestPart('cover') MultipartFile? cover,
  });
}

@FeignClient('badUploads', url: 'http://bad.test')
abstract interface class BadUploadClient {
  @PostMapping('/both')
  Future<String> both(
    @RequestPart('file') MultipartFile file,
    @RequestBody() Book book,
  );

  @PostMapping.of(path: '/json', consumes: MediaType.applicationJson)
  Future<String> json(@RequestPart('file') MultipartFile file);

  @PostMapping('/roles')
  Future<String> roles(@RequestPart('a') @RequestParam('a') String a);
}

// ---- generated ----

class UploadClientImpl implements UploadClient {
  UploadClientImpl(this._handler, this._metadata);

  static UploadClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<UploadClient>(
      typeName: 'UploadClient',
      annotations: const [FeignClient('uploads', url: 'http://uploads.test')],
      methods: [
        ProxyMethod(
          'upload',
          parameters: const [
            BeanParameter(
              'isbn',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
            BeanParameter(
              'file',
              type: ClassType<MultipartFile>(),
              isRequired: true,
              annotations: [RequestPart('file')],
            ),
            BeanParameter(
              'meta',
              type: ClassType<Book>(),
              isRequired: true,
              annotations: [RequestPart('meta')],
            ),
            BeanParameter(
              'note',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestPart('note')],
            ),
            BeanParameter(
              'draft',
              type: ClassType<bool>(),
              isRequired: true,
              annotations: [RequestParam('draft')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            PostMapping.of(
              path: '/books/{isbn}/files',
              consumes: MediaType.multipartFormData,
            ),
          ],
          call: (target, arguments) => (target as UploadClient).upload(
            arguments[0]! as String,
            arguments[1]! as MultipartFile,
            arguments[2]! as Book,
            arguments[3]! as String,
            arguments[4]! as bool,
          ),
        ),
        ProxyMethod(
          'kinds',
          parameters: const [
            BeanParameter(
              'files',
              type: ListType<MultipartFile>(ClassType<MultipartFile>()),
              isRequired: true,
              annotations: [RequestPart('files')],
            ),
            BeanParameter(
              'raw',
              type: ClassType<Uint8List>(),
              isRequired: true,
              annotations: [RequestPart('raw')],
            ),
            BeanParameter(
              'ints',
              type: ListType<int>(ClassType<int>()),
              isRequired: true,
              annotations: [RequestPart('ints')],
            ),
            BeanParameter(
              'count',
              type: ClassType<int>(),
              isRequired: true,
              annotations: [RequestPart('count')],
            ),
            BeanParameter(
              'shelf',
              type: EnumType<Shelf>(Shelf.values),
              isRequired: true,
              annotations: [RequestPart('shelf')],
            ),
            BeanParameter(
              'at',
              type: ClassType<DateTime>(),
              isRequired: true,
              annotations: [RequestPart('at')],
            ),
            BeanParameter(
              'tags',
              type: ListType<String>(ClassType<String>()),
              isRequired: true,
              annotations: [RequestPart('tags')],
            ),
            BeanParameter(
              'labels',
              type: MapType<String, Object?>(
                ClassType<String>(),
                DynamicType(),
              ),
              isRequired: true,
              annotations: [RequestPart('labels')],
            ),
            BeanParameter(
              'books',
              type: ListType<Book>(ClassType<Book>()),
              isRequired: true,
              annotations: [RequestPart('books')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [PostMapping('/kinds')],
          call: (target, arguments) => (target as UploadClient).kinds(
            arguments[0]! as List<MultipartFile>,
            arguments[1]! as Uint8List,
            arguments[2]! as List<int>,
            arguments[3]! as int,
            arguments[4]! as Shelf,
            arguments[5]! as DateTime,
            arguments[6]! as List<String>,
            arguments[7]! as Map<String, Object?>,
            arguments[8]! as List<Book>,
          ),
        ),
        ProxyMethod(
          'optional',
          parameters: const [
            BeanParameter(
              'file',
              type: ClassType<MultipartFile>(),
              isRequired: true,
              annotations: [RequestPart('file')],
            ),
            BeanParameter(
              'note',
              type: ClassType<String>(nullable: true),
              symbol: #note,
              annotations: [RequestPart('note')],
            ),
            BeanParameter(
              'cover',
              type: ClassType<MultipartFile>(nullable: true),
              symbol: #cover,
              annotations: [RequestPart('cover')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [PostMapping('/optional')],
          call: (target, arguments) => (target as UploadClient).optional(
            arguments[0]! as MultipartFile,
            note: arguments[1] as String?,
            cover: arguments[2] as MultipartFile?,
          ),
        ),
      ],
    );
    return UploadClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<UploadClient> _metadata;

  @override
  Future<String> upload(
    String isbn,
    MultipartFile file,
    Book meta,
    String note,
    bool draft,
  ) => retypeFuture<String>(
    _handler.invoke(_metadata.methods[0], [isbn, file, meta, note, draft]),
  );

  @override
  Future<String> kinds(
    List<MultipartFile> files,
    Uint8List raw,
    List<int> ints,
    int count,
    Shelf shelf,
    DateTime at,
    List<String> tags,
    Map<String, Object?> labels,
    List<Book> books,
  ) => retypeFuture<String>(
    _handler.invoke(_metadata.methods[1], [
      files,
      raw,
      ints,
      count,
      shelf,
      at,
      tags,
      labels,
      books,
    ]),
  );

  // The parameters accept null, which the type system keeps from the
  // generated code, so a test can reach the checks of the handler.
  @override
  Future<String> optional(
    MultipartFile? file, {
    String? note,
    MultipartFile? cover,
  }) => retypeFuture<String>(
    _handler.invoke(_metadata.methods[2], [file, note, cover]),
  );
}

class BadUploadClientImpl implements BadUploadClient {
  BadUploadClientImpl(this._handler, this._metadata);

  static BadUploadClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<BadUploadClient>(
      typeName: 'BadUploadClient',
      annotations: const [FeignClient('badUploads', url: 'http://bad.test')],
      methods: [
        ProxyMethod(
          'both',
          parameters: const [
            BeanParameter(
              'file',
              type: ClassType<MultipartFile>(),
              isRequired: true,
              annotations: [RequestPart('file')],
            ),
            BeanParameter(
              'book',
              type: ClassType<Book>(),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [PostMapping('/both')],
          call: (target, arguments) => (target as BadUploadClient).both(
            arguments[0]! as MultipartFile,
            arguments[1]! as Book,
          ),
        ),
        ProxyMethod(
          'json',
          parameters: const [
            BeanParameter(
              'file',
              type: ClassType<MultipartFile>(),
              isRequired: true,
              annotations: [RequestPart('file')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            PostMapping.of(path: '/json', consumes: MediaType.applicationJson),
          ],
          call: (target, arguments) =>
              (target as BadUploadClient).json(arguments[0]! as MultipartFile),
        ),
        ProxyMethod(
          'roles',
          parameters: const [
            BeanParameter(
              'a',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestPart('a'), RequestParam('a')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [PostMapping('/roles')],
          call: (target, arguments) =>
              (target as BadUploadClient).roles(arguments[0]! as String),
        ),
      ],
    );
    return BadUploadClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<BadUploadClient> _metadata;

  @override
  Future<String> both(MultipartFile file, Book book) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], [file, book]));

  @override
  Future<String> json(MultipartFile file) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], [file]));

  @override
  Future<String> roles(String a) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[2], [a]));
}

/// The module with [UploadClient] (and the introspection of [Book]).
final uploadsModule = BeanModule(
  'uploads',
  [
    BeanDefinition<UploadClient>(
      name: 'uploadClient',
      primary: true,
      create: UploadClientImpl.$create,
    ),
  ],
  introspections: [bookIntrospection],
);

/// The module with [BadUploadClient], which fails at startup.
final badUploadsModule = BeanModule(
  'badUploads',
  [
    BeanDefinition<BadUploadClient>(
      name: 'badUploadClient',
      primary: true,
      create: BadUploadClientImpl.$create,
    ),
  ],
  introspections: [bookIntrospection],
);
