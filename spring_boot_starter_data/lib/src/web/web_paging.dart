import 'package:spring_boot_dart/spring_boot_dart.dart' show Environment;
import 'package:spring_boot_starter_data/src/properties/data_properties.dart';
import 'package:spring_boot_starter_data/src/properties_binding.dart';
import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// The page a controller's `Pageable` parameter gets when the request does
/// not ask for one: [size] items per page (10, as Spring's), from [page],
/// ordered by [sort] in [direction].
///
/// Mark the `Pageable` parameter of a controller method. The web glue the
/// build writes into an application that depends on both
/// `spring_boot_starter_web` and this starter reads it (see [WebPaging]).
///
/// ```dart
/// @GetMapping('/books')
/// Future<Page<Book>> list(
///   @PageableDefault(size: 5, sort: ['title']) Pageable pageable,
/// ) => books.findAll(pageable);
/// ```
///
/// Spring (Java): `org.springframework.data.web.PageableDefault`; its
/// `value` and `size` are one parameter, [size], here.
class PageableDefault {
  /// A default of [size] items per page, from page [page] (zero-based),
  /// ordered by [sort] in [direction].
  const PageableDefault({
    this.size = 10,
    this.page = 0,
    this.sort = const [],
    this.direction = Direction.asc,
  });

  /// The number of items per page.
  final int size;

  /// The zero-based page number.
  final int page;

  /// The properties to order by; none leaves the order to the store.
  final List<String> sort;

  /// The direction of every property of [sort].
  final Direction direction;
}

/// The order a controller's `Sort` (or `Pageable`) parameter gets when the
/// request has no `sort` parameter: [sort] in [direction]. Written more than
/// once on a parameter, each adds its properties after the previous ones.
///
/// ```dart
/// @GetMapping('/books')
/// Future<List<Book>> list(
///   @SortDefault(sort: ['year'], direction: Direction.desc) Sort sort,
/// ) => books.findAll(sort);
/// ```
///
/// Spring (Java): `org.springframework.data.web.SortDefault` (and
/// `SortDefault.SortDefaults`, which Dart does not need: an annotation may
/// be repeated).
class SortDefault {
  /// A default order of the properties [sort] in [direction].
  const SortDefault({this.sort = const [], this.direction = Direction.asc});

  /// The properties to order by.
  final List<String> sort;

  /// The direction of every property.
  final Direction direction;
}

/// The settings of [WebPaging], from the `spring.data.web.*` properties of
/// Spring Boot's `SpringDataWebProperties`.
///
/// | Property | Default |
/// |---|---|
/// | `spring.data.web.pageable.default-page-size` | 20 |
/// | `spring.data.web.pageable.max-page-size` | 2000 |
/// | `spring.data.web.pageable.one-indexed-parameters` | false |
/// | `spring.data.web.pageable.page-parameter` | `page` |
/// | `spring.data.web.pageable.size-parameter` | `size` |
/// | `spring.data.web.pageable.prefix` | empty |
/// | `spring.data.web.pageable.qualifier-delimiter` | `_` |
/// | `spring.data.web.sort.sort-parameter` | `sort` |
///
/// Spring (Java): `SpringDataWebProperties`.
final class WebPagingProperties {
  /// Settings with the given values (the defaults of Spring Boot unless
  /// said otherwise).
  const WebPagingProperties({
    this.defaultPageSize = 20,
    this.maxPageSize = 2000,
    this.oneIndexedParameters = false,
    this.pageParameter = 'page',
    this.sizeParameter = 'size',
    this.prefix = '',
    this.qualifierDelimiter = '_',
    this.sortParameter = 'sort',
  });

