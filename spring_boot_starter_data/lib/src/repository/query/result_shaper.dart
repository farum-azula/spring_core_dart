import 'package:spring_boot_starter_data/src/repository/page.dart';

/// Creates the collections of a `@Query` method's result with the real type
/// argument: a `Future<List<BookCard>>` method must get a `List<BookCard>`,
/// not a `List<Object>`.
///
/// Built through `TypeInfo.capture` from the element type of the method,
/// which is the only way to name a type that is known at run time (the
/// derived queries and the CRUD methods know theirs: `RepositoryOperations`
/// is generic in the entity).
///
/// Spring (Java): none; Java's erased generics need nothing of the sort.
abstract interface class ResultShaper {
  /// A `List<E>` of [items].
  Object list(Iterable<Object?> items);

  /// A `Set<E>` of [items].
  Object set(Iterable<Object?> items);

  /// [items] as a `Stream<E>`, lazily.
  Object streamOf(Stream<Object?> items);

  /// A `Page<E>` with [content] of the window [pageable] among [total]
  /// elements.
  Object page(List<Object?> content, Pageable pageable, int total);

  /// A `Slice<E>` with [content] of the window [pageable]; [hasNext] says
  /// whether there are more elements after it.
  Object slice(List<Object?> content, Pageable pageable, bool hasNext);
}

/// The [ResultShaper] of element type [E].
final class TypedResultShaper<E> implements ResultShaper {
  /// A shaper of [E].
  const TypedResultShaper();

  @override
  Object list(Iterable<Object?> items) => <E>[
    for (final item in items) item as E,
  ];

  @override
  Object set(Iterable<Object?> items) => <E>{
    for (final item in items) item as E,
  };

  @override
  Object streamOf(Stream<Object?> items) => items.map((item) => item as E);

  @override
  Object page(List<Object?> content, Pageable pageable, int total) =>
      PageImpl<E>(<E>[for (final item in content) item as E], pageable, total);

  @override
  Object slice(List<Object?> content, Pageable pageable, bool hasNext) =>
      SliceImpl<E>(
        <E>[for (final item in content) item as E],
        pageable,
        hasNext,
      );
}
