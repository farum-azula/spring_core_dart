import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/external/legacy_config.dart';
import 'package:spring_core_dart_example/src/creation_log.dart';
import 'package:spring_core_dart_example/src/greeting/greeter.dart';

@Introspected()
class AppSettings {
  AppSettings(this.title);

  final String title;
}

class Banner {
  Banner(this.text);

  final String text;
}

abstract interface class IdGenerator {
  int next();
}

class _SequenceGenerator implements IdGenerator {
  int _value = 0;

  @override
  int next() => ++_value;
}

/// A resource with init and (inferred) destroy methods.
class Connection {
  bool open = false;

  void connect() {
    open = true;
    creationLog.add('connection:connect');
  }

  void close() {
    open = false;
    creationLog.add('connection:close');
  }
}

/// `@Bean` methods declare beans; their parameters are injected.
@Configuration()
@PropertySource(['file:config/example.properties'])
@Import([LegacyConfig])
class AppConfig {
  /// Configuration classes can be injected too.
  AppConfig(this.greeter);

  final Greeter greeter;

  @Bean()
  AppSettings appSettings(@Value(r'${app.title}') String title) {
    creationLog.add('appSettings');
    return AppSettings(title);
  }

  /// Depends on another `@Bean` through a parameter.
  @Bean(name: 'welcomeBanner', aliases: ['banner'])
  @Scope(ScopeType.prototype)
  Banner banner(AppSettings settings) => Banner(greeter.greet(settings.title));

  /// Exposed only as the declared return type.
  @Bean()
  @Lazy()
  static IdGenerator idGenerator() => _SequenceGenerator();

  @Bean(initMethod: 'connect')
  Connection connection() => Connection();
}

/// `#{...}` expressions can read `@Introspected` beans.
@Component()
class Headline {
  Headline(@Value('#{appSettings.title.toUpperCase()}') this.text);

  final String text;
}

/// Created after the connection (and destroyed before it).
@Component()
@DependsOn(['connection'])
class Migrations {
  Migrations() {
    creationLog.add('migrations');
  }
}