  /// The settings of [environment]; a malformed number or boolean throws.
  factory WebPagingProperties.of(Environment environment) {
    Never refuse(InvalidProperty failure) => throw ArgumentError.value(
      failure.value,
      failure.property,
      'must be ${failure.expected}',
    );
    final pageable = bindSettings<DataPageableProperties>(
      environment,
      'spring.data.web.pageable',
      fallback: const DataPageableProperties(),
      onInvalid: refuse,
    );
    final sort = bindSettings<DataSortProperties>(
      environment,
      'spring.data.web.sort',
      fallback: const DataSortProperties(),
      onInvalid: refuse,
    );
    const defaults = DataPageableProperties();
    // A blank name is as good as none; the prefix and the delimiter keep
    // their spaces and empty values as written.
    String name(String value, String fallback) =>
        value.trim().isEmpty ? fallback : value.trim();
    return WebPagingProperties(
      defaultPageSize: pageable.defaultPageSize,
      maxPageSize: pageable.maxPageSize,
      oneIndexedParameters: pageable.oneIndexedParameters,
      pageParameter: name(pageable.pageParameter, defaults.pageParameter),
      sizeParameter: name(pageable.sizeParameter, defaults.sizeParameter),
      prefix: pageable.prefix,
      qualifierDelimiter: pageable.qualifierDelimiter,
      sortParameter: name(
        sort.sortParameter,
        const DataSortProperties().sortParameter,
      ),
    );
  }

  /// The page size when the request and the parameter give none.
  final int defaultPageSize;

  /// The largest page size a request may ask for; a larger one is cut to it.
  final int maxPageSize;

  /// Whether the `page` parameter counts from 1 (the first page is `1`).
  final bool oneIndexedParameters;

  /// The name of the query parameter holding the page number.
  final String pageParameter;

  /// The name of the query parameter holding the page size.
  final String sizeParameter;

  /// What the names of the page and size parameters start with.
  final String prefix;

  /// What follows a `@Qualifier`'s value in the names of the parameters.
  final String qualifierDelimiter;

  /// The name of the query parameter holding the order.
  final String sortParameter;
}

/// Turns the query parameters of a request into the `Pageable` and `Sort`
/// of a controller parameter, as Spring Data's
/// `PageableHandlerMethodArgumentResolver` and
/// `SortHandlerMethodArgumentResolver` do.
///
/// `?page=2&size=10&sort=title,desc&sort=year` is page 2 (zero-based) of 10
/// items ordered by title descending, then year ascending. A property list
/// may share one direction (`sort=title,year,desc`) and end with
/// `ignorecase`. The rules are Spring's:
///
/// - a page number below zero is 0, a non-numeric one is 0, and an absent
///   one is the default's;
/// - a size below one, or non-numeric, is the default's; one above
///   [WebPagingProperties.maxPageSize] is cut to it;
/// - the default is the parameter's [PageableDefault], else page 0 of
///   [WebPagingProperties.defaultPageSize];
/// - an empty `sort=` is no sort; a request without an order gets the
///   parameter's [SortDefault]s, then the `PageableDefault`'s order;
/// - a parameter marked `@Qualifier('foo')` reads `foo_page`, `foo_size`
///   and `foo_sort`.
///
/// A sort property the entity does not have is not checked here: the
/// repository refuses it (`PropertyReferenceException`), which the web glue
/// answers with a 400.
///
/// The web starter's resolvers, written into the application by the
/// generator from this starter's template, call it: this starter does not
/// depend on the web starter.
///
/// Spring (Java): `PageableHandlerMethodArgumentResolver`,
/// `SortHandlerMethodArgumentResolver`.
final class WebPaging {
  /// Resolves with [properties].
  const WebPaging([this.properties = const WebPagingProperties()]);

  /// The settings.
  final WebPagingProperties properties;

