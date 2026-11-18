// compileSpel: SpEL expressions compiled to Dart on real analyzer types.
//
// The expressions run against the classes and variables of
// support/spel_fixture.dart. The tests check the code written for each
// construct, the problems and the `unsupported` outcomes, and that the code
// gives what the interpreter gives: the compiled expressions are written
// into one Dart program, which is run in a process of its own (it needs
// `dart` and the package config of the test), and its results are compared
// with the interpreter's on the same data, errors included.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:code_builder/code_builder.dart'
    show DartEmitter, Expression, literalNum, refer;
import 'package:dart_style/dart_style.dart';
import 'package:spring_core_dart/spring_core_dart.dart'
    show SpelExpressionParser;
import 'package:spring_core_dart_generator/src/spel_compiler.dart';
import 'package:test/test.dart';

import 'support/spel_fixture.dart' as fixture;

// Every variable of the fixture, and the scopes the expressions compile in.
const _variables = [
  'book',
  'ghost',
  'maybeBook',
  'count',
  'zero',
  'negative',
  'maybeInt',
  'someInt',
  'ratio',
  'whole',
  'zeroD',
  'anyNum',
  'name',
  'nothing',
  'empty',
  'blank',
  'big',
  'yes',
  'no',
  'maybeBool',
  'names',
  'maybeNames',
  'someNames',
  'numbers',
  'scores',
  'maybeScores',
  'filter',
  'status',
  'opaque',
];

// `book` is the root, the variables and the beans `catalog` and
// `environment` are there.
const _full = 'full';

// The same, but `#book` and the root are read from the first argument, as
// generated code reads a method's arguments.
const _arguments = 'arguments';

// `#book` read as `a[0]`, as `list.first()` and as a conditional: the code
// of a primary is used as it is, any other is parenthesized.
const _indexed = 'indexed';
const _called = 'called';
const _composite = 'composite';

// No root, no beans.
const _bare = 'bare';

// A root, but no bean resolver.
const _noBeans = 'noBeans';

// `@environment` only, as the `environment` parameter.
const _environmentOnly = 'environmentOnly';

