import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// A request for one page of results: which page, how large, in what order.
///
/// A repository method taking a `Pageable` returns a [Page] (which counts
/// the whole result) or a [Slice] (which only knows whether one more page
/// follows). Build one with [PageRequest.of]; [Pageable.unpaged] asks for
/// everything in one go.
///
/// Spring (Java): `org.springframework.data.domain.Pageable`.
abstract interface class Pageable {
  /// A request for everything, unordered (or ordered by [sort]); the
  /// repository returns one page holding the whole result.
  const factory Pageable.unpaged([Sort sort]) = _Unpaged;

  /// Whether this request asks for a page (`true`) or everything
  /// ([Pageable.unpaged], `false`).
  bool get isPaged;

  /// Whether this request asks for everything ([Pageable.unpaged]).
  bool get isUnpaged;

  /// The zero-based page number.
  int get pageNumber;

  /// The number of items per page.
  int get pageSize;

  /// The number of items to skip before this page: `pageNumber * pageSize`.
  int get offset;

  /// The ordering of the items.
  Sort get sort;

  /// The request for the next page.
  Pageable next();

  /// The request for the previous page, or the first if already on it.
  Pageable previousOrFirst();

  /// The request for the first page.
  Pageable first();

  /// A request for the page at [pageNumber], same size and order.
  Pageable withPage(int pageNumber);

  /// Whether a previous page exists (the page number is above zero).
  bool get hasPrevious;
}

/// The usual [Pageable]: a page number, a size and a [Sort].
///
/// Spring (Java): `org.springframework.data.domain.PageRequest`.
final class PageRequest implements Pageable {
  const PageRequest._(this.pageNumber, this.pageSize, this.sort);

  /// A request for page [page] (zero-based) of [size] items, ordered by
  /// [sort]. Throws an [ArgumentError] for a negative page or a size below
  /// one, as Spring does.
  factory PageRequest.of(int page, int size, [Sort sort = Sort.unsorted]) {
    if (page < 0) {
      throw ArgumentError.value(page, 'page', 'must not be negative');
    }
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be greater than zero');
    }
    return PageRequest._(page, size, sort);
  }

  @override
  final int pageNumber;

  @override
  final int pageSize;

  @override
  final Sort sort;

  @override
  bool get isPaged => true;

  @override
  bool get isUnpaged => false;

  @override
  int get offset => pageNumber * pageSize;

  @override
  bool get hasPrevious => pageNumber > 0;

  @override
  Pageable next() => PageRequest._(pageNumber + 1, pageSize, sort);

  @override
  Pageable previousOrFirst() =>
      hasPrevious ? PageRequest._(pageNumber - 1, pageSize, sort) : this;

  @override
  Pageable first() => PageRequest._(0, pageSize, sort);

  @override
  Pageable withPage(int pageNumber) =>
      PageRequest.of(pageNumber, pageSize, sort);

  @override
  bool operator ==(Object other) =>
      other is PageRequest &&
      other.pageNumber == pageNumber &&
      other.pageSize == pageSize &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(pageNumber, pageSize, sort);

  @override
  String toString() =>
      'Page request [number: $pageNumber, size: $pageSize, sort: $sort]';
}

final class _Unpaged implements Pageable {
  const _Unpaged([this.sort = Sort.unsorted]);

  @override
  final Sort sort;

  @override
  bool get isPaged => false;

  @override
  bool get isUnpaged => true;

  @override
  bool get hasPrevious => false;

  // Spring's Unpaged throws on these; a caller that treats a request as a
  // page must first check isPaged.
  @override
  int get pageNumber => throw UnsupportedError('unpaged request has no page');

  @override
  int get pageSize => throw UnsupportedError('unpaged request has no size');

  @override
  int get offset => throw UnsupportedError('unpaged request has no offset');

  @override
  Pageable next() => this;

  @override
  Pageable previousOrFirst() => this;

  @override
  Pageable first() => this;

  @override
  Pageable withPage(int pageNumber) => pageNumber == 0
      ? this
      : throw UnsupportedError('unpaged request has no page');

  @override
  bool operator ==(Object other) => other is _Unpaged && other.sort == sort;

  @override
  int get hashCode => sort.hashCode;

  @override
  String toString() => 'Unpaged';
}

/// A part of a larger result that knows whether another part follows, but
/// not how large the whole is (no `count` query is run).
///
/// Return a `Slice` instead of a [Page] when the total is not needed: an
/// infinite scroll only asks "is there more?". A `Page` is a `Slice` that
/// also carries the total.
///
/// Spring (Java): `org.springframework.data.domain.Slice`.
abstract interface class Slice<T> {
  /// The items on this slice.
  List<T> get content;

