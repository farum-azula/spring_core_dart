// The method security interceptor on its own, with hand-made calls: how
// the annotations of a member are found, the rules for @PreFilter targets,
// what can and cannot be filtered, the order of the checks, and the
// failures (401, 403, and mistakes that must not let a call through).
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

/// A call of a method with [args] that returns [result] and remembers the
/// arguments it ran with.
final class FakeInvocation implements MethodInvocation {
  FakeInvocation(this.signature, this.args, [this.result]);

  @override
  final MethodSignature signature;

  @override
  final List<Object?> args;

  final Object? result;

  /// The arguments of each run of the method.
  final ran = <List<Object?>>[];

  @override
  Object? proceed([List<Object?>? args]) {
    ran.add(args ?? this.args);
    return result;
  }

  @override
  Object get proxy => this;

  @override
  Object get target => 'the bean';

  @override
  String toShortString() => signature.toShortString();
}

MethodSignature signatureOf(
  List<Object> annotations, {
  List<String> parameterNames = const ['items'],
  List<Object> classAnnotations = const [],
  MemberKind kind = MemberKind.method,
}) => MethodSignature(
  name: 'run',
  declaringType: 'Service',
  targetType: 'Service',
  parameterNames: parameterNames,
  annotations: annotations,
  targetAnnotations: classAnnotations,
  kind: kind,
);