// What the code of an expression looks like, and its static type.
const _emitted = <(String, String, String, String)>[
  // (scope, expression, code, type)
  (_full, "'plain'", "'plain'", 'String'),
  (_full, r"'it''s $x \ ok'", r'''r"it's $x \ ok"''', 'String'),
  (_full, '42', '42', 'int'),
  (_full, '-5', '-5', 'int'),
  (_full, '+5', '5', 'int'),
  (_full, '3.14', '3.14', 'double'),
  (_full, '2d', '2.0', 'double'),
  (_full, '0x1F', '31', 'int'),
  (_full, 'true', 'true', 'bool'),
  (_full, 'null', 'null', 'Null'),
  (_full, '#count', 'count', 'int'),
  (_full, '#root.title', 'book.title', 'String'),
  (_full, '#this.title', 'book.title', 'String'),
  (_full, 'title', 'book.title', 'String'),
  (_full, '#book.label', 'book.label', 'String'),
  (_full, '#book.author?.name', 'book.author?.name', 'String?'),
  (
    _full,
    '#book.author?.mentor?.country',
    'book.author?.mentor?.country',
    'String?',
  ),
  (_full, '#ghost?.title', 'ghost?.title', 'String?'),
  (_full, '#ghost?.title?.length', 'ghost?.title?.length', 'int?'),
  (_full, '#book.tags.first', 'book.tags.first', 'String'),
  (_full, '#book.status.name', 'book.status.name', 'String'),
  (_full, '#book.status.index', 'book.status.index', 'int'),
  (_full, '#book.greet(#name)', 'book.greet(name)', 'String'),
  (_full, "#book.repeatWord('ab', 3)", "book.repeatWord('ab', 3)", 'String'),
  (_full, '#book.scale(2)', 'book.scale(2.toDouble())', 'double'),
  (_full, '#book.author?.shout()', 'book.author?.shout()', 'String?'),
  (_full, '#name.substring(1, 2)', 'name.substring(1, 2)', 'String'),
  (_full, '#numbers.sublist(1)', 'numbers.sublist(1)', 'List<int>'),
  (
    _full,
    '#ratio.toString()',
    'SpelOperations.doubleToString(ratio)',
    'String',
  ),
  (_full, "@catalog.lookup('x')", "catalog.lookup('x')", 'String'),
  (_full, '@catalog.first().title', 'catalog.first().title', 'String'),
  (
    _full,
    "@environment.getProperty('app.name')?.length",
    "environment.getProperty('app.name')?.length",
    'int?',
  ),
  (_full, '#names[0]', 'SpelOperations.listElement(names, 0)', 'String'),
  (_full, "#scores['ada']", "scores['ada']", 'int?'),
  (_full, '#scores[ada]', "scores['ada']", 'int?'),
  (_full, '#name[1]', 'SpelOperations.stringElement(name, 1)', 'String'),
  (_full, 'tags[0]', 'SpelOperations.listElement(book.tags, 0)', 'String'),
  (
    _full,
    '#maybeNames?.[0]',
    r'(switch (maybeNames) { final spel$target? => '
        r'SpelOperations.listElement(spel$target, 0), _ => null })',
    'String?',
  ),
  (_full, '1 + 2', '1 + 2', 'int'),
  (_full, '1 + 2.5', '1 + 2.5', 'double'),
  (_full, '#anyNum + 1', 'anyNum + 1', 'num'),
  (_full, '#count * #ratio', 'count * ratio', 'double'),
  (_full, '#count / 2', 'SpelOperations.divideInts(count, 2)', 'int'),
  (_full, '#count / #ratio', 'count / ratio', 'double'),
  (_full, '#anyNum / 2', 'SpelOperations.divide(anyNum, 2)', 'num'),
  (_full, '7 % 3', 'SpelOperations.modulusInts(7, 3)', 'int'),
  (_full, '#ratio % 2', 'SpelOperations.modulusReals(ratio, 2)', 'double'),
  (_full, '#anyNum % 2', 'SpelOperations.modulus(anyNum, 2)', 'num'),
  (_full, '2 ^ 10', 'SpelOperations.powerInts(2, 10)', 'int'),
  (_full, '2 ^ 0.5', 'SpelOperations.powerReals(2, 0.5)', 'double'),
  (_full, '#anyNum ^ 2', 'SpelOperations.power(anyNum, 2)', 'num'),
  (_full, '-#count', '-count', 'int'),
  (_full, '-(-3)', '-(-3)', 'int'),
  (_full, '1 + 2 * 3', '1 + 2 * 3', 'int'),
  (_full, '(1 + 2) * 3', '(1 + 2) * 3', 'int'),
  (_full, '10 - (2 - 3)', '10 - (2 - 3)', 'int'),
  (
    _full,
    '(#count + 1) / 2',
    'SpelOperations.divideInts(count + 1, 2)',
    'int',
  ),
  (_full, "'a' + 1", "SpelOperations.concat('a', 1)", 'String'),
  (_full, "#nothing + 'x'", "SpelOperations.concat(nothing, 'x')", 'String'),
  (
    _full,
    "'n=' + #whole",
    "SpelOperations.concat('n=', whole, rightReal: true)",
    'String',
  ),
  (_full, '1 + 2 + "a"', "SpelOperations.concat(1 + 2, 'a')", 'String'),
  (_full, '#count == 1', 'count == 1', 'bool'),
  (_full, "#name ne 'Ada'", "name != 'Ada'", 'bool'),
  (_full, '#ghost != null', 'ghost != null', 'bool'),
  (_full, '#maybeInt == 5', 'maybeInt == 5', 'bool'),
  (_full, '#book == #ghost', 'SpelOperations.equals(book, ghost)', 'bool'),
  (_full, "#count == 'a'", "SpelOperations.equals(count, 'a')", 'bool'),
  (_full, '#count lt 5', 'count.compareTo(5) < 0', 'bool'),
  (_full, "#name < 'b'", "name.compareTo('b') < 0", 'bool'),
  (_full, '#ratio >= 2.5', 'ratio.compareTo(2.5) >= 0', 'bool'),
  (_full, '(#count + 1) > 2', '(count + 1).compareTo(2) > 0', 'bool'),
  (
    _full,
    '#maybeInt < 1',
    'SpelOperations.compare(maybeInt, 1) < 0',
    'bool',
  ),
  (_full, '#yes < #no', 'SpelOperations.compare(yes, no) < 0', 'bool'),
  (_full, '#yes and #no', 'yes && no', 'bool'),
  (_full, '#yes or #no and #yes', 'yes || no && yes', 'bool'),
  (_full, '(#yes or #no) and #yes', '(yes || no) && yes', 'bool'),
  (
    _full,
    '#maybeBool or #yes',
    'SpelOperations.toBool(maybeBool) || yes',
    'bool',
  ),
  (_full, '!#yes', '!yes', 'bool'),
  (_full, 'not #no', '!no', 'bool'),
  (_full, '!(1 > 2)', '!(1.compareTo(2) > 0)', 'bool'),
  (_full, '!#maybeBool', '!SpelOperations.toBool(maybeBool)', 'bool'),
  (_full, '#yes ? 1 : 2', 'yes ? 1 : 2', 'int'),
  (_full, '#yes ? 1 : null', 'yes ? 1 : null', 'int?'),
  (_full, "#yes ? 'a' : 1", "yes ? 'a' : 1", 'Object'),
  (_full, '#no ? 1 : #yes ? 2 : 3', 'no ? 1 : (yes ? 2 : 3)', 'int'),
  // A conditional as the test of another: Dart's `?:` nests to the right.
  (
    _full,
    '(#yes ? #no : false) ? 1 : 2',
    '(yes ? no : false) ? 1 : 2',
    'int',
  ),
  (_full, '(#yes ? #no : #yes) ? 1 : 2', '(yes ? no : yes) ? 1 : 2', 'int'),
  (
    _full,
    "(#yes ? 'a' : 'b') == 'a' ? 1 : 2",
    "(yes ? 'a' : 'b') == 'a' ? 1 : 2",
    'int',
  ),
  (
    _full,
    "(#maybeBool ?: #yes) ? 'Y' : 'N'",
    "maybeBool ?? yes ? 'Y' : 'N'",
    'String',
  ),
  // In the middle a conditional is unambiguous, and so is `??` as a test.
  (_full, '#yes ? (#no ? 1 : 2) : 3', 'yes ? no ? 1 : 2 : 3', 'int'),
  (_full, '!(#yes ? #no : #yes)', '!(yes ? no : yes)', 'bool'),
  (
    _full,
    '(#yes ? #no : #yes) and #yes',
    '(yes ? no : yes) && yes',
    'bool',
  ),
  (_full, '(#yes ? 1 : 2) + 1', '(yes ? 1 : 2) + 1', 'int'),
  (
    _full,
    "#nothing ?: 'dflt'",
    "(switch (nothing) { null || '' => 'dflt', final text? => text })",
    'String',
  ),
  (
    _full,
    "#name ?: 'dflt'",
    "(switch (name) { '' => 'dflt', final text => text })",
    'String',
  ),
  (_full, '#book.sequel ?: #book', 'book.sequel ?? book', 'Book'),
  (_full, '#maybeInt ?: 0', 'maybeInt ?? 0', 'int'),
  (_full, '#someInt ?: 0', 'someInt ?? 0', 'int'),
  // What the caller's code for a variable is kept as.
  (_arguments, '#book.title', '(a[0] as Book).title', 'String'),
  (_arguments, 'year + 1', '(a[0] as Book).year + 1', 'int'),
  (_arguments, '#book?.title', '(a[0] as Book).title', 'String'),
  (_indexed, '#book.title', 'a[0].title', 'String'),
  (_indexed, '#book.sequel?.title', 'a[0].sequel?.title', 'String?'),
  (_called, '#book.title', 'list.first().title', 'String'),
  (_composite, '#book.title', '(c == 1 ? a : b).title', 'String'),
  (
    _composite,
    '#book == #ghost',
    'SpelOperations.equals(c == 1 ? a : b, ghost)',
    'bool',
  ),
  // The environment as a parameter: the interpreter's methods, with the
  // default as a named argument.
  (
    _environmentOnly,
    "@environment.getProperty('app.name')",
    "environment.getProperty('app.name')",
    'String?',
  ),
  (
    _environmentOnly,
    "@environment.getProperty('x', 'dflt')",
    "environment.getProperty('x', defaultValue: 'dflt')",
    'String?',
  ),
  (
    _environmentOnly,
    "@environment.getProperty('x', #nothing)",
    "environment.getProperty('x', defaultValue: nothing)",
    'String?',
  ),
  (
    _environmentOnly,
    "@environment.getRequiredProperty('app.name')",
    "environment.getRequiredProperty('app.name')",
    'String',
  ),
  (
    _environmentOnly,
    "@environment.containsProperty('app.name')",
    "environment.containsProperty('app.name')",
    'bool',
  ),
  (
    _environmentOnly,
    "@environment.getProperty('app.name') ?: 'none'",
    "(switch (environment.getProperty('app.name')) { null || '' => 'none', "
        'final text? => text })',
    'String',
  ),
  (_environmentOnly, '@environment', 'environment', 'Object'),
];

