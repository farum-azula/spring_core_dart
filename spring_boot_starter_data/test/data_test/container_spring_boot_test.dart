@Tags(['docker'])
library;

// A @SpringBootTest class with containers: the containers start before the
// application, a @ServiceConnection wires the application to PostgreSQL over
// the URL of its config file, and a @DynamicPropertySource method hands over
// the address of a container of any image. Skipped without Docker (a failure
// with CONTAINERS_REQUIRED=true). The generator writes
// spring_gen/data_test/container_spring_boot.test.spring.dart.
import 'dart:io';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/data_test/container_spring_boot.test.spring.dart';
import 'postgres_app/postgres_data_app.dart';

@SpringBootTest(
  application: 'test/data_test/postgres_app/postgres_data_app.dart',
)
@Testcontainers()
class ContainerSpringBootTest {
  // The properties file says postgresql://nobody@localhost:1/none.
  @Container()
  @ServiceConnection()
  static final postgres = PostgresContainer('postgres:17');

  @Container()
  static final GenericContainer web = GenericContainer('nginx:1.29-alpine')
      .withExposedPorts([80])
      .waitingFor(Wait.forHttp('/').forStatusCode(200));

  static final List<String> events = [];

  // The application is not a dependant of the starter, which is what adds its
  // auto-configuration to an application (the generator).
  @ContextInitializer()
  static void addTheStarter(ConfigurableApplicationContext context) =>
      context.register(springBootStarterDataAutoConfiguration);

  @BeforeAll()
  static void containersAreUpBeforeTheTests() {
    events.add('beforeAll: ${postgres.isStarted} ${web.isStarted}');
  }

  // Runs when the context starts, after the containers did.
  @DynamicPropertySource()
  static void properties(DynamicPropertyRegistry registry) {
    events.add('dynamic: ${web.isStarted}');
    registry.add('shop.web.url', () => web.baseUrl(80));
  }

  @Value(r'${shop.web.url}')
  late String webUrl;

  @Autowired()
  late DataSource dataSource;

  @Autowired()
  late BookRepository books;

  @Test()
  void startsTheContainersBeforeAnythingElse() {
    expect(events, ['beforeAll: true true', 'dynamic: true']);
  }

  @Test()
  Future<void> theServiceConnectionBeatsTheConfigFile() async {
    expect(dataSource.settings.url.toString(), postgres.jdbcUrl);
    expect(dataSource.settings.url.toString(), isNot(contains('localhost:1')));
    // The migrations ran on the container's database.
    expect(await books.count(), 0);
  }

  @Test()
  Future<void> aDynamicPropertyHoldsTheAddressOfAContainer() async {
    expect(webUrl, web.baseUrl(80));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(Uri.parse(webUrl))).close();
    await response.drain<void>();
    expect(response.statusCode, 200);
  }
}

void main() => runSpringTests();
