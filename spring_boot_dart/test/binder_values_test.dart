import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

// The binder on its own: @DefaultValue and missing constructor parameters,
// read-only collections, @RawValue, enum spellings and hand-written
// introspections without type information.

enum Level { off, low, high }

enum Switch { on, standby }

class Inner {
  const Inner([this.count = 3]);
  final int count;
}

class Pool {
  const Pool(
    this.name,
    this.tags,
    this.ids,
    this.level,
    this.timeout,
    this.extra,
    this.headers,
    this.inner,
  );
  final String name;
  final List<String> tags;
  final Set<int> ids;
  final Level level;
  final Duration timeout;
  final Object? extra;
  final Map<String, String> headers;
  final Inner inner;
}

class Needy {
  const Needy(this.name, this.names, this.level);
  final String name;
  final List<String> names;
  final Level level;
}

class Holder {
  final Set<String> ids = {};
  final Map<String, String> map = {};
  final List<String> frozen = List.unmodifiable(<String>[]);
  String raw = '';
  String cooked = '';
  int port = 0;
  Level level = Level.low;
  Switch toggle = Switch.standby;
}

BeanProperty<T> _read<T extends Object>(
  String name,
  TypeInfo<Object?>? info,
  Type type,
  Object? Function(T) get, [
  void Function(T, Object?)? set,
  List<Object> annotations = const [],
]) => BeanProperty<T>(
  name,
  type: type,
  typeInfo: info,
  get: get,
  set: set,
  annotations: annotations,
);

final innerIntrospection = BeanIntrospection<Inner>(
  properties: [
    _read<Inner>('count', const ClassType<int>(), int, (b) => b.count),
  ],
  constructor: BeanConstructor<Inner>(
    parameters: const [BeanParameter('count', type: ClassType<int>())],
    create: (positional, named) =>
        Function.apply(Inner.new, positional, named) as Inner,
  ),
);

final poolIntrospection = BeanIntrospection<Pool>(
  properties: [
    _read<Pool>('name', const ClassType<String>(), String, (b) => b.name),
  ],
  constructor: BeanConstructor<Pool>(
    parameters: const [
      BeanParameter('name', type: ClassType<String>(), isRequired: true),
      BeanParameter(
        'tags',
        type: ListType<String>(ClassType<String>()),
        isRequired: true,
        annotations: [
          DefaultValue(['a', 'b']),
        ],
      ),
      BeanParameter(
        'ids',
        type: SetType<int>(ClassType<int>()),
        isRequired: true,
        annotations: [DefaultValue('1,2')],
      ),
      BeanParameter(
        'level',
        type: EnumType<Level>(Level.values),
        isRequired: true,
        annotations: [DefaultValue('high')],
      ),
      BeanParameter(
        'timeout',
        type: ClassType<Duration>(),
        isRequired: true,
        annotations: [DefaultValue('5s')],
      ),
      BeanParameter(
        'extra',
        type: DynamicType(),
        isRequired: true,
        annotations: [DefaultValue('x')],
      ),
      BeanParameter(
        'headers',
        type: MapType<String, String>(ClassType<String>(), ClassType<String>()),
        isRequired: true,
        annotations: [DefaultValue()],
      ),
      BeanParameter(
        'inner',
        type: ClassType<Inner>(),
        isRequired: true,
        annotations: [DefaultValue()],
      ),
    ],
    create: (p, n) => Pool(
      p[0]! as String,
      p[1]! as List<String>,
      p[2]! as Set<int>,
      p[3]! as Level,
      p[4]! as Duration,
      p[5],
      p[6]! as Map<String, String>,
      p[7]! as Inner,
    ),
  ),
);

final needyIntrospection = BeanIntrospection<Needy>(
  properties: [
    _read<Needy>('name', const ClassType<String>(), String, (b) => b.name),
  ],
  constructor: BeanConstructor<Needy>(
    parameters: const [
      BeanParameter('name', type: ClassType<String>(), isRequired: true),
      BeanParameter(
        'names',
        type: ListType<String>(ClassType<String>()),
        isRequired: true,
      ),
      BeanParameter(
        'level',
        type: EnumType<Level>(Level.values),
        isRequired: true,
      ),
    ],
    create: (p, n) =>
        Needy(p[0]! as String, p[1]! as List<String>, p[2]! as Level),
  ),
);

final holderIntrospection = BeanIntrospection<Holder>(
  properties: [
    _read<Holder>(
      'ids',
      const SetType<String>(ClassType<String>()),
      Set<String>,
      (b) => b.ids,
    ),
    _read<Holder>(
      'map',
      const MapType<String, String>(ClassType<String>(), ClassType<String>()),
      Map<String, String>,
      (b) => b.map,
    ),
    _read<Holder>(
      'frozen',
      const ListType<String>(ClassType<String>()),
      List<String>,
      (b) => b.frozen,
    ),
    _read<Holder>(
      'raw',
      const ClassType<String>(),
      String,
      (b) => b.raw,
      (b, v) => b.raw = v! as String,
      const [RawValue()],
    ),
    _read<Holder>(
      'cooked',
      const ClassType<String>(),
      String,
      (b) => b.cooked,
      (b, v) => b.cooked = v! as String,
    ),
    // No type information: the hand-written kind.
    _read<Holder>(
      'port',
      null,
      int,
      (b) => b.port,
      (b, v) => b.port = v! as int,
    ),
    _read<Holder>(
      'level',
      const EnumType<Level>(Level.values),
      Level,
      (b) => b.level,
      (b, v) => b.level = v! as Level,
    ),
    _read<Holder>(
      'toggle',
      const EnumType<Switch>(Switch.values),
      Switch,
      (b) => b.toggle,
      (b, v) => b.toggle = v! as Switch,
    ),
  ],
  instantiate: Holder.new,
);