  /// Whether this slice has any items.
  bool get hasContent;

  /// The number of items on this slice.
  int get numberOfElements;

  /// The zero-based number of this slice.
  int get number;

  /// The size asked for ([Pageable.pageSize]).
  int get size;

  /// The ordering of the items.
  Sort get sort;

  /// Whether this is the first slice.
  bool get isFirst;

  /// Whether this is the last slice (no next one).
  bool get isLast;

  /// Whether a next slice follows.
  bool get hasNext;

  /// Whether a previous slice exists.
  bool get hasPrevious;

  /// The request for the next slice, or an unpaged request past the last.
  Pageable nextPageable();

  /// The request for the previous slice, or the first.
  Pageable previousPageable();

  /// A slice with each item mapped by [transform], the paging kept.
  Slice<R> map<R>(R Function(T) transform);
}

/// A [Slice] that also knows the total number of items and pages, from a
/// `count` query.
///
/// Spring (Java): `org.springframework.data.domain.Page`.
abstract interface class Page<T> implements Slice<T> {
  /// An empty page for request [pageable] (or an unpaged empty page).
  factory Page.empty([Pageable? pageable]) =>
      PageImpl<T>(const [], pageable ?? const Pageable.unpaged(), 0);

  /// The total number of pages.
  int get totalPages;

  /// The total number of items across all pages.
  int get totalElements;

  @override
  Page<R> map<R>(R Function(T) transform);
}

/// The usual [Slice]: a list of items and the request that produced it,
/// plus whether another slice follows.
///
/// Spring (Java): `org.springframework.data.domain.SliceImpl`.
class SliceImpl<T> implements Slice<T> {
  /// A slice holding [content] for [pageable], with [hasNext] telling
  /// whether one more slice follows.
  SliceImpl(List<T> content, this.pageable, this._hasNext)
    : content = List.unmodifiable(content);

  @override
  final List<T> content;

  /// The request that produced this slice.
  final Pageable pageable;

  final bool _hasNext;

  @override
  bool get hasContent => content.isNotEmpty;

  @override
  int get numberOfElements => content.length;

  @override
  int get number => pageable.isPaged ? pageable.pageNumber : 0;

  @override
  int get size => pageable.isPaged ? pageable.pageSize : content.length;

  @override
  Sort get sort => pageable.sort;

  @override
  bool get isFirst => !hasPrevious;

  @override
  bool get isLast => !hasNext;

  @override
  bool get hasNext => _hasNext;

  @override
  bool get hasPrevious => number > 0;

  @override
  Pageable nextPageable() =>
      hasNext ? pageable.next() : const Pageable.unpaged();

  @override
  Pageable previousPageable() =>
      hasPrevious ? pageable.previousOrFirst() : const Pageable.unpaged();

  @override
  Slice<R> map<R>(R Function(T) transform) =>
      SliceImpl<R>([for (final e in content) transform(e)], pageable, _hasNext);

  @override
  String toString() => 'Slice $number containing $numberOfElements item(s)';
}

/// The usual [Page]: a list of items, the request that produced it, and the
/// total count.
///
/// Spring (Java): `org.springframework.data.domain.PageImpl`.
class PageImpl<T> implements Page<T> {
  /// A page holding [content] for [pageable], out of [totalElements] items
  /// in all.
  PageImpl(List<T> content, this.pageable, this.totalElements)
    : content = List.unmodifiable(content);

  @override
  final List<T> content;

  /// The request that produced this page.
  final Pageable pageable;

  @override
  final int totalElements;

  @override
  bool get hasContent => content.isNotEmpty;

  @override
  int get numberOfElements => content.length;

  @override
  int get number => pageable.isPaged ? pageable.pageNumber : 0;

  @override
  int get size => pageable.isPaged ? pageable.pageSize : content.length;

  @override
  Sort get sort => pageable.sort;

  @override
  int get totalPages => size == 0 ? 1 : (totalElements / size).ceil();

  @override
  bool get isFirst => !hasPrevious;

  @override
  bool get isLast => !hasNext;

  @override
  bool get hasNext => number + 1 < totalPages;

  @override
  bool get hasPrevious => number > 0;

  @override
  Pageable nextPageable() =>
      hasNext ? pageable.next() : const Pageable.unpaged();

  @override
  Pageable previousPageable() =>
      hasPrevious ? pageable.previousOrFirst() : const Pageable.unpaged();

  @override
  Page<R> map<R>(R Function(T) transform) => PageImpl<R>(
    [for (final e in content) transform(e)],
    pageable,
    totalElements,
  );

  @override
  String toString() =>
      'Page $number of $totalPages containing $numberOfElements item(s)';
}
