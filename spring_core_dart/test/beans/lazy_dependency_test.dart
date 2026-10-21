import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

abstract interface class Books {
  String find();
}

/// A hand-written stand-in for the generated lazy proxy.
class LazyBooks implements Books {
  LazyBooks(this._resolve);
  final Books Function() _resolve;
  @override
  String find() => _resolve().find();
}

class BookService implements Books {
  late Books self;
  @override
  String find() => 'raw';
  String viaSelf() => self.find();
}

class Wrapped implements Books {
  Wrapped(this.target);
  final BookService target;
  @override
  String find() => 'proxied';
}

/// Wraps BookService like an AOP proxy would.
class WrapBooks implements BeanPostProcessor {
  @override
  Object postProcessBeforeInitialization(Object bean, String name) => bean;
  @override
  Object postProcessAfterInitialization(Object bean, String name) =>
      bean is BookService ? Wrapped(bean) : bean;
}

abstract interface class Greeter {
  String greet();
}

class English implements Greeter {
  @override
  String greet() => 'hello';
}

class Loud implements Greeter {
  Loud(this.inner);
  final Greeter inner;
  @override
  String greet() => inner.greet().toUpperCase();
}

class LazyGreeter implements Greeter {
  LazyGreeter(this._resolve);
  final Greeter Function() _resolve;
  @override
  String greet() => _resolve().greet();
}

class A {
  A(this.b);
  final B b;
}

class B {
  B(this.a);
  final A a;
}

class LazyA implements A {
  LazyA(this._resolve);
  final A Function() _resolve;
  @override
  B get b => _resolve().b;
}

AnnotationConfigApplicationContext start(List<BeanDefinition<Object>> beans) =>
    AnnotationConfigApplicationContext([BeanModule('m', beans)])..refresh();

void main() {
  test('self-injection through @Lazy reaches the proxy', () {
    final context = start([
      BeanDefinition<WrapBooks>(
        name: 'wrap',
        types: const [WrapBooks, BeanPostProcessor],
        create: (_) => WrapBooks(),
      ),
      BeanDefinition<BookService>(
        name: 'bookService',
        types: const [BookService, Books],
        dependencies: const [Dependency.lazy(Books, name: 'self')],
        create: (_) => BookService(),
        inject: (bean, r) =>
            bean.self = LazyBooks(r.lazyDependency<Books>(name: 'self')),
      ),
    ]);
    final proxy = context.getBean<Books>() as Wrapped;
    expect(proxy.target.viaSelf(), 'proxied');
  });

  test(
    'a lazy dependency keeps the requester: decorators get the other bean',
    () {
      final context = start([
        BeanDefinition<English>(
          name: 'english',
          types: const [English, Greeter],
          create: (_) => English(),
        ),
        BeanDefinition<Loud>(
          name: 'loud',
          types: const [Loud, Greeter],
          primary: true,
          dependencies: const [Dependency.lazy(Greeter, name: 'inner')],
          create: (r) =>
              Loud(LazyGreeter(r.lazyDependency<Greeter>(name: 'inner'))),
        ),
      ]);
      // Resolved after creation (no bean in creation), still excluding loud.
      expect(context.getBean<Greeter>().greet(), 'HELLO');
    },
  );

  test('@Lazy breaks a constructor cycle', () {
    final context = start([
      BeanDefinition<A>(
        name: 'a',
        dependencies: const [Dependency(B, name: 'b')],
        create: (r) => A(r.dependency<B>(name: 'b')),
      ),
      BeanDefinition<B>(
        name: 'b',
        dependencies: const [Dependency.lazy(A, name: 'a')],
        create: (r) => B(LazyA(r.lazyDependency<A>(name: 'a'))),
      ),
    ]);
    final b = context.getBean<B>();
    expect(b.a.b, same(b));
  });

  test('without @Lazy the same cycle fails at refresh', () {
    expect(
      () => start([
        BeanDefinition<A>(
          name: 'a',
          dependencies: const [Dependency(B, name: 'b')],
          create: (r) => A(r.dependency<B>(name: 'b')),
        ),
        BeanDefinition<B>(
          name: 'b',
          dependencies: const [Dependency(A, name: 'a')],
          create: (r) => B(r.dependency<A>(name: 'a')),
        ),
      ]),
      throwsA(isA<BeanCurrentlyInCreationException>()),
    );
  });

  test(
    'a missing or ambiguous lazy bean fails at refresh, not on first use',
    () {
      expect(
        () => start([
          BeanDefinition<B>(
            name: 'b',
            dependencies: const [Dependency.lazy(A)],
            create: (r) => B(LazyA(r.lazyDependency<A>())),
          ),
        ]),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        () => start([
          BeanDefinition<English>(
            name: 'one',
            types: const [English, Greeter],
            create: (_) => English(),
          ),
          BeanDefinition<English>(
            name: 'two',
            types: const [English, Greeter],
            create: (_) => English(),
          ),
          BeanDefinition<Loud>(
            name: 'loud',
            dependencies: const [Dependency.lazy(Greeter)],
            create: (r) => Loud(LazyGreeter(r.lazyDependency<Greeter>())),
          ),
        ]),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
    },
  );

  test('the target is resolved on every call (scoped beans stay correct)', () {
    var created = 0;
    final context = start([
      BeanDefinition<English>(
        name: 'english',
        types: const [English, Greeter],
        scope: ScopeType.prototype,
        create: (_) {
          created++;
          return English();
        },
      ),
      BeanDefinition<Loud>(
        name: 'loud',
        dependencies: const [Dependency.lazy(Greeter)],
        create: (r) => Loud(LazyGreeter(r.lazyDependency<Greeter>())),
      ),
    ]);
    final loud = context.getBean<Loud>();
    expect(created, 0); // nothing resolved yet
    loud.greet();
    loud.greet();
    expect(created, 2);
  });
}
