// The rules of the Pageable and Sort controller parameters, without the web
// starter (the glue only hands the query parameters over). The glue itself
// runs in spring_core_dart_generator/test/web_glue_runtime_test.dart.
import 'dart:convert';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

Map<String, List<String>> _q(String query) => Uri.splitQueryString(query).map(
  (key, value) => MapEntry(key, [value]),
)..addAll(_multi(query));

// `sort=a&sort=b`: splitQueryString keeps the last; the query parameters of
// Uri keep all.
Map<String, List<String>> _multi(String query) =>
    Uri(query: query).queryParametersAll;

String _show(Pageable p) => '${p.pageNumber}/${p.pageSize}/${p.sort}';

void main() {
  const paging = WebPaging();

  group('Pageable', () {
    test('Spring Boot defaults: page 0 of 20', () {
      expect(_show(paging.pageable(_q(''))), '0/20/UNSORTED');
    });

    test('page, size and sort come from the query', () {
      expect(
        _show(paging.pageable(_q('page=2&size=5&sort=a,desc&sort=b'))),
        '2/5/a: desc, b: asc',
      );
    });

    test('the size is cut at the maximum; below one or text is the default; '
        'a bad page is 0', () {
      expect(_show(paging.pageable(_q('size=2001'))), '0/2000/UNSORTED');
      expect(_show(paging.pageable(_q('size=0'))), '0/20/UNSORTED');
      expect(_show(paging.pageable(_q('size=-5'))), '0/20/UNSORTED');
      expect(_show(paging.pageable(_q('size=x&page=y'))), '0/20/UNSORTED');
      expect(_show(paging.pageable(_q('page=-1'))), '0/20/UNSORTED');
      expect(
        _show(paging.pageable(_q('page=99999999999'))),
        '0/20/UNSORTED',
      );
      expect(_show(paging.pageable(_q('page=%202'))), '0/20/UNSORTED');
    });

    test('one-indexed parameters: page 1 is the first, 0 too', () {
      const one = WebPaging(WebPagingProperties(oneIndexedParameters: true));
      expect(_show(one.pageable(_q('page=1'))), '0/20/UNSORTED');
      expect(_show(one.pageable(_q('page=3'))), '2/20/UNSORTED');
      expect(_show(one.pageable(_q('page=0'))), '0/20/UNSORTED');
    });

    test('@PageableDefault supplies what the request leaves out', () {
      const d = PageableDefault(
        size: 5,
        page: 1,
        sort: ['t'],
        direction: Direction.desc,
      );
      expect(_show(paging.pageable(_q(''), pageableDefault: d)), '1/5/t: desc');
      expect(
        _show(paging.pageable(_q('size=7&sort=u'), pageableDefault: d)),
        '1/7/u: asc',
      );
    });

    test('@SortDefault applies without a sort parameter, in order', () {
      const defaults = [
        SortDefault(sort: ['a'], direction: Direction.desc),
        SortDefault(sort: ['b']),
      ];
      expect(
        _show(paging.pageable(_q(''), sortDefaults: defaults)),
        '0/20/a: desc, b: asc',
      );
      expect(
        _show(paging.pageable(_q('sort=c'), sortDefaults: defaults)),
        '0/20/c: asc',
      );
    });

    test('the size of the default is cut at the maximum too', () {
      expect(
        _show(
          paging.pageable(
            _q(''),
            pageableDefault: const PageableDefault(size: 5000),
          ),
        ),
        '0/2000/UNSORTED',
      );
    });

    test('a qualifier, prefix and delimiter shape the names', () {
      const custom = WebPaging(
        WebPagingProperties(
          pageParameter: 'p',
          sizeParameter: 'n',
          prefix: 'x.',
          qualifierDelimiter: '-',
          sortParameter: 'order',
        ),
      );
      expect(
        // The prefix is for page and size only; the sort has its qualifier.
        _show(custom.pageable(_q('x.b-p=2&x.b-n=3&order=z'), qualifier: 'b')),
        '2/3/UNSORTED',
      );
      expect(
        _show(custom.pageable(_q('x.b-p=2&x.b-n=3&b-order=z'), qualifier: 'b')),
        '2/3/z: asc',
      );
    });
  });

  group('Sort', () {
    test('a direction ends a part and covers its properties', () {
      expect(paging.sort(_q('sort=a,b,desc')).toString(), 'a: desc, b: desc');
      expect(paging.sort(_q('sort=a,foo')).toString(), 'a: asc, foo: asc');
    });

    test('ignorecase, in any case, may end a part', () {
      expect(
        paging.sort(_q('sort=a,desc,IgnoreCase')).toString(),
        'a: desc, ignoring case',
      );
    });

    test('empty parts and an empty sort= are no order', () {
      expect(paging.sort(_q('sort=')).isUnsorted, isTrue);
      expect(paging.sort(_q('sort=,')).isUnsorted, isTrue);
    });

    test('a property is kept as given: the repository refuses a wrong one', () {
      expect(paging.sort(_q('sort=nope')).orders.single.property, 'nope');
    });
  });

  group('properties', () {
    test('are read from the environment', () {
      final environment = StandardEnvironment();
      environment.propertySources.addFirst(
        const MapPropertySource('t', {
          'spring.data.web.pageable.default-page-size': '3',
          'spring.data.web.pageable.max-page-size': '9',
          'spring.data.web.pageable.one-indexed-parameters': 'true',
          'spring.data.web.sort.sort-parameter': 'order',
        }),
      );
      final p = WebPagingProperties.of(environment);
      expect(
        [p.defaultPageSize, p.maxPageSize, p.oneIndexedParameters],
        [3, 9, true],
      );
      expect(
        [p.pageParameter, p.sizeParameter, p.sortParameter],
        [
          'page',
          'size',
          'order',
        ],
      );
    });

    test('a malformed number names the key', () {
      final environment = StandardEnvironment();
      environment.propertySources.addFirst(
        const MapPropertySource('t', {
          'spring.data.web.pageable.max-page-size': 'many',
        }),
      );
      expect(
        () => WebPagingProperties.of(environment),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'spring.data.web.pageable.max-page-size',
          ),
        ),
      );
    });
  });

  group('Page as JSON', () {
    test("is Spring Data 3.3's stable shape", () {
      final page = PageImpl<Object>(
        ['a', 'b'],
        PageRequest.of(1, 2),
        5,
      );
      expect(jsonDecode(jsonEncode(page.toJson())), {
        'content': ['a', 'b'],
        'page': {'size': 2, 'number': 1, 'totalElements': 5, 'totalPages': 3},
      });
    });

    test('an unpaged page holds everything on page 0', () {
      final page = PageImpl<int>([1, 2, 3], const Pageable.unpaged(), 3);
      expect(page.toJson()['page'], {
        'size': 3,
        'number': 0,
        'totalElements': 3,
        'totalPages': 1,
      });
    });
  });

  test('InvalidDataArgumentException is an InvalidDataAccessApiUsage', () {
    expect(
      InvalidDataArgumentException('x'),
      isA<InvalidDataAccessApiUsageException>(),
    );
  });
}