// Messages the build reports: (scope, expression, parts of the problems).
const _problems = <(String, String, List<String>)>[
  (
    _full,
    '#book.titel',
    [
      "No property 'titel' on type 'Book'; did you mean 'title'?",
      'Available properties: author, boom, counts, label,',
    ],
  ),
  (
    _full,
    'titel',
    ["No property 'titel' on type 'Book'; did you mean 'title'?"],
  ),
  (
    _full,
    '#book.author?.nam',
    ["No property 'nam' on type 'Author'; did you mean 'name'?"],
  ),
  (
    _full,
    '#names.lenght',
    ["No property 'lenght' on type 'List<String>'; did you mean 'length'?"],
  ),
  (
    _full,
    '#book.gret(1)',
    ["No method 'gret' on type 'Book'; did you mean 'greet'?"],
  ),
  (
    _full,
    '#book.zzzzzz',
    [
      "No property 'zzzzzz' on type 'Book'. Available properties:",
    ],
  ),
  (
    _full,
    '#book.greet()',
    ["Method 'Book.greet' takes 1 argument, but 0 were given"],
  ),
  (
    _full,
    "#book.greet('a', 'b')",
    ["Method 'Book.greet' takes 1 argument, but 2 were given"],
  ),
  (
    _full,
    '#book.repeatWord()',
    [
      "Method 'Book.repeatWord' takes between 1 and 2 arguments",
      'but 0 were given',
    ],
  ),
  (
    _full,
    '#bok.title',
    ["Unknown variable '#bok'; did you mean '#book'?", 'Available variables:'],
  ),
  (
    _full,
    '@catlog.size',
    [
      "No bean named 'catlog'; did you mean 'catalog'?",
      'Available beans: catalog, environment.',
    ],
  ),
  (
    _full,
    '#ghost.title',
    ["Cannot read property 'title' on Book?, which can be null: use ?."],
  ),
  (
    _full,
    "#ghost.greet('x')",
    ["Cannot call method 'greet' on Book?, which can be null: use ?."],
  ),
  (
    _full,
    '#book.author.name',
    ["Cannot read property 'name' on Author?, which can be null"],
  ),
  (
    _full,
    '#book.subtitle.length',
    ["Cannot read property 'length' on String?, which can be null"],
  ),
  (
    _full,
    '#maybeNames[0]',
    ['Cannot index on List<String>?, which can be null'],
  ),
  (
    _full,
    '#maybeScores[ada]',
    ['Cannot index on Map<String, int>?, which can be null'],
  ),
  (
    _full,
    'title()',
    ["'title' is a property of Book, not a method; read it without ()"],
  ),
  (
    _full,
    'greet',
    ["'greet' is a method of Book, not a property; call it as greet(...)"],
  ),
  (
    _full,
    '#book.touch()',
    ["Method 'Book.touch' returns void: it has no value"],
  ),
  (_full, 'null.length', ["Cannot read property 'length' on null"]),
  (_full, '1 +', ['Invalid expression: EL1042E']),
  (_bare, 'title', ["Property 'title' needs a root object"]),
  (_bare, "greet('x')", ["Method 'greet' needs a root object"]),
  (_bare, '#root', ["'#root' needs a root object"]),
  (_bare, '#this', ["'#this' needs a root object"]),
  (_bare, '[0]', ['Indexing needs a root object']),
  // Every problem is reported, and they win over `unsupported`.
  (
    _full,
    '#book.titel + #book.yeer',
    [
      "No property 'titel' on type 'Book'; did you mean 'title'?",
      "No property 'yeer' on type 'Book'; did you mean 'year'?",
    ],
  ),
  (
    _full,
    '#book.titel + T(Math).PI',
    ["No property 'titel' on type 'Book'; did you mean 'title'?"],
  ),
  (
    _full,
    '@environment.nothing',
    ["No property 'nothing' on type 'ConfigurableEnvironment'. Available"],
  ),
  (
    _environmentOnly,
    '@environment.getProperty()',
    [
      "Method '@environment.getProperty' takes one or two arguments",
      'but 0 were given',
    ],
  ),
  (
    _environmentOnly,
    "@environment.getRequiredProperty('a', 'b')",
    ["Method '@environment.getRequiredProperty' takes 1 argument, but 2 were"],
  ),
  (
    _environmentOnly,
    "@environment.getPropery('a')",
    [
      "No method 'getPropery' on @environment; did you mean 'getProperty'?",
      'Available methods: containsProperty,',
    ],
  ),
];

