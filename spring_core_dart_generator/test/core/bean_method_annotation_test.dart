// `@BeanMethodAnnotation`: marked methods become the bean definition's
// annotated methods, called directly where they can be.
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  group('@BeanMethodAnnotation', () {
    const source = """
@BeanMethodAnnotation()
class Every {
  const Every(this.period, {this.name});
  final Duration period;
  final String? name;
}

class Plain {
  const Plain();
}

abstract interface class Job {
  @Every(Duration(minutes: 1))
  void tick();
}

@Component()
class Poller implements Job {
  @override
  void tick() {}

  @Every(Duration(seconds: 30), name: 'inbox')
  @Plain()
  Future<void> check(int attempt, [String? label]) async {}

  @Plain()
  void notMarked() {}
}

class Report {
  @Every(Duration(hours: 1))
  void hourly() {}
}

@Configuration()
class Config {
  @Bean()
  Report report() => Report();
}
""";

    test('marked methods become BeanDefinition.annotatedMethods', () async {
      final output = await generateModule(source);
      // A constant, called directly through a top-level function (an
      // absent optional argument gets its default).
      expect(
        output,
        hasCode(
          "annotatedMethods: [const IntrospectedMethod<Poller>(r'check', "
          'parameterTypes: [int, String], '
          "parameters: [IntrospectedParameter(r'attempt', type: "
          'ClassType<int>(), isRequired: true), '
          "IntrospectedParameter(r'label', type: ClassType<String>(nullable: "
          'true))], '
          'isFuture: true, isVoid: true, invoke: ',
        ),
      );
      expect(
        output,
        matches(
          RegExp(
            r'isVoid:true,invoke:_\$invoke\d+,'
            r"annotations:\[Every\(Duration\(seconds:30\),name:r'inbox'\),"
            r'Plain\(\)\]\)',
          ),
        ),
      );
      expect(
        output,
        hasCode(
          '(Poller bean, List<Object?> arguments) => '
          'bean.check((arguments[0] as int), '
          'arguments.argumentOr(1, null));',
        ),
      );
      // Declared on the interface, implemented by the bean; a void method
      // answers null.
      expect(
        output,
        matches(
          RegExp(
            r"IntrospectedMethod<Poller>\(r'tick',isVoid:true,invoke:_\$invoke\d+,"
            r'annotations:\[Every\(Duration\(minutes:1\)\)\]\)',
          ),
        ),
      );
      expect(
        output,
        hasCode(
          '(Poller bean, List<Object?> arguments) '
          '{ bean.tick(); return null; }',
        ),
      );
      expect(output, isNot(contains('notMarked')));
      // The return type of a @Bean method is scanned too.
      expect(
        output,
        matches(
          RegExp(
            r"annotatedMethods:\[constIntrospectedMethod<Report>\(r'hourly',"
            r'isVoid:true,invoke:_\$invoke\d+,'
            r'annotations:\[Every\(Duration\(hours:1\)\)\]\)\]',
          ),
        ),
      );
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test(
      'named parameters, the result type and annotated parameters',
      () async {
        final output = await generateModule("""
@BeanMethodAnnotation()
class Handles {
  const Handles();
}

class Param {
  const Param(this.name);
  final String name;
}

class Item {
  const Item(this.id);
  final int id;
}

@Component()
class Api {
  @Handles()
  Future<List<Item>> find(@Param('q') String query, {required int page, int size = 20}) async => [];
}
""");
        expect(
          output,
          hasCode(
            "parameters: [IntrospectedParameter(r'query', type: "
            'ClassType<String>(), '
            "isRequired: true, annotations: [Param(r'q')]), "
            "IntrospectedParameter(r'page', type: ClassType<int>(), symbol: "
            '#page, isRequired: true), '
            "IntrospectedParameter(r'size', type: ClassType<int>(), symbol: "
            '#size)], '
            'returnTypeInfo: ListType<Item>(ClassType<Item>()), '
            'isFuture: true, ',
          ),
        );
        // Called directly with the named arguments; without them the
        // required `page` cannot be passed, so `Function.apply` says so.
        expect(
          output,
          hasCode(
            '(Api bean, List<Object?> positional, Map<Symbol, Object?> named) '
            '=> bean.find((positional[0] as String), '
            'page: (named[#page] as int), size: named.argumentOr(#size, 20));',
          ),
        );
        expect(
          output,
          hasCode(
            '(Api bean, List<Object?> arguments) => '
            'Function.apply(bean.find, arguments);',
          ),
        );
        // The result type of the bean's package is introspected.
        expect(output, contains('Introspection<Item>'));
      },
    );

    group('direct calls', () {
      // What a direct call cannot write: a type parameter of the class that
      // declares the method (a generic base controller), and defaults that
      // are no literals (double.infinity, double.nan, typed empty lists).
      const source = '''
@BeanMethodAnnotation()
class Handles {
  const Handles();
}

class Book {}

abstract class Crud<E> {
  @Handles()
  void save(E entity) {}

  @Handles()
  List<E> all({int limit = 10}) => [];

  @Handles()
  Map<String, List<E>> grouped() => {};

  E? current;
}

@Component()
@Introspected()
class BookCrud extends Crud<Book> {}

@Component()
class Ticker {
  @Handles()
  void tick({
    double max = double.infinity,
    double min = double.negativeInfinity,
    double unset = double.nan,
    List<int> ids = const <int>[],
    Map<String, int> named = const <String, int>{},
    Set<String> few = const <String>{'a'},
    Map<Object, int> keyed = const <Object, int>{1: 2},
    Map<String, Object> filters = const <String, Object>{'year': 2026},
  }) {}
}

@Introspected()
class Limits {
  Limits({this.max = double.infinity, this.ids = const <int>[]});
  final double max;
  final List<int> ids;
  double rate = double.nan;
  List<String> tags = const <String>[];
  List<num> limits = const [1];
}
''';

      test('the generated code compiles', () async {
        expect(
          await compileErrors({'lib/src/service.dart': source}),
          isEmpty,
        );
      });

      test('a type parameter of the declaring class: Function.apply', () async {
        final output = await generateModule(source);
        expect(
          output,
          hasCode(
            '(BookCrud bean, List<Object?> arguments) => '
            'Function.apply(bean.save, arguments);',
          ),
        );
        expect(output, isNot(contains('asE)')));
        // Its free type parameters are unknown types, at any depth.
        expect(output, hasCode('returnType: List<Object?>'));
        expect(output, hasCode('returnType: Map<String, List<Object?>>'));
        expect(output, isNot(contains('returnType: List<dynamic>')));
      });

      test('defaults that are no literals keep their meaning', () async {
        final output = await generateModule(source);
        expect(output, hasCode('named.argumentOr(#max, double.infinity)'));
        expect(
          output,
          hasCode('named.argumentOr(#min, double.negativeInfinity)'),
        );
        expect(output, hasCode('named.argumentOr(#unset, double.nan)'));
        expect(output, hasCode('named.argumentOr(#ids, const <int>[])'));
        expect(
          output,
          hasCode('named.argumentOr(#named, const <String, int>{})'),
        );
        // The elements give the type of a non-empty one.
        expect(output, hasCode("named.argumentOr(#few, const {r'a'})"));
        expect(output, hasCode('initialValue: double.nan'));
        expect(output, hasCode('initialValue: <String>[]'));
        // The field's type, not the elements', gives that of a non-empty
        // initial value.
        expect(output, hasCode('initialValue: <num>[1]'));
        // Both type arguments of a map, or code_builder writes
        // `<Object, dynamic>` and `<String, Object>` none.
        expect(
          output,
          hasCode('named.argumentOr(#keyed, const <Object, int>{1: 2})'),
        );
        expect(
          output,
          hasCode(
            "named.argumentOr(#filters, const <String, Object>{r'year': 2026})",
          ),
        );
        expect(output, hasCode('defaultValue: double.infinity'));
        expect(output, isNot(contains('Infinity,')));
        expect(output, isNot(contains('NaN')));
      });
    });

    test('private, static and generic methods are rejected', () async {
      const every = '''
@BeanMethodAnnotation()
class Every {
  const Every();
}
''';
      await expectBuildError(
        '$every@Component() class A { @Every() void _run() {} }',
        'must be a public instance method',
      );
      await expectBuildError(
        '$every@Component() class A { @Every() static void run() {} }',
        'must be a public instance method',
      );
      await expectBuildError(
        '$every@Component() class A { @Every() void run<T>() {} }',
        'must not be generic',
      );
    });
  });
}
