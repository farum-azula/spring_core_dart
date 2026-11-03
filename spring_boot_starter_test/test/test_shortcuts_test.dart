// Constructed without const on purpose, so the constructors run.
// ignore_for_file: prefer_const_constructors

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

// The shortcuts of the test context that need a missing web starter or a
// missing value, and the annotations of test classes with what they hold.

void main() {
  group('without the web starter', () {
    final app = springBootTest(SpringApplication([appModule()]));

    test('there is no local server port, and the error says what to do', () {
      expect(
        () => app.localServerPort,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('WebEnvironment.randomPort'),
          ),
        ),
      );
    });

    test('there is no MockMvc', () {
      expect(() => app.mockMvc, throwsStateError);
    });

    test('a value with a placeholder that has none is null as optional', () {
      expect(app.optionalValue<String>(r'${no.such.key}'), isNull);
      expect(app.optionalValue<String>(r'${greeting.prefix:Hi}'), 'Hi');
    });
  });

  group('the annotations of test classes', () {
    // Built at run time, so their constructors run.
    final names = ['one', 'two'];

    test('@SpringBootTest keeps its settings and has the defaults', () {
      final plain = SpringBootTest(args: names);
      expect(plain.args, names);
      expect(plain.application, isNull);
      expect(plain.properties, isEmpty);
      expect(plain.resourceDirectories, ['test/resources']);
      expect(plain.webEnvironment, WebEnvironment.mock);
      final full = SpringBootTest(
        application: names.first,
        properties: {names.last: 1},
        resourceDirectories: names,
        webEnvironment: WebEnvironment.randomPort,
      );
      expect(full.application, 'one');
      expect(full.properties, {'two': 1});
      expect(full.resourceDirectories, names);
      expect(full.webEnvironment, WebEnvironment.randomPort);
    });

    test('profiles, property sources and environments', () {
      expect(ActiveProfiles(names).profiles, names);
      final source = TestPropertySource(
        properties: {names.first: names.last},
        locations: names,
      );
      expect(source.properties, {'one': 'two'});
      expect(source.locations, names);
      expect(const TestPropertySource().properties, isEmpty);
      expect(TestEnvironment({names.first: names.last}).variables, {
        'one': 'two',
      });
    });

    test('@TestBean, names and the markers', () {
      final bean = TestBean(name: names.first, type: names.runtimeType);
      expect(bean.name, 'one');
      expect(bean.type, names.runtimeType);
      expect(const TestBean().name, isNull);
      expect(Test(names.first).name, 'one');
      expect(Nested(names.first).name, 'one');
      expect(Disabled(names.first).reason, 'one');
      expect(Tag(names.first).name, 'one');
      expect(DisplayName(names.first).name, 'one');
      expect(const Test().name, isNull);
      expect(const Disabled().reason, isNull);
      expect(const Nested().name, isNull);
    });

    test('@TestOptions keeps the options of the test', () {
      final options = TestOptions(
        timeout: Timeout(const Duration(seconds: 3)),
        retry: names.length,
        testOn: names.first,
        onPlatform: {names.last: 1},
      );
      expect(options.timeout?.duration, const Duration(seconds: 3));
      expect(options.retry, 2);
      expect(options.testOn, 'one');
      expect(options.onPlatform, {'two': 1});
      expect(const TestOptions().retry, isNull);
    });

    test('the argument-free markers can be created', () {
      // Without const, so the constructors run.
      final markers = <Object>[
        DynamicPropertySource(),
        ContextInitializer(),
        DirtiesContext(),
        BeforeAll(),
        BeforeEach(),
        AfterEach(),
        AfterAll(),
        CapturedOutput(),
        LocalServerPort(),
        AutoConfigureMockMvc(),
        Test(),
        Nested(),
        Disabled(),
        TestBean(),
        SpringBootTest(),
        TestOptions(),
        TestPropertySource(),
      ];
      expect(markers, hasLength(17));
    });
  });
}
