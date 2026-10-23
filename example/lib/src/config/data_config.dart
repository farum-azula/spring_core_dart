// Profile-specific configurations declaring the same bean name, with the
// bean type inferred from the @Bean method body.
//
// Spring (Java): @Profile("dev") and @Profile("prod") @Configuration
// classes that both declare `@Bean DataSource dataSource()`. Spring only
// knows the declared type (DataSource) until the bean is created; here the
// definition is registered as EmbeddedDataSource / PooledDataSource from
// the start.
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class DataSource {
  String get url;
}

class EmbeddedDataSource implements DataSource {
  EmbeddedDataSource(this.url);

  @override
  final String url;
}

class PooledDataSource implements DataSource {
  PooledDataSource(this.url, this.maxSize);

  @override
  final String url;
  final int maxSize;
}

@Configuration()
@Profile(['dev'])
class DevDataConfig {
  @Bean()
  @Lazy()
  DataSource dataSource() => EmbeddedDataSource('mem:books');
}

@Configuration()
@Profile(['prod'])
class ProdDataConfig {
  @Bean()
  @Lazy()
  DataSource dataSource(@Value(r'${db.pool-size:8}') int size) =>
      PooledDataSource('pool:books', size);
}