// What stays with the interpreter: (scope, expression, the construct).
const _unsupported = <(String, String, String)>[
  (_full, 'T(Math).PI', 'T(Math)'),
  (_full, "new String('x')", 'new String'),
  (_full, "#names.?[#this == 'a']", 'selection'),
  (_full, '#names.![length]', 'projection'),
  (_full, '{1, 2}', 'inline list'),
  (_full, '{a: 1}', 'inline map'),
  (_full, "#book.title matches 'D.*'", 'matches'),
  (_full, '#book instanceof T(Book)', 'instanceof'),
  (_full, '1 between {0, 2}', 'between'),
  (_full, '#count = 3', 'assignment'),
  (_full, '#count++', '++ and --'),
  (_full, '#fn(1)', 'function call #fn'),
  (_full, '&catalog', 'factory bean reference &catalog'),
  (_full, '#opaque.length', "property 'length' of a value of type Object?"),
  (_full, '#opaque[0]', 'index of a value of type Object?'),
  // An unquoted name indexing a value of an unknown type may be a map's
  // key: not a property of the root, so not a problem.
  (_full, '#opaque[address]', 'index of a value of type Object?'),
  (_full, '#filter[address][city]', 'index of a value of type Object?'),
  (_full, '#filter[tags][first]', 'index of a value of type Object?'),
  (_full, '#scores.ada', "property 'ada' of a Map"),
  (_full, '#names.size()', "Java-style method 'size()'"),
  (_full, '#names.length()', "Java-style method 'length()'"),
  (_full, "#name.equals('x')", "Java-style method 'equals()'"),
  (_full, '#name.isBlank()', "Java-style method 'isBlank()'"),
  (_full, '#book.hashCode()', "Java-style method 'hashCode()'"),
  (_full, '#names.first()', "Java-style method 'first()'"),
  (_full, '#name.size', "Java-style property 'size'"),
  (_full, '#names.take(1)', "method 'take'"),
  (_full, "#names.add('x')", "method 'add'"),
  (_full, "'ab' * 2", '* on String and int'),
  (_full, "'d' - 3", '- on String and int'),
  (_full, '#maybeInt + 1', '+ on int? and int'),
  (_full, '#someInt * 2', '* on int? and int'),
  (_full, '#opaque + 1', '+ on Object? and int'),
  (_full, '#yes ? 1 : 2.5', 'a conditional with a double'),
  (_full, '#maybeInt ?: 2.5', 'an elvis with a double'),
  (_full, '#name.substring(#ratio)', "argument 1 of 'substring'"),
  (_full, "#name.padLeft('x')", "argument 1 of 'padLeft'"),
  (_full, '#names[#name]', 'index of type String into List<String>'),
  (_noBeans, '@catalog.size', 'bean reference @catalog'),
  (_environmentOnly, "@environment['app.name']", 'index into @environment'),
  // The interpreter's builtins know the members of every object.
  (
    _environmentOnly,
    '@environment.toString()',
    "Java-style method 'toString()' of @environment",
  ),
  (
    _environmentOnly,
    '@environment.hashCode()',
    "Java-style method 'hashCode()' of @environment",
  ),
  (
    _environmentOnly,
    "@environment.equals('x')",
    "Java-style method 'equals()' of @environment",
  ),
  (_environmentOnly, '@environment.name', "property 'name' of @environment"),
  (
    _environmentOnly,
    '@environment.getActiveProfiles()',
    '@environment.getActiveProfiles()',
  ),
  (
    _environmentOnly,
    '@environment.getProperty(1)',
    "argument 1 of '@environment.getProperty'",
  ),
  (_environmentOnly, '@catalog.size', 'bean reference @catalog'),
];