void main() {
  late GlobalSecurityContextHolderStrategy holder;
  late MethodSecurityInterceptor interceptor;

  void loginAs(String name, [List<String> authorities = const []]) =>
      holder.setContext(
        SecurityContextImpl(
          TestingAuthenticationToken(name, null, authorities),
        ),
      );

  setUp(() {
    holder = GlobalSecurityContextHolderStrategy();
    interceptor = MethodSecurityInterceptor(
      MethodSecurityExpressionHandler(),
      holderStrategy: holder,
    );
  });

  group('finding the annotations of a member', () {
    test('only the five security annotations count', () {
      expect(isMethodSecurityAnnotation(const PreAuthorize('true')), isTrue);
      expect(isMethodSecurityAnnotation(const PostAuthorize('true')), isTrue);
      expect(isMethodSecurityAnnotation(const Secured(['A'])), isTrue);
      expect(isMethodSecurityAnnotation(const PreFilter('true')), isTrue);
      expect(isMethodSecurityAnnotation(const PostFilter('true')), isTrue);
      expect(isMethodSecurityAnnotation(const Deprecated('x')), isFalse);
      expect(isMethodSecurityAnnotation('PreAuthorize'), isFalse);
    });

    test('those of the class apply to a method without its own', () {
      final signature = signatureOf(
        [],
        classAnnotations: [const PreAuthorize('denyAll')],
      );
      final attributes = MethodSecurityAttributes.of(signature);
      expect(attributes.isEmpty, isFalse);
      expect(attributes.preAuthorize!.value, 'denyAll');
    });

    test('a method annotation wins over the class one', () {
      final signature = signatureOf(
        [const PreAuthorize('permitAll')],
        classAnnotations: [const PreAuthorize('denyAll')],
      );
      expect(
        MethodSecurityAttributes.of(signature).preAuthorize!.value,
        'permitAll',
      );
    });

    test('a getter takes nothing from its class', () {
      final signature = signatureOf(
        [],
        kind: MemberKind.getter,
        classAnnotations: [const PreAuthorize('denyAll')],
      );
      expect(MethodSecurityAttributes.of(signature).isEmpty, isTrue);
      expect(
        const MethodSecurityPointcut().matches(signature, 'bean'),
        isFalse,
      );
    });

    test('each kind is reachable by its own accessor', () {
      final attributes = MethodSecurityAttributes.of(
        signatureOf([
          const PreAuthorize('a'),
          const PostAuthorize('b'),
          const Secured(['ROLE_C']),
          const PreFilter('d'),
          const PostFilter('e'),
        ]),
      );
      expect(attributes.preAuthorize!.value, 'a');
      expect(attributes.postAuthorize!.value, 'b');
      expect(attributes.secured!.value, ['ROLE_C']);
      expect(attributes.preFilter!.value, 'd');
      expect(attributes.postFilter!.value, 'e');
      expect(MethodSecurityAttributes.of(signatureOf([])).preAuthorize, isNull);
    });

    final duplicates = <String, List<Object>>{
      'PreAuthorize': [const PreAuthorize('a'), const PreAuthorize('b')],
      'PostAuthorize': [const PostAuthorize('a'), const PostAuthorize('b')],
      'Secured': [
        const Secured(['A']),
        const Secured(['B']),
      ],
      'PreFilter': [const PreFilter('a'), const PreFilter('b')],
      'PostFilter': [const PostFilter('a'), const PostFilter('b')],
    };
    for (final MapEntry(key: type, value: annotations) in duplicates.entries) {
      test('two @$type on one member are refused, not merged', () {
        expect(
          () => MethodSecurityAttributes.of(signatureOf(annotations)),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('more than one @$type'), contains('Service.run')),
            ),
          ),
        );
      });
    }

    test('the pointcut matches secured members and prints its name', () {
      const pointcut = MethodSecurityPointcut();
      expect(
        pointcut.matches(signatureOf([const PreAuthorize('true')]), 'bean'),
        isTrue,
      );
      expect(pointcut.matches(signatureOf([]), 'bean'), isFalse);
      expect('$pointcut', 'MethodSecurityPointcut');
    });

    test('the startup check runs after every other post-processor', () {
      final validator = MethodSecurityValidator(() => interceptor);
      expect(validator.order, Ordered.lowestPrecedence);
    });

    test('different kinds together are fine', () {
      expect(
        () => MethodSecurityAttributes.of(
          signatureOf([const PreAuthorize('a'), const PostAuthorize('b')]),
        ),
        returnsNormally,
      );
    });

    test('the attributes of a signature are computed once', () {
      final signature = signatureOf([const PreAuthorize('true')]);
      expect(
        identical(
          interceptor.attributesOf(signature),
          interceptor.attributesOf(signature),
        ),
        isTrue,
      );
    });

    test('validate parses every expression, so a typo fails at startup', () {
      expect(
        () => interceptor.validate(signatureOf([const PreAuthorize('true')])),
        returnsNormally,
      );
      for (final broken in [
        const PreAuthorize('hasRole('),
        const PostAuthorize('hasRole('),
        const PreFilter('hasRole('),
        const PostFilter('hasRole('),
      ]) {
        expect(
          () => interceptor.validate(signatureOf([broken])),
          throwsA(anything),
          reason: '${broken.runtimeType}',
        );
      }
    });
  });

  group('calls without security annotations', () {
    test('go straight through, without even looking for a user', () {
      final call = FakeInvocation(signatureOf([]), ['x'], 'result');

      expect(interceptor.invoke(call), 'result');

      expect(call.ran, [
        ['x'],
      ]);
    });
  });

  group('who is calling', () {
    test('nobody: a 401 before any expression runs', () {
      // 'permitAll' would pass; the missing login must still fail the call.
      final call = FakeInvocation(
        signatureOf([const PreAuthorize('permitAll')]),
        ['x'],
      );

      expect(
        () => interceptor.invoke(call),
        throwsA(isA<AuthenticationCredentialsNotFoundException>()),
      );
      expect(call.ran, isEmpty);
    });

    test('denied: a generic message, the method not run', () {
      loginAs('ada');
      final call = FakeInvocation(
        signatureOf([const PreAuthorize("hasRole('ADMIN')")]),
        ['x'],
      );

      expect(
        () => interceptor.invoke(call),
        throwsA(
          isA<AuthorizationDeniedException>()
              .having((e) => e.message, 'message', 'Access Denied')
              .having((e) => e.result.isGranted, 'granted', isFalse),
        ),
      );
      expect(call.ran, isEmpty);
    });

    test('@Secured checks authorities with the hierarchy of the handler', () {
      interceptor = MethodSecurityInterceptor(
        MethodSecurityExpressionHandler(
          roleHierarchy: RoleHierarchyImpl.fromHierarchy(
            'ROLE_ADMIN > ROLE_SUPPORT',
          ),
        ),
        holderStrategy: holder,
      );
      final call = FakeInvocation(
        signatureOf([
          const Secured(['ROLE_SUPPORT']),
        ]),
        [],
        'ok',
      );

      loginAs('ada', ['ROLE_USER']);
      expect(
        () => interceptor.invoke(call),
        throwsA(isA<AccessDeniedException>()),
      );
      loginAs('root', ['ROLE_ADMIN']);
      expect(interceptor.invoke(call), 'ok');
    });
  });

  group('@PreFilter', () {
    FakeInvocation call(
      List<Object?> args, {
      String target = '',
      List<String> names = const ['items', 'other'],
      String expression = 'filterObject > 1',
    }) => FakeInvocation(
      signatureOf([
        PreFilter(expression, filterTarget: target),
      ], parameterNames: names),
      args,
      'done',
    );

    setUp(() => loginAs('ada'));

    test('the only collection argument is filtered; the method gets the '
        "result and the caller's list is untouched", () {
      final input = [1, 2, 3];
      final invocation = call([input]);

      expect(interceptor.invoke(invocation), 'done');

      expect(invocation.ran.single.single, [2, 3]);
      expect(input, [1, 2, 3]);
    });

    test('other arguments pass unchanged, whatever their type', () {
      final invocation = call([
        5,
        [1, 2, 3],
        'text',
      ]);

      interceptor.invoke(invocation);

      expect(invocation.ran.single, [
        5,
        [2, 3],
        'text',
      ]);
    });

    test('a Set stays a Set', () {
      final invocation = call([
        {1, 2, 3},
      ]);

      interceptor.invoke(invocation);

      expect(invocation.ran.single.single, isA<Set<Object?>>());
      expect(invocation.ran.single.single, {2, 3});
    });

    test('a Map is filtered by its entries, in place', () {
      final input = <String, int>{'a': 1, 'b': 2, 'c': 3};
      final invocation = call([
        input,
      ], expression: 'filterObject.value > 1 and filterObject.key != "c"');

      interceptor.invoke(invocation);

      expect(invocation.ran.single.single, {'b': 2});
      expect(input, {'b': 2}, reason: "a copy would lose the map's types");
    });

    test('an unmodifiable Map cannot be filtered: the call fails instead '
        'of running with everything', () {
      final invocation = call([
        Map<Object?, Object?>.unmodifiable({'a': 1}),
      ]);

      expect(
        () => interceptor.invoke(invocation),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('unmodifiable Map'),
          ),
        ),
      );
      expect(invocation.ran, isEmpty);
    });

    test('filterTarget picks one of several collections', () {
      final invocation = call([
        [1, 2, 3],
        [1, 2, 3],
      ], target: 'other');

      interceptor.invoke(invocation);

      expect(invocation.ran.single, [
        [1, 2, 3],
        [2, 3],
      ]);
    });

    test('several collections without filterTarget: the call fails', () {
      final invocation = call([
        [1],
        [2],
      ]);

      expect(
        () => interceptor.invoke(invocation),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('needs filterTarget'), contains('more than one')),
          ),
        ),
      );
      expect(invocation.ran, isEmpty);
    });

    test('no collection argument and no filterTarget: the call fails', () {
      final invocation = call(['text', 5]);

      expect(
        () => interceptor.invoke(invocation),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('needs filterTarget'), contains('no collection')),
          ),
        ),
      );
      expect(invocation.ran, isEmpty);
    });

    test('a filterTarget that is no argument: the call fails', () {
      final invocation = call([
        [1],
      ], target: 'nope');

      expect(
        () => interceptor.invoke(invocation),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('No argument nope'), contains('Service.run')),
          ),
        ),
      );
      expect(invocation.ran, isEmpty);
    });

    test('a filterTarget that is not a List, Set or Map: the call fails', () {
      final invocation = call(['text', 5], target: 'items');

      expect(
        () => interceptor.invoke(invocation),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Can only filter a List, Set or Map'),
          ),
        ),
      );
      expect(invocation.ran, isEmpty);
    });

    test('a lazy Iterable cannot be filtered either', () {
      final invocation = call([
        [1, 2, 3].map((e) => e),
      ]);

      expect(
        () => interceptor.invoke(invocation),
        throwsA(isA<ArgumentError>()),
      );
      expect(invocation.ran, isEmpty);
    });

    test('a null target stays null', () {
      final invocation = call([null, 'x'], target: 'items');

      interceptor.invoke(invocation);

      expect(invocation.ran.single, [null, 'x']);
    });

    test('the filter runs before @PreAuthorize, which sees the filtered '
        'argument', () {
      final invocation = FakeInvocation(
        signatureOf([
          const PreFilter('filterObject > 1'),
          const PreAuthorize('#items.size() == 2'),
        ]),
        [
          [1, 2, 3],
        ],
        'done',
      );

      expect(interceptor.invoke(invocation), 'done');

      final tooMany = FakeInvocation(
        signatureOf([
          const PreFilter('filterObject > 0'),
          const PreAuthorize('#items.size() == 2'),
        ]),
        [
          [1, 2, 3],
        ],
      );
      expect(
        () => interceptor.invoke(tooMany),
        throwsA(isA<AuthorizationDeniedException>()),
      );
    });

    test('an element failing the expression decides nothing by chance: a '
        'broken filter fails the call', () {
      final invocation = call([
        [1, 2],
      ], expression: "'not a boolean'");

      expect(() => interceptor.invoke(invocation), throwsArgumentError);
      expect(invocation.ran, isEmpty);
    });
  });

  group('@PostFilter and @PostAuthorize', () {
    setUp(() => loginAs('ada'));

    test('@PostFilter filters the result of the method', () {
      final invocation = FakeInvocation(
        signatureOf([const PostFilter('filterObject != 2')]),
        [],
        [1, 2, 3],
      );

      expect(interceptor.invoke(invocation), [1, 3]);
    });

    test('a null result stays null', () {
      final invocation = FakeInvocation(
        signatureOf([const PostFilter('false')]),
        [],
      );

      expect(interceptor.invoke(invocation), isNull);
    });

    test('a result that cannot be filtered fails the call', () {
      final invocation = FakeInvocation(
        signatureOf([const PostFilter('true')]),
        [],
        'a string',
      );

      expect(
        () => interceptor.invoke(invocation),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('not String'),
          ),
        ),
      );
    });

    test('@PostAuthorize sees the filtered result and may deny it', () {
      final allowed = FakeInvocation(
        signatureOf([
          const PostFilter('filterObject > 1'),
          const PostAuthorize('returnObject.size() == 2'),
        ]),
        [],
        [1, 2, 3],
      );
      expect(interceptor.invoke(allowed), [2, 3]);

      final denied = FakeInvocation(
        signatureOf([
          const PostFilter('filterObject > 2'),
          const PostAuthorize('returnObject.size() == 2'),
        ]),
        [],
        [1, 2, 3],
      );
      expect(
        () => interceptor.invoke(denied),
        throwsA(isA<AuthorizationDeniedException>()),
      );
      expect(denied.ran, hasLength(1), reason: 'the method has run');
    });

    test('@PostAuthorize reads the arguments of the call, as filtered', () {
      final invocation = FakeInvocation(
        signatureOf([
          const PreFilter('filterObject != 2'),
          const PostAuthorize('#items.size() == 2'),
        ]),
        [
          [1, 2, 3],
        ],
        'result',
      );

      expect(interceptor.invoke(invocation), 'result');
    });
  });
}
