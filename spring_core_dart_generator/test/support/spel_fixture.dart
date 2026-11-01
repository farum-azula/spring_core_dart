// The values of spel_compiler_test.dart: classes and top-level variables
// that the analyzer types (the compiler reads their declarations), that the
// generated program reads directly and that the interpreter reads through
// the accessors below, so one expression runs both ways on the same data.
// The variables are `final`, not `const`, with their declared types, which
// are what the analyzer reports for them.
// ignore_for_file: prefer_const_declarations, prefer_int_literals
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations
// ignore_for_file: prefer_const_constructors
import 'package:spring_core_dart/spring_core_dart.dart';

enum Status { draft, published }

class Author {
  const Author(this.name, {this.country, this.mentor});

  final String name;
  final String? country;
  final Author? mentor;

  String shout() => name.toUpperCase();
}

class Book {
  Book({
    required this.title,
    required this.year,
    this.subtitle,
    this.author,
    this.tags = const [],
    this.rating = 0,
    this.price = 0,
    this.status = Status.draft,
    this.stock,
    this.counts = const {},
    this.sequel,
  });

  final String title;
  final String? subtitle;
  final int year;
  final Author? author;
  final List<String> tags;
  final double rating;
  final num price;
  final Status status;
  final int? stock;
  final Map<String, int> counts;
  final Book? sequel;

  String get label => '$title ($year)';
  bool get published => status == Status.published;
  int get boom => throw StateError('boom');
  List<Book> get related => [?sequel];

  String greet(String who) => 'Hello $who from $title';
  String repeatWord(String word, [int times = 1]) => word * times;
  int plus(int by) => year + by;
  double scale(double by) => rating * by;
  Book withTitle(String other) => Book(title: other, year: year);
  int explode() => throw StateError('explode');
  void touch() {}
}

class Catalog {
  const Catalog(this.books);

  final List<Book> books;

  int get size => books.length;

  String lookup(String isbn) => 'book-$isbn';
  Book first() => books.first;
}

final Book sequel = Book(title: 'Dune Messiah', year: 1969);

final Book book = Book(
  title: 'Dune',
  year: 1965,
  author: const Author(
    'Frank Herbert',
    mentor: Author('Somebody', country: 'US'),
  ),
  tags: const ['scifi', 'classic'],
  rating: 4.5,
  price: 12,
  status: Status.published,
  counts: const {'a': 1, 'b': 2},
  sequel: sequel,
);

final Book? ghost = null;
final Book? maybeBook = sequel;

final int count = 7;
final int zero = 0;
final int negative = -7;
final int? maybeInt = null;
final int? someInt = 5;
final double ratio = 2.5;
final double whole = 7.0;
final double zeroD = 0.0;
final num anyNum = 3;

final String name = 'Ada';
final String? nothing = null;
final String empty = '';
final String? blank = '';
final String big = 'x' * 60000;

final bool yes = true;
final bool no = false;
final bool? maybeBool = null;

final List<String> names = ['a', 'b', 'c'];
final List<String>? maybeNames = null;
final List<String>? someNames = ['x', 'y'];
final List<int> numbers = [1, 2, 3];
final Map<String, int> scores = {'ada': 10};
final Map<String, int>? maybeScores = null;
final Map<String, Object?> filter = {
  'address': {'city': 'Paris'},
  'tags': ['a'],
};
final Status status = Status.published;
final Object? opaque = 'opaque';

final Catalog catalog = Catalog([book, sequel]);
final ConfigurableEnvironment environment = StandardEnvironment()
  ..propertySources.addFirst(MapPropertySource('test', {'app.name': 'demo'}));

/// The `#name` variables of the expressions, by name.
final Map<String, Object?> variables = {
  'book': book,
  'ghost': ghost,
  'maybeBook': maybeBook,
  'count': count,
  'zero': zero,
  'negative': negative,
  'maybeInt': maybeInt,
  'someInt': someInt,
  'ratio': ratio,
  'whole': whole,
  'zeroD': zeroD,
  'anyNum': anyNum,
  'name': name,
  'nothing': nothing,
  'empty': empty,
  'blank': blank,
  'big': big,
  'yes': yes,
  'no': no,
  'maybeBool': maybeBool,
  'names': names,
  'maybeNames': maybeNames,
  'someNames': someNames,
  'numbers': numbers,
  'scores': scores,
  'maybeScores': maybeScores,
  'filter': filter,
  'status': status,
  'opaque': opaque,
};