// What the code gives, compared with what the interpreter gives; all of
// them compile in the `full` scope.
const _equivalent = <String>[
  // Literals.
  "'abc'",
  '"x y"',
  "'it''s'",
  r"'a$b'",
  r"'back\slash'",
  "'é'",
  '42',
  '-5',
  '+5',
  '3.14',
  '1e3',
  '2d',
  '0x1F',
  'true',
  'FALSE',
  'null',
  // Variables, `#root` and `#this`.
  '#count',
  '#name',
  '#ghost',
  '#numbers',
  '#root.title',
  '#this.title',
  '#book.title',
  "#this.greet('x')",
  // Properties.
  'title',
  'year',
  'label',
  'published',
  'rating',
  'price',
  'author?.name',
  'author?.country',
  'author?.country?.length',
  'author?.mentor?.name',
  'author?.mentor?.country',
  '#book.author?.name',
  '#ghost?.title',
  '#ghost?.title?.length',
  '#ghost?.author?.name',
  'sequel?.title',
  'sequel?.author?.name',
  '#maybeBook?.title',
  'tags.length',
  'tags.first',
  'tags.last',
  'tags.isEmpty',
  'tags.isNotEmpty',
  '#names.length',
  '#name.length',
  '#name.isEmpty',
  '#empty.isEmpty',
  '#empty.isNotEmpty',
  'status.name',
  'status.index',
  '#ratio.isNegative',
  '#negative.isNegative',
  '#count.sign',
  '#negative.sign',
  // Methods.
  "greet('Ada')",
  '#book.greet(#name)',
  'greet(title)',
  "repeatWord('ab')",
  "repeatWord('ab', 3)",
  'plus(2)',
  'plus(#count)',
  'scale(2)',
  'scale(#ratio)',
  "withTitle('Other').title",
  'author?.shout()',
  '#ghost?.explode()',
  "#book.greet('x').length",
  '#name.toUpperCase()',
  '#name.toLowerCase()',
  '#name.substring(1)',
  '#name.substring(0, 2)',
  "'abc'.substring(1, 2)",
  "#name.startsWith('A')",
  "#name.endsWith('x')",
  "#name.contains('d')",
  "#name.indexOf('d')",
  "#name.replaceAll('d', 'x')",
  "'  pad '.trim()",
  '#name.padLeft(5)',
  "#name.padRight(5, '.')",
  "#name.compareTo('B')",
  "#names.contains('a')",
  "#names.indexOf('b')",
  "#names.join('-')",
  '#names.join()',
  '#numbers.sublist(1)',
  '#names.elementAt(1)',
  '#numbers.toList()',
  "#scores.containsKey('ada')",
  "#scores.containsKey('x')",
  '#scores.containsValue(10)',
  '#count.toString()',
  '#ratio.toString()',
  '#whole.toString()',
  '#book.status.toString()',
  '#count.abs()',
  '#negative.abs()',
  '#ratio.round()',
  '#ratio.floor()',
  '#ratio.ceil()',
  '#ratio.toStringAsFixed(1)',
  '#count.compareTo(5)',
  '#count.toDouble()',
  '#ratio.toInt()',
  // Receivers that need parentheses.
  "(#big + 'y').length",
  "(#yes ? #name : 'x').length",
  '(1 + 2).toString()',
  '(-5).abs()',
  // The scope of arguments, of an index and of a chain.
  'sequel?.greet(title)',
  '#maybeBook?.greet(title)',
  'tags[year - 1964]',
  '#names[year - 1964]',
  'sequel?.counts?.[title]',
  // Beans.
  "@catalog.lookup('x')",
  '@catalog.size',
  '@catalog.first().title',
  '@catalog.first()?.title',
  '@catalog.first().tags.length',
  "@environment.getProperty('app.name')",
  "@environment.getProperty('missing')",
  "@environment.getProperty('app.name')?.length",
  "@environment.getProperty('missing')?.length",
  // Indexing.
  '#names[0]',
  '#names[2]',
  '#names[#count - 6]',
  '#numbers[1] + #numbers[2]',
  "#scores['ada']",
  "#scores['x']",
  '#scores[ada]',
  '#scores[x]',
  '#name[0]',
  '#name[1]',
  'tags[0]',
  'tags[1].length',
  "counts['a']",
  "counts['b'] == 2",
  '#maybeNames?.[0]',
  '#someNames?.[1]',
  "#maybeBook?.counts?.['x']",
  // Arithmetic.
  '1 + 2',
  '7 - 10',
  '3 * 4',
  '7 / 2',
  '-7 / 2',
  '7 % 3',
  '-7 % 3',
  '2 ^ 10',
  '2 ^ -1',
  '2 ^ 100',
  '2 ^ 0.5',
  '7.0 / 2',
  '7 / 2.0',
  '7.5 % 2',
  '1.5 + 1',
  '1 + 1.5',
  '#count * 2',
  '#count / 2',
  '#count / 0',
  '#count % 0',
  '#zero / #count',
  '#negative / 2',
  '#negative % 3',
  '#ratio * 2',
  '#ratio / 2',
  '#ratio / 0',
  '#ratio % 2',
  '#ratio ^ 2',
  '#whole / 2',
  '#whole + 1',
  '#count + #ratio',
  '#count / #ratio',
  '#zeroD / #zeroD',
  '#anyNum / 2',
  '#anyNum + 1',
  '#anyNum % 2',
  '#anyNum ^ 2',
  '#count ^ 2',
  '1 + 2 * 3',
  '(1 + 2) * 3',
  '10 - 2 - 3',
  '10 - (2 - 3)',
  '2 * 3 + 4 * 5',
  '(#count + 1) / 2',
  '-#count',
  '-#ratio',
  '+#count',
  '-(-3)',
  'year + 1',
  'year - 1900',
  'rating * 2',
  'rating / 2',
  'rating + year',
  'price + 1',
  'price / 2',
  'price * rating',
  // Text.
  "'a' + 'b'",
  "'a' + 1",
  "1 + 'a'",
  "'a' + null",
  "null + 'a'",
  "'a' + 1.5",
  "'a' + true",
  "'a' + #names",
  "#name + '!'",
  "'x' + #nothing",
  "#nothing + 'x'",
  "'n=' + #count",
  "'n=' + #whole",
  "'n=' + #ratio",
  "title + ' (' + year + ')'",
  "'a' + 'b' + 'c'",
  "1 + 2 + 'a'",
  "'a' + 1 + 2",
  '#big + #big',
  // Equality.
  '1 == 1',
  '1 == 1.0',
  '1 != 2',
  "'a' == 'a'",
  "'a' == 'b'",
  'null == null',
  'null == 1',
  '#nothing == null',
  '#ghost == null',
  '#ghost != null',
  "#name == 'Ada'",
  "#name eq 'Ada'",
  "#name ne 'Ada'",
  "'Dune' == title",
  '#count == #ratio',
  '#zeroD == #zeroD',
  '(#zeroD / #zeroD) == (#zeroD / #zeroD)',
  '#numbers == #numbers',
  '#names == #names',
  '#names == #numbers',
  '#book == #book',
  '#book == #ghost',
  '#book != #ghost',
  '#status == status',
  '#yes == #no',
  '#yes == true',
  '#maybeInt == 5',
  '#someInt == 5',
  '#maybeInt == #someInt',
  "#count == 'a'",
  '#name == 1',
  // Order.
  '1 < 2',
  '2 <= 2',
  '3 > 2',
  '3 >= 4',
  '1 lt 2',
  '1 le 1',
  '1 gt 2',
  '1 ge 2',
  '1 < 1.5',
  "'a' < 'b'",
  "'b' < 'a'",
  "'a' < 'B'",
  '#maybeInt < 1',
  '1 < #maybeInt',
  '#someInt > 4',
  '#maybeInt >= #someInt',
  "#nothing < 'a'",
  "'a' > #nothing",
  '#nothing < #nothing',
  '#yes < #no',
  '#no < #yes',
  '#status < status',
  '#status <= status',
  '#ratio > 2',
  '#ratio >= 2.5',
  'year > 1900',
  'year < 2000 && year > 1900',
  '(#zeroD / #zeroD) < 1',
  '1 < (#zeroD / #zeroD)',
  "#count < 'a'",
  '#numbers < #numbers',
  '#book < #book',
  // Logic.
  'true and false',
  'true or false',
  '#yes and #no',
  '#yes && #yes',
  '#no || #yes',
  '!#yes',
  'not #no',
  '!(1 > 2)',
  '!!#yes',
  '1 > 0 and 2 > 1 or false',
  'true or false and false',
  '#yes or #maybeBool',
  '#no and #maybeBool',
  '#no or #maybeBool',
  '#maybeBool and #yes',
  '!#maybeBool',
  "'true' and #yes",
  "'x' and #yes",
  '#name and #yes',
  "#count > 5 and #name == 'Ada'",
  "#count > 5 or #name == 'Bob'",
  '#yes and #no or #yes',
  // Conditional and Elvis.
  '#yes ? 1 : 2',
  "#no ? 'a' : 'b'",
  "#count > 5 ? 'big' : 'small'",
  '#yes ? 1 : null',
  "#yes ? 'a' : 1",
  '#maybeBool ? 1 : 2',
  "'true' ? 1 : 2",
  '#yes ? #yes ? 1 : 2 : 3',
  '#no ? 1 : #yes ? 2 : 3',
  '(#yes ? 1 : 2) + 1',
  "#book.greet(#yes ? 'a' : 'b')",
  "title == 'Dune' ? year + 1 : 0",
  "#nothing ?: 'dflt'",
  "#blank ?: 'dflt'",
  "#name ?: 'dflt'",
  "#empty ?: 'dflt'",
  "#ghost?.title ?: 'none'",
  'subtitle ?: title',
  "author?.country ?: 'unknown'",
  '#someInt ?: 0',
  '#maybeInt ?: 0',
  '#ghost ?: #book',
  '#maybeBook ?: #book',
  "#nothing ?: #blank ?: 'z'",
  "(#nothing ?: 'a').length",
  // Conditionals and Elvis inside one another, in every position: Dart's
  // `?:` nests to the right, SpEL's by what the parentheses say.
  '(#yes ? #no : false) ? 1 : 2',
  '(#no ? #yes : #yes) ? 1 : 2',
  '(#yes ? #yes : false) ? (#no ? 1 : 2) : (#yes ? 3 : 4)',
  "(#yes ? 'a' : 'b') == 'a' ? 1 : 2",
  '#yes ? (#no ? 1 : 2) : 3',
  '#no ? 1 : (#no ? 2 : 3)',
  '#yes ? 1 : #no ? 2 : #yes ? 3 : 4',
  '#no ? 1 : #no ? 2 : #yes ? 3 : 4',
  "(#count > 5 ? 1 : 2) > 1 ? 'big' : 'small'",
  "(#maybeBool ?: #yes) ? 'Y' : 'N'",
  "(#maybeBool ?: #no) ? 'Y' : 'N'",
  "(#nothing ?: #name) == 'Ada' ? 1 : 2",
  "#yes ? #nothing ?: 'x' : 'y'",
  "#no ? 'x' : #nothing ?: 'y'",
  "(#yes ? #nothing : 'y') ?: 'z'",
  "(#no ? 'x' : #nothing) ?: (#yes ? 'a' : 'b')",
  "#nothing ?: (#yes ? 'a' : 'b')",
  '!(#yes ? #no : #yes)',
  '(#yes ? #no : #yes) and #yes',
  '#yes and (#yes ? #no : #yes)',
  '(#yes ? #no : #yes) or (#no ? #yes : #no)',
  '-(#yes ? 1 : 2)',
  "(#yes ? 'a' : 'b') + 'c'",
  '(#count > 5 ? 1 : 2) * (#yes ? 3 : 4)',
  '#count - (#yes ? 1 : 2)',
  '(#yes ? #count : 0) / 2',
  // Errors the code raises.
  '#names[3]',
  '#names[-1]',
  '#numbers[#count]',
  '#name[9]',
  '#name[-1]',
  '#book.explode()',
  'explode()',
];

