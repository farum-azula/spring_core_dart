import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

final class Code implements ExitCodeGenerator {
  Code(this.code);
  final int code;
  @override
  int getExitCode() => code;
}

final class OrderedCode extends Code implements Ordered {
  OrderedCode(super.code, this.order);
  @override
  final int order;
}

final class Throwing implements ExitCodeGenerator {
  @override
  int getExitCode() => throw StateError('no code');
}

final class MapStartupError implements ExitCodeExceptionMapper {
  @override
  int getExitCode(Object exception) => exception is FormatException ? 64 : 0;
}

final class Failing implements CommandLineRunner {
  Failing(this.error);
  final Object error;
  @override
  void run(Object args) => throw error;
}

final class CodedError implements Exception, ExitCodeGenerator {
  @override
  int getExitCode() => 78;
}

BeanModule _module(List<Object> beans) => BeanModule('app', [
  for (final (i, bean) in beans.indexed)
    BeanDefinition<Object>(
      name: 'bean$i',
      types: [
        bean.runtimeType,
        ...switch (bean) {
          ExitCodeGenerator() => [ExitCodeGenerator],
          ExitCodeExceptionMapper() => [ExitCodeExceptionMapper],
          CommandLineRunner() => [CommandLineRunner],
          _ => <Type>[],
        },
      ],
      create: (_) => bean,
    ),
]);

ConfigurableApplicationContext _run(
  List<Object> beans, {
  List<ExitCodeEvent>? events,
}) => SpringApplication(
  [_module(beans)],
  registerShutdownHook: false,
  initializers: [
    if (events != null)
      (context) => context.addApplicationListener(
        ApplicationListenerAdapter.of<ExitCodeEvent>(events.add),
      ),
  ],
  out: (_) {},
).run(const [], systemEnvironment: const {});

void main() {
  group('SpringApplication.exit', () {
    test('without generators the code is 0 and the context is closed', () {
      final events = <ExitCodeEvent>[];
      final context = _run([], events: events);
      expect(SpringApplication.exit(context), 0);
      expect(context.isActive, isFalse);
      expect(events, isEmpty);
    });

    test('the first non-zero code wins (Boot 3+), not the highest', () {
      final context = _run([Code(0), Code(3), Code(7), Code(5)]);
      expect(SpringApplication.exit(context), 3);
    });

    test('generators are sorted by order first', () {
      final context = _run([
        OrderedCode(-2, 5),
        OrderedCode(-9, 1),
        OrderedCode(0, 0),
      ]);
      expect(SpringApplication.exit(context), -9);
    });

    test('generators passed in are combined with the beans', () {
      final context = _run([Code(3)]);
      expect(SpringApplication.exit(context, [Code(9), Code(1)]), 9);
      final ordered = _run([OrderedCode(4, Ordered.highestPrecedence)]);
      expect(SpringApplication.exit(ordered, [Code(9)]), 4);
    });

    test('ExitCodeEvent is published, then the context closes', () {
      final events = <ExitCodeEvent>[];
      final active = <bool>[];
      final context = _run([Code(4)], events: events);
      context.addApplicationListener(
        ApplicationListenerAdapter.of<ExitCodeEvent>(
          (_) => active.add(context.isActive),
        ),
      );
      expect(SpringApplication.exit(context), 4);
      expect(events.map((e) => e.exitCode), [4]);
      expect(events.single.source, same(context));
      expect(active, [true]);
      expect(context.isActive, isFalse);
    });

    test('a generator that throws gives 1, or keeps the code found', () {
      expect(SpringApplication.exit(_run([Throwing()])), 1);
      expect(SpringApplication.exit(_run([Code(6), Throwing()])), 6);
    });

    test('an already closed context gives 1', () {
      final context = _run([Code(3)])..close();
      expect(SpringApplication.exit(context), 1);
    });
  });

  group('failed runs', () {
    test('an ExitCodeExceptionMapper bean maps the error of a runner', () {
      final events = <ExitCodeEvent>[];
      final error = FormatException('bad input');
      Object? caught;
      try {
        _run([MapStartupError(), Failing(error)], events: events);
      } catch (e) {
        caught = e;
      }
      expect(caught, same(error));
      expect(SpringApplication.exitCodeOf(error), 64);
      expect(events.map((e) => e.exitCode), [64]);
    });

    test('an error that is an ExitCodeGenerator gives its code', () {
      final error = CodedError();
      expect(() => _run([Failing(error)]), throwsA(same(error)));
      expect(SpringApplication.exitCodeOf(error), 78);
    });

    test('no mapping: null', () {
      final error = StateError('x');
      expect(() => _run([MapStartupError(), Failing(error)]), throwsStateError);
      expect(SpringApplication.exitCodeOf(error), isNull);
      expect(SpringApplication.exitCodeOf('a string'), isNull);
    });
  });
}