void main() {
  Binder binder(Map<String, Object> properties) => Binder(
    StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(MapPropertySource('test', properties)),
    introspector: BeanIntrospector()
      ..registerAll([
        innerIntrospection,
        poolIntrospection,
        needyIntrospection,
        holderIntrospection,
      ]),
  );

  Holder bindHolder(Map<String, Object> properties) => binder(
    properties,
  ).bind('app', const ClassType<Holder>()).get();

  List<String> errorsOf(void Function() bind) {
    try {
      bind();
    } on ConfigurationPropertiesBindException catch (e) {
      return e.errors;
    }
    fail('binding should have failed');
  }

  group('constructor parameters without a property', () {
    test('get their @DefaultValue by type', () {
      final pool = binder({
        'app.name': 'main',
      }).bind('app', const ClassType<Pool>()).get();
      expect(pool.name, 'main');
      expect(pool.tags, ['a', 'b']);
      expect(pool.ids, {1, 2});
      expect(pool.level, Level.high);
      expect(pool.timeout, const Duration(seconds: 5));
      expect(pool.extra, 'x');
      expect(pool.headers, isEmpty);
      expect(pool.inner.count, 3);
    });

    test('keep the value that is set', () {
      final pool = binder({
        'app.name': 'main',
        'app.tags': 'z',
        'app.level': 'low',
        'app.inner.count': '9',
      }).bind('app', const ClassType<Pool>()).get();
      expect(pool.tags, ['z']);
      expect(pool.level, Level.low);
      expect(pool.inner.count, 9);
    });

    test('a required one without a default is empty for a list, an error '
        'naming the key for an enum', () {
      final errors = errorsOf(
        () => binder({'app.name': 'n'}).bind('app', const ClassType<Needy>()),
      );
      expect(errors.single, contains('app.level'));
      expect(errors.single, contains('required constructor parameter'));
      final needy = binder({
        'app.name': 'n',
        'app.level': 'low',
      }).bind('app', const ClassType<Needy>()).get();
      expect(needy.names, isEmpty);
    });
  });

  group('read-only collections', () {
    test('a set and a map are filled in place', () {
      final holder = bindHolder({'app.ids': 'a,b', 'app.map.k': 'v'});
      expect(holder.ids, {'a', 'b'});
      expect(holder.map, {'k': 'v'});
    });

    test('an unmodifiable list is left as it is', () {
      expect(bindHolder({'app.frozen': 'x'}).frozen, isEmpty);
    });
  });

  group('@RawValue', () {
    test('keeps a placeholder as written, others are resolved', () {
      final holder = bindHolder({
        'app.raw': r'${other}',
        'app.cooked': r'${other}',
        'other': 'resolved',
      });
      expect(holder.raw, r'${other}');
      expect(holder.cooked, 'resolved');
    });
  });

  group('enums', () {
    test('false is the off constant, true the on constant', () {
      expect(bindHolder({'app.level': 'false'}).level, Level.off);
      expect(bindHolder({'app.toggle': 'true'}).toggle, Switch.on);
    });

    test('spellings are relaxed', () {
      expect(bindHolder({'app.level': 'HIGH'}).level, Level.high);
    });

    test('an unknown name lists the allowed ones and names the key', () {
      final errors = errorsOf(() => bindHolder({'app.level': 'loud'}));
      expect(errors.single, contains('app.level'));
      expect(errors.single, contains('off, low, high'));
    });

    test('true without an on constant is an error', () {
      expect(errorsOf(() => bindHolder({'app.level': 'true'})), hasLength(1));
    });

    test('a blank value leaves the default', () {
      expect(bindHolder({'app.level': ' ', 'app.port': '1'}).level, Level.low);
    });
  });

  group('a property described without type information', () {
    test('is converted as a whole', () {
      expect(bindHolder({'app.port': '8080'}).port, 8080);
    });

    test('a bad value fails naming the key', () {
      final errors = errorsOf(() => bindHolder({'app.port': 'many'}));
      expect(errors.single, contains('app.port'));
    });
  });

  group('booleans', () {
    bool read(Object value) => binder({
      'app.flag': value,
    }).bind('app.flag', const ClassType<bool>()).get();

    test('true and false in any case', () {
      expect(read('TRUE'), isTrue);
      expect(read('False'), isFalse);
      expect(read(true), isTrue);
    });

    test('anything else is an error naming the key', () {
      final errors = errorsOf(() => read('maybe'));
      expect(errors.single, contains('app.flag'));
    });
  });
}