// The same, for `@environment` given as code (the `environmentOnly` scope).
const _environmentEquivalent = <String>[
  "@environment.getProperty('app.name')",
  "@environment.getProperty('missing')",
  "@environment.getProperty('missing', 'dflt')",
  "@environment.getProperty('app.name', 'dflt')",
  "@environment.getProperty('missing', #nothing)",
  "@environment.getProperty('app.name')?.length",
  "@environment.getProperty('missing') ?: 'none'",
  "@environment.getRequiredProperty('app.name')",
  "@environment.getRequiredProperty('missing')",
  "@environment.containsProperty('app.name')",
  "@environment.containsProperty('missing')",
  r"@environment.resolvePlaceholders('Hi ${app.name}')",
  r"@environment.resolvePlaceholders('Hi ${missing}')",
  r"@environment.resolveRequiredPlaceholders('Hi ${app.name}')",
  r"@environment.resolveRequiredPlaceholders('Hi ${missing}')",
  "@environment.getProperty('app.name') + '!'",
  "@environment.getProperty('app.name') == 'demo'",
];

// Results known in advance, so that the comparison with the interpreter
// cannot pass with both sides wrong the same way.
const _known = <String, String>{
  '#count / 2': 'int|3',
  '-7 / 2': 'int|-3',
  '7.0 / 2': 'double|3.5',
  '-7 % 3': 'int|-1',
  '2 ^ 100': 'int|9223372036854775807',
  '#count / 0': 'dart|UnsupportedError|Unsupported operation: / by zero',
  '1 == 1.0': 'bool|true',
  '#names == #numbers': 'bool|false',
  '#maybeInt < 1': 'bool|true',
  '1 < (#zeroD / #zeroD)': 'bool|true',
  "'a' + null": 'String|anull',
  "'n=' + #whole": 'String|n=7.0',
  "#nothing ?: 'dflt'": 'String|dflt',
  '#ghost?.title': 'Null|null',
  'sequel?.greet(title)': 'String|Hello Dune from Dune Messiah',
  '#names[year - 1964]': 'String|b',
  '#no or #maybeBool':
      'spel|typeConversionError|'
      'EL1001E: Type conversion problem, cannot convert from null to bool',
  "#count < 'a'":
      'spel|notComparable|EL1013E: Cannot compare instances of int and String',
  '#names[3]':
      'spel|collectionIndexOutOfBounds|'
      "EL1025E: The collection has '3' elements, index '3' is invalid",
  '#book.explode()': 'dart|StateError|Bad state: explode',
};