  /// The `Pageable` the [query] parameters ask for, [pageableDefault] and
  /// [sortDefaults] being the annotations of the parameter and [qualifier]
  /// the value of its `@Qualifier`.
  Pageable pageable(
    Map<String, List<String>> query, {
    PageableDefault? pageableDefault,
    List<SortDefault> sortDefaults = const [],
    String? qualifier,
  }) {
    final fallbackSize = pageableDefault?.size ?? properties.defaultPageSize;
    final fallbackPage = pageableDefault?.page ?? 0;
    final fallbackSort = pageableDefault == null
        ? Sort.unsorted
        : _sortOf(pageableDefault.sort, pageableDefault.direction);
    final page = _number(
      _first(query, _name(properties.pageParameter, qualifier, true)),
      0x7fffffff,
      shift: properties.oneIndexedParameters,
    );
    final size = _number(
      _first(query, _name(properties.sizeParameter, qualifier, true)),
      properties.maxPageSize,
    );
    var pageSize = size ?? fallbackSize;
    // Spring: a size below one is the default's, then the upper bound.
    if (pageSize < 1) {
      pageSize = fallbackSize;
    }
    if (pageSize > properties.maxPageSize) {
      pageSize = properties.maxPageSize;
    }
    final requested = sort(
      query,
      sortDefaults: sortDefaults,
      qualifier: qualifier,
    );
    return PageRequest.of(
      page ?? fallbackPage,
      pageSize,
      requested.isSorted ? requested : fallbackSort,
    );
  }

  /// The `Sort` the [query] parameters ask for, [sortDefaults] being the
  /// parameter's annotations and [qualifier] the value of its
  /// `@Qualifier`; the defaults, or unsorted, when the request has none.
  Sort sort(
    Map<String, List<String>> query, {
    List<SortDefault> sortDefaults = const [],
    String? qualifier,
  }) {
    final values = query[_name(properties.sortParameter, qualifier, false)];
    if (values == null ||
        (values.length == 1 && values.single.trim().isEmpty)) {
      return _defaultSort(sortDefaults);
    }
    final orders = <SortOrder>[];
    for (final value in values) {
      orders.addAll(_parse(value));
    }
    return Sort.byOrders(orders);
  }

  Sort _defaultSort(List<SortDefault> defaults) {
    var result = Sort.unsorted;
    for (final one in defaults) {
      result = result.and(_sortOf(one.sort, one.direction));
    }
    return result;
  }

  static Sort _sortOf(List<String> properties, Direction direction) =>
      Sort.byOrders([
        for (final property in properties)
          if (property.trim().isNotEmpty)
            SortOrder(property.trim(), direction: direction),
      ]);

  // `title,year,desc` and `title,ignorecase`: Spring's SortOrderParser.
  List<SortOrder> _parse(String part) {
    final elements = part.split(',');
    var end = elements.length;
    var ignoreCase = false;
    if (end > 0 && elements[end - 1].trim().toLowerCase() == 'ignorecase') {
      ignoreCase = true;
      end--;
    }
    var direction = Direction.asc;
    if (end > 0) {
      final last = switch (elements[end - 1].trim().toLowerCase()) {
        'asc' => Direction.asc,
        'desc' => Direction.desc,
        _ => null,
      };
      if (last != null) {
        direction = last;
        end--;
      }
    }
    return [
      for (var i = 0; i < end; i++)
        if (elements[i].trim().isNotEmpty)
          SortOrder(
            elements[i].trim(),
            direction: direction,
            ignoreCase: ignoreCase,
          ),
    ];
  }

  String _name(String source, String? qualifier, bool withPrefix) {
    final out = StringBuffer(withPrefix ? properties.prefix : '');
    if (qualifier != null) {
      out
        ..write(qualifier)
        ..write(properties.qualifierDelimiter);
    }
    return (out..write(source)).toString();
  }

  static String? _first(Map<String, List<String>> query, String name) {
    final values = query[name];
    return values == null || values.isEmpty ? null : values.first;
  }

  // Spring's parseAndApplyBoundaries: absent for blank text; a number
  // below zero is 0, above [upper] is [upper]; text that is no int is 0.
  int? _number(String? text, int upper, {bool shift = false}) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final parsed = RegExp(r'^[+-]?\d+$').hasMatch(text)
        ? int.tryParse(text)
        : null;
    // Java's Integer.parseInt fails beyond 32 bits.
    if (parsed == null || parsed > 0x7fffffff || parsed < -0x80000000) {
      return 0;
    }
    final value = parsed - (shift ? 1 : 0);
    return value < 0
        ? 0
        : value > upper
        ? upper
        : value;
  }
}