/// The beans `@name` stands for.
final Map<String, Object> beans = {
  'catalog': catalog,
  'environment': environment,
};

final class _Beans implements BeanResolver {
  @override
  Object? resolve(EvaluationContext context, String beanName) =>
      beans[beanName] ?? (throw AccessException('No bean $beanName'));
}

/// An interpreter context over the same values: [book] is the root, and
/// the classes above are readable through accessors (the interpreter has no
/// introspection data for them).
StandardEvaluationContext interpreterContext() {
  final context = StandardEvaluationContext(book)
    ..beanResolver = _Beans()
    ..addPropertyAccessor(
      FunctionPropertyAccessor<Book>(
        getters: {
          'title': (b) => b.title,
          'subtitle': (b) => b.subtitle,
          'year': (b) => b.year,
          'author': (b) => b.author,
          'tags': (b) => b.tags,
          'rating': (b) => b.rating,
          'price': (b) => b.price,
          'status': (b) => b.status,
          'stock': (b) => b.stock,
          'counts': (b) => b.counts,
          'sequel': (b) => b.sequel,
          'label': (b) => b.label,
          'published': (b) => b.published,
          'boom': (b) => b.boom,
          'related': (b) => b.related,
        },
      ),
    )
    ..addPropertyAccessor(
      FunctionPropertyAccessor<Author>(
        getters: {
          'name': (a) => a.name,
          'country': (a) => a.country,
          'mentor': (a) => a.mentor,
        },
      ),
    )
    ..addPropertyAccessor(
      FunctionPropertyAccessor<Catalog>(
        getters: {'size': (c) => c.size, 'books': (c) => c.books},
      ),
    )
    ..addMethodResolver(
      FunctionMethodResolver<Book>({
        'greet': (b, args) => b.greet(args[0]! as String),
        'repeatWord': (b, args) => b.repeatWord(
          args[0]! as String,
          args.length > 1 ? args[1]! as int : 1,
        ),
        'plus': (b, args) => b.plus(args[0]! as int),
        'scale': (b, args) => b.scale((args[0]! as num).toDouble()),
        'withTitle': (b, args) => b.withTitle(args[0]! as String),
        'explode': (b, args) => b.explode(),
        'touch': (b, args) => b.touch(),
      }),
    )
    ..addMethodResolver(
      FunctionMethodResolver<Author>({'shout': (a, args) => a.shout()}),
    )
    ..addMethodResolver(
      FunctionMethodResolver<Catalog>({
        'lookup': (c, args) => c.lookup(args[0]! as String),
        'first': (c, args) => c.first(),
      }),
    )
    ..addMethodResolver(
      FunctionMethodResolver<Environment>({
        'getProperty': (e, args) => e.getProperty(
          args[0]! as String,
          defaultValue: args.length > 1 ? args[1] as String? : null,
        ),
        'getRequiredProperty': (e, args) =>
            e.getRequiredProperty(args[0]! as String),
        'containsProperty': (e, args) => e.containsProperty(args[0]! as String),
        'resolvePlaceholders': (e, args) =>
            e.resolvePlaceholders(args[0]! as String),
        'resolveRequiredPlaceholders': (e, args) =>
            e.resolveRequiredPlaceholders(args[0]! as String),
      }),
    );
  for (final MapEntry(:key, :value) in variables.entries) {
    context.setVariable(key, value);
  }
  return context;
}

/// What running [body] gives, as text to compare: the runtime type and the
/// value of a scalar, the code and message of a SpEL error, the type and
/// message of any other error.
String outcomeOf(Object? Function() body) {
  try {
    final value = body();
    return value == null || value is num || value is bool || value is String
        ? '${value.runtimeType}|$value'
        : 'object|$value';
  } on SpelEvaluationException catch (error) {
    return 'spel|${error.messageCode.name}|${error.simpleMessage}';
  } on Object catch (error) {
    return 'dart|${error.runtimeType}|$error';
  }
}