// Where the code differs from the interpreter on purpose: the expression
// and what each says (a start of the outcome).
//
// Not here, because the VM does not show it: a `double` variable or property
// that holds an integral value. The code follows the static type, as Java
// does (`'n=' + #whole` is `n=7.0`, see the `_known` row), and so does the
// interpreter on the VM; on the web the interpreter finds an `int` in the
// variable and says `n=7`.
const _differences = <(String, String, String)>[
  // A getter that throws: the interpreter wraps the error (EL1021E).
  (
    '#book.boom',
    'dart|StateError|Bad state: boom',
    'spel|exceptionDuringPropertyRead|',
  ),
  (
    'boom',
    'dart|StateError|Bad state: boom',
    'spel|exceptionDuringPropertyRead|',
  ),
  (
    '#book.related.first.boom',
    'dart|StateError|Bad state: boom',
    'spel|exceptionDuringPropertyRead|',
  ),
];

final _parser = SpelExpressionParser();

// ---------------------------------------------------------------------------
// Compiling
// ---------------------------------------------------------------------------

// One compiled expression: `code` and `type`, or `construct` (unsupported),
// or `problems`.
final class _Result {
  const _Result({this.code, this.type, this.construct, this.problems});

  final String? code;
  final String? type;
  final String? construct;
  final List<String>? problems;

  @override
  String toString() => code != null
      ? '$code : $type'
      : construct != null
      ? 'unsupported $construct'
      : 'problems $problems';
}

// The code as text: formatted, on one line, without trailing commas.
String _flat(String code) => code
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(', )', ')')
    .replaceAll(', }', ' }')
    .trim();

String _show(Expression expression) {
  final source = expression.accept(DartEmitter(useNullSafetySyntax: true));
  final formatted = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  ).formatStatement('x = $source;');
  return _flat(formatted.replaceFirst('x =', '').replaceFirst(';', ''));
}

// The key of a compiled expression in the results.
String _key(String scope, String expression) => '$scope\n$expression';

// Compiles every expression of the tables in one analysis of the fixture.
Future<Map<String, _Result>> _compileAll() async {
  final packageRoot = await _packageRoot();
  final source = File('$packageRoot/test/support/spel_fixture.dart')
      .readAsStringSync();
  final requests = <(String, String)>{
    for (final (scope, expression, _, _) in _emitted) (scope, expression),
    for (final (scope, expression, _) in _problems) (scope, expression),
    for (final (scope, expression, _) in _unsupported) (scope, expression),
    for (final expression in _equivalent) (_full, expression),
    for (final expression in _environmentEquivalent)
      (_environmentOnly, expression),
    for (final (expression, _, _) in _differences) (_full, expression),
  };
  return await resolveSources<Map<String, _Result>>(
    {'pkg|lib/fixture.dart': source},
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/fixture.dart'),
      );
      final scopes = _scopes(library);
      final results = <String, _Result>{};
      for (final (scope, expression) in requests) {
        results[_key(scope, expression)] = switch (compileSpel(
          expression,
          scopes[scope]!,
        )) {
          SpelCompiled(:final code, :final type) => _Result(
            code: _show(code),
            type: type.getDisplayString(),
          ),
          SpelUnsupported(:final construct) => _Result(construct: construct),
          SpelInvalid(:final problems) => _Result(
            problems: [for (final problem in problems) problem.message],
          ),
        };
      }
      return results;
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/fixture.dart',
    readAllSourcesFromFilesystem: true,
  );
}

Map<String, SpelScope> _scopes(LibraryElement library) {
  SpelBinding bind(String name) {
    final variable = library.topLevelVariables.firstWhere(
      (v) => v.name == name,
    );
    return SpelBinding(variable.type, refer(name));
  }

  final variables = {for (final name in _variables) name: bind(name)};
  SpelBinding? bean(String name) =>
      const {'catalog', 'environment'}.contains(name) ? bind(name) : null;
  // `#book` from the first argument, as `a[0] as Book`.
  final book = SpelBinding(
    bind('book').type,
    refer('a').index(literalNum(0)).asA(refer('Book')),
  );
  return {
    _full: SpelScope(
      library: library,
      variables: variables,
      root: bind('book'),
      beans: bean,
      beanNames: const ['catalog', 'environment'],
    ),
    _arguments: SpelScope(
      library: library,
      variables: {'book': book},
      root: book,
    ),
    _indexed: SpelScope(
      library: library,
      variables: {
        'book': SpelBinding(
          bind('book').type,
          refer('a').index(literalNum(0)),
        ),
      },
    ),
    _called: SpelScope(
      library: library,
      variables: {
        'book': SpelBinding(
          bind('book').type,
          refer('list').property('first').call([]),
        ),
      },
    ),
    _composite: SpelScope(
      library: library,
      variables: {
        'book': SpelBinding(
          bind('book').type,
          refer('c').equalTo(literalNum(1)).conditional(refer('a'), refer('b')),
        ),
        'ghost': bind('ghost'),
      },
    ),
    _bare: SpelScope(library: library, variables: {'book': bind('book')}),
    _noBeans: SpelScope(
      library: library,
      variables: variables,
      root: bind('book'),
    ),
    _environmentOnly: SpelScope(
      library: library,
      variables: variables,
      root: bind('book'),
      environment: refer('environment'),
    ),
  };
}

