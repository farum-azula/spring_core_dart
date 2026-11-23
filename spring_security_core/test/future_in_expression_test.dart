// An expression runs synchronously: a Future in it is refused, and never
// compared, so `... != false` cannot hold for everyone.
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

class Gate {
  int calls = 0;

  Future<bool> get ready async => false;

  Future<bool> described() async {
    calls++;
    return false;
  }

  Object undeclared() {
    calls++;
    return Future<bool>.value(false);
  }

  bool open() => true;
}

final class _Customizer implements SecurityExpressionContextCustomizer {
  const _Customizer();

  @override
  void customize(StandardEvaluationContext context) {
    context.addMethodResolver(const _CustomResolver());
  }
}

final class _CustomResolver implements MethodResolver {
  const _CustomResolver();

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) => name == 'custom' ? (_, _, _) => Future<bool>.value(false) : null;
}

bool _evaluate(String text, Gate gate, {List<Object?> args = const []}) {
  final introspector = Introspector()
    ..register(
      Introspection<Gate>(
        properties: [
          IntrospectedProperty<Gate>(
            'ready',
            type: Future,
            get: (gate) => gate.ready,
          ),
        ],
        methods: [
          IntrospectedMethod<Gate>(
            'described',
            isFuture: true,
            invoke: (gate, _) => gate.described(),
          ),
          IntrospectedMethod<Gate>(
            'undeclared',
            invoke: (gate, _) => gate.undeclared(),
          ),
          IntrospectedMethod<Gate>('open', invoke: (gate, _) => gate.open()),
        ],
      ),
    );
  final handler = MethodSecurityExpressionHandler(
    introspector: introspector,
    customizers: const [_Customizer()],
  );
  final root = handler.createRoot(() => null, target: gate);
  final signature = MethodSignature(
    name: 'call',
    declaringType: 'Gate',
    targetType: 'Gate',
    parameterNames: [for (var i = 0; i < args.length; i++) 'v$i'],
  );
  return handler.evaluate(
    text,
    handler.createEvaluationContext(root, signature, args),
  );
}

void main() {
  final refused = throwsA(
    isA<ArgumentError>().having(
      (error) => '$error',
      'message',
      contains('asynchronous'),
    ),
  );

  test('a method described as asynchronous is not called', () {
    final gate = Gate();
    expect(() => _evaluate('this.described() != false', gate), refused);
    expect(gate.calls, 0);
  });

  test('a Future from a method not described as one is refused', () {
    expect(() => _evaluate('this.undeclared() != false', Gate()), refused);
  });

  test('a Future from a property is refused', () {
    expect(() => _evaluate('this.ready != false', Gate()), refused);
  });

  test("a Future from a customizer's resolver is refused", () {
    expect(() => _evaluate('this.custom() != false', Gate()), refused);
  });

  for (final (text, value) in <(String, Object?)>[
    ('#v0 != false', Future<bool>.value(false)),
    ('#v0 == false', Future<bool>.value(false)),
    ('#v0 != null', Future<bool>.value(false)),
    ('#v0[0] != false', [Future<bool>.value(false)]),
    ("#v0['k'] != false", {'k': Future<bool>.value(false)}),
    ('#v0 != {false}', [Future<bool>.value(false)]),
    ('#v0.?[#this != false].size() > 0', [Future<bool>.value(false)]),
  ]) {
    test('an argument holding a Future is refused: $text', () {
      expect(() => _evaluate(text, Gate(), args: [value]), refused);
    });
  }

  test('plain arguments still compare', () {
    expect(_evaluate('#v0 != false', Gate(), args: [true]), isTrue);
    expect(
      _evaluate(
        "#v0['k'] == 1",
        Gate(),
        args: [
          {'k': 1},
        ],
      ),
      isTrue,
    );
  });

  test('a synchronous method still answers', () {
    expect(_evaluate('this.open()', Gate()), isTrue);
  });
}
