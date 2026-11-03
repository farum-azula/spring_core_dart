// @BeforeEach and @AfterEach run in the transaction of the test, the
// @Nested groups' ones too, and the @BeforeAll one outside it. The
// generator writes spring_gen/data_test/lifecycle.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/data_test/lifecycle.test.spring.dart';
import 'app/data_test_app.dart';

@DataTest(
  application: 'test/data_test/app/data_test_app.dart',
  properties: {'spring.main.banner-mode': 'off'},
)
@ActiveProfiles(['test'])
@TestPropertySource(properties: {'shop.name': 'Night Books'})
class LifecycleTest {
  static final events = <String>[];

  @BeforeAll()
  static void beforeAll() => events.add('beforeAll');

  @AfterAll()
  static void afterAll() {
    expect(events.first, 'beforeAll');
  }

  @Autowired()
  late BookRepository books;

  @Autowired()
  late Environment environment;

  @BeforeEach()
  Future<void> seed() async {
    // In the transaction: a second seed would fail the unique index if the
    // first one had stayed.
    expect(TransactionSynchronizationManager.currentTransaction, isNotNull);
    await books.save(Book(title: 'Seeded', year: 2000));
  }

  @AfterEach()
  Future<void> check() async {
    expect(TransactionSynchronizationManager.currentTransaction, isNotNull);
    expect(await books.count(), greaterThanOrEqualTo(1));
  }

  @Test()
  Future<void> firstTestSeesOnlyItsSeed() async {
    expect(await books.count(), 1);
    await books.save(Book(title: 'Dune', year: 1965));
  }

  @Test()
  Future<void> secondTestSeesOnlyItsSeed() async {
    expect(await books.count(), 1);
  }

  @Test()
  void theSharedAnnotationsStillApply() {
    expect(environment.activeProfiles, contains('test'));
    expect(environment.getProperty('shop.name'), 'Night Books');
  }

  @Nested('with a second book')
  final withSecondBook = WithSecondBook();
}

class WithSecondBook {
  @Autowired()
  late BookRepository books;

  // After the outer class's @BeforeEach.
  @BeforeEach()
  Future<void> addSecond() async {
    await books.save(Book(title: 'Second', year: 2001));
  }

  @Test()
  Future<void> seesBothSeeds() async {
    expect(await books.count(), 2);
  }

  // Both seeds went with the transaction of the test before: the unique
  // index of the migrations would refuse the second pair otherwise.
  @Test()
  Future<void> seesBothSeedsAgain() async {
    expect(await books.count(), 2);
  }
}

void main() => runSpringTests();