Future<String> _packageRoot() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse(
      'package:spring_core_dart_generator/spring_core_dart_generator.dart',
    ),
  );
  return File.fromUri(library!).parent.parent.path;
}

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

// The outcome of each of [expressions] when its compiled code runs in a
// program of its own, in the order given.
Future<List<String>> _runCompiled(
  List<String> expressions,
  Map<String, _Result> results, [
  String scope = _full,
]) async {
  final unavailable = [
    for (final expression in expressions)
      if (results[_key(scope, expression)]?.code == null)
        '$expression: ${results[_key(scope, expression)]}',
  ];
  if (unavailable.isNotEmpty) {
    fail('Not compiled:\n${unavailable.join('\n')}');
  }
  final root = await _packageRoot();
  final directory = Directory.systemTemp.createTempSync('spel_compiler_test');
  try {
    File(
      '$root/test/support/spel_fixture.dart',
    ).copySync('${directory.path}/fixture.dart');
    final program = StringBuffer()
      ..writeln("import 'dart:convert';")
      ..writeln("import 'package:spring_core_dart/spring_core_dart.dart';")
      ..writeln("import 'fixture.dart';")
      ..writeln('void main() {')
      ..writeln('  print(jsonEncode(<String>[');
    for (final expression in expressions) {
      program.writeln(
        '    outcomeOf(() => ${results[_key(scope, expression)]!.code}),',
      );
    }
    program.writeln('  ]));\n}');
    final main = File('${directory.path}/main.dart')
      ..writeAsStringSync(program.toString());
    final config = (await Isolate.packageConfig)!.toFilePath();
    final run = await Process.run(Platform.resolvedExecutable, [
      '--packages=$config',
      main.path,
    ]);
    if (run.exitCode != 0) {
      fail('The compiled program failed:\n${run.stdout}\n${run.stderr}');
    }
    return (jsonDecode((run.stdout as String).trim()) as List<Object?>)
        .cast<String>();
  } finally {
    directory.deleteSync(recursive: true);
  }
}

String _interpreted(String expression) => fixture.outcomeOf(
  () => _parser
      .parseExpression(expression)
      .getValue(fixture.interpreterContext()),
);

void main() {
  late Map<String, _Result> results;

  setUpAll(() async {
    results = await _compileAll();
  });

  group('the code written', () {
    for (final (scope, expression, code, type) in _emitted) {
      test('[$scope] $expression', () {
        final result = results[_key(scope, expression)]!;
        expect(result.code, isNotNull, reason: '$result');
        expect(result.code, _flat(code));
        expect(result.type, type);
      });
    }
  });

  group('problems', () {
    for (final (scope, expression, parts) in _problems) {
      test('[$scope] $expression', () {
        final result = results[_key(scope, expression)]!;
        expect(result.problems, isNotNull, reason: '$result');
        final text = result.problems!.join('\n');
        for (final part in parts) {
          expect(text, contains(part));
        }
      });
    }

    test('are reported with the offset of the member', () async {
      // `#book.titel`: `titel` starts at offset 6.
      final packageRoot = await _packageRoot();
      final source = File(
        '$packageRoot/test/support/spel_fixture.dart',
      ).readAsStringSync();
      final positions = await resolveSources<List<int>>(
        {'pkg|lib/fixture.dart': source},
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId('pkg', 'lib/fixture.dart'),
          );
          final scope = _scopes(library)[_full]!;
          return [
            for (final expression in [
              '#book.titel',
              '#bok.title',
              '1 + #book.yeer',
            ])
              (compileSpel(
                expression,
                scope,
              ) as SpelInvalid).problems.first.position,
          ];
        },
        rootPackage: 'pkg',
        resolverFor: 'pkg|lib/fixture.dart',
        readAllSourcesFromFilesystem: true,
      );
      expect(positions, [6, 0, 10]);
    });
  });

  group('left to the interpreter', () {
    for (final (scope, expression, construct) in _unsupported) {
      test('[$scope] $expression', () {
        final result = results[_key(scope, expression)]!;
        expect(result.construct, isNotNull, reason: '$result');
        expect(result.construct, contains(construct));
      });
    }
  });

  group("compiled code gives the interpreter's results", () {
    late List<String> compiled;

    setUpAll(() async {
      compiled = await _runCompiled(_equivalent, results);
    });

    for (final (index, expression) in _equivalent.indexed) {
      test(expression, () {
        expect(compiled[index], _interpreted(expression));
      });
    }

    for (final MapEntry(key: expression, value: outcome) in _known.entries) {
      test('$expression is $outcome', () {
        expect(compiled[_equivalent.indexOf(expression)], outcome);
      });
    }
  }, tags: 'integration');

  group("compiled @environment gives the interpreter's results", () {
    late List<String> compiled;

    setUpAll(() async {
      compiled = await _runCompiled(
        _environmentEquivalent,
        results,
        _environmentOnly,
      );
    });

    for (final (index, expression) in _environmentEquivalent.indexed) {
      test(expression, () {
        expect(compiled[index], _interpreted(expression));
      });
    }

    test('a default is used for a missing property only', () {
      expect(
        compiled[_environmentEquivalent.indexOf(
          "@environment.getProperty('missing', 'dflt')",
        )],
        'String|dflt',
      );
      expect(
        compiled[_environmentEquivalent.indexOf(
          "@environment.getProperty('app.name', 'dflt')",
        )],
        'String|demo',
      );
    });
  }, tags: 'integration');

  group('compiled code differs from the interpreter', () {
    late List<String> compiled;

    setUpAll(() async {
      compiled = await _runCompiled([
        for (final (expression, _, _) in _differences) expression,
      ], results);
    });

    for (final (index, (expression, mine, theirs)) in _differences.indexed) {
      test(expression, () {
        expect(compiled[index], startsWith(mine));
        expect(_interpreted(expression), startsWith(theirs));
      });
    }
  }, tags: 'integration');
}
