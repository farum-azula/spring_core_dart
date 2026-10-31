import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

// The default values the introspection describes: the defaults of the
// constructor parameters and the constant initializers of the fields.

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

const _models = r'''
enum Status { draft, live }

const publicLimit = 7;
const _privateLimit = 9;

@Introspected()
class Fields {
  int version = 0;
  bool inStock = true;
  String status = 'new';
  double rate = 1;
  int offset = -3;
  double scale = -1.5;
  String? note = null;
  Status state = Status.draft;
  List<String> tags = const ['a', 'b'];
  Map<String, int> limits = const {'x': 1};
  Set<int> ids = const {1, 2};
  int limit = publicLimit;
  int hidden = _privateLimit;
  int noInitializer = 0;
  late int later = 5;
  DateTime added = DateTime.now();
  List<String> notConst = [];
  String interpolated = 'v${publicLimit}';
}

@Introspected()
class Plain {
  Plain(this.name);
  late String name;
  String? other;
}

class Base {
  Base({this.level = 3});
  final int level;
}

@Introspected()
class Params extends Base {
  Params(
    this.title, [
    this.size = 5,
  ]) : super();
  final String title;
  final int size;
}

@Introspected()
class Named extends Base {
  Named({
    required this.id,
    super.level = 4,
    this.count = 5,
    this.status = Status.draft,
    this.nothing = null,
    this.tags = const ['t'],
    this.label = 'x',
    this.flag = false,
    this.limit = _privateLimit,
    this.created,
    String? alias,
  }) : alias = alias ?? '';
  final int id;
  final int count;
  final Status status;
  final String? nothing;
  final List<String> tags;
  final String label;
  final bool flag;
  final int limit;
  final DateTime? created;
  final String alias;
}

@Introspected()
class Fresh {
  Fresh();
  String? name;
}
''';

Future<(String, List<String>)> _generate(String source) async {
  final sources = {
    'lib/src/beans.dart': _scan,
    'lib/src/models.dart': '$_header$source',
  };
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final output = result.readerWriter.testing.readString(result.outputs.single);
  final errors = await resolveSources<List<String>>(
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      'pkg|lib/src/beans.spring.dart': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/src/beans.spring.dart'),
      );
      final result = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (result case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/src/beans.spring.dart',
    readAllSourcesFromFilesystem: true,
  );
  return (_normalize(output), errors);
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

// The arguments of the property `Class.name` before its `get` closure.
String _property(String output, String bean, String name) {
  final start = output.indexOf("BeanProperty<$bean>(r'$name',");
  expect(start, isNonNegative, reason: 'property $bean.$name');
  return output.substring(start, output.indexOf('get:', start));
}

// The arguments of the constructor parameter `name` of `bean` (up to the
// next parameter or the end of the list).
String _parameter(String output, String bean, String name) {
  final model = output.indexOf('BeanIntrospection<$bean>(');
  final start = output.indexOf("BeanParameter(r'$name',", model);
  expect(start, isNonNegative, reason: 'parameter $bean($name)');
  final next = output.indexOf('BeanParameter(', start + 1);
  final close = output.indexOf('],create:', start);
  return output.substring(
    start,
    next == -1 || next > close ? close : next,
  );
}

void main() {
  late final String output;
  late final List<String> errors;

  setUpAll(() async {
    (output, errors) = await _generate(_models);
  });

  test('the generated code compiles', () {
    expect(errors, isEmpty);
  });

  group('field initializers', () {
    void initial(String name, String value) {
      test('$name has the initial value $value', () {
        expect(
          _property(output, 'Fields', name),
          _has('hasInitialValue: true, initialValue: $value,'),
        );
      });
    }

    void none(String name) {
      test('$name has no initial value', () {
        expect(_property(output, 'Fields', name), isNot(contains('Initial')));
      });
    }

    initial('version', '0');
    initial('inStock', 'true');
    initial('status', "r'new'");
    initial('rate', '1.0');
    initial('offset', '-3');
    initial('scale', '-1.5');
    initial('note', 'null');
    initial('state', 'Status.draft');
    initial('tags', "const [r'a', r'b']");
    initial('limits', "const {r'x': 1}");
    initial('ids', 'const {1, 2}');
    initial('limit', '7');
    initial('hidden', '9');
    initial('noInitializer', '0');
    initial('later', '5');
    none('added');
    none('notConst');
    none('interpolated');

    test('a field without an initializer has none', () {
      expect(_property(output, 'Plain', 'other'), isNot(contains('Initial')));
      expect(_property(output, 'Plain', 'name'), isNot(contains('Initial')));
    });
  });

  group('constructor parameter defaults', () {
    void default_(String bean, String name, String value) {
      test('$bean($name) defaults to $value', () {
        expect(
          _parameter(output, bean, name),
          _has('hasDefaultValue: true, defaultValue: $value)'),
        );
      });
    }

    void none(String bean, String name) {
      test('$bean($name) has no default', () {
        expect(
          _parameter(output, bean, name),
          isNot(contains('DefaultValue')),
        );
      });
    }

    default_('Params', 'size', '5');
    none('Params', 'title');
    default_('Named', 'count', '5');
    default_('Named', 'level', '4');
    default_('Named', 'status', 'Status.draft');
    default_('Named', 'nothing', 'null');
    default_('Named', 'tags', "const [r't']");
    default_('Named', 'label', "r'x'");
    default_('Named', 'flag', 'false');
    default_('Named', 'limit', '9');
    none('Named', 'id');
    none('Named', 'created');
    none('Named', 'alias');
  });

  test('a class without defaults is written as before', () {
    final start = output.indexOf('BeanIntrospection<Fresh>(');
    final end = output.indexOf('BeanIntrospection<', start + 1);
    final fresh = output.substring(start, end == -1 ? output.length : end);
    expect(fresh, isNot(contains('hasInitialValue')));
    expect(fresh, isNot(contains('hasDefaultValue')));
    expect(fresh, isNot(contains('Value:')));
  });
}
