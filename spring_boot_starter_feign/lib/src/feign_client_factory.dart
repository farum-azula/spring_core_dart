import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_client.dart';
import 'package:spring_boot_starter_feign/src/feign_client_config.dart';
import 'package:spring_boot_starter_feign/src/feign_exception.dart';
import 'package:spring_boot_starter_feign/src/feign_invocation_handler.dart';
import 'package:spring_boot_starter_feign/src/request_template.dart';
import 'package:spring_boot_starter_feign/src/retryer.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Builds the working client behind each `@FeignClient` interface: it
/// gathers the client's settings and collaborators and creates its
/// [FeignInvocationHandler].
///
/// The starter declares it as the `feignClientFactory` bean; when the
/// container creates a client bean, the generated class asks this factory
/// for its handler. Applications do not use it directly: they declare
/// beans of the collaborator types and the factory finds them. Each
/// client gets the application's [ObjectMapper] and [HttpTransport] and,
/// chosen per client, its [RequestInterceptor]s, [ErrorDecoder] and
/// [Retryer]:
///
/// 1. the beans declared by the client's `@FeignClient(configuration:)`
///    classes: their `ErrorDecoder` and `Retryer` win, their interceptors
///    are added;
/// 2. the application's other beans of these types (beans of a
///    configuration class never reach clients that do not list it);
///    without any, a [DefaultErrorDecoder] and [Retryer.never];
/// 3. the `retryer` and `error-decoder` properties of
///    `spring.cloud.openfeign.client.config.<name>` (or `default`), which
///    win over both, as with Spring's default `default-to-properties`;
///    the `request-interceptors` property adds interceptors.
///
/// [interceptors], [errorDecoder] and [retryer] given to the constructor
/// replace the application's beans (step 2), for example in a test.
///
/// Spring (Java): `FeignClientFactoryBean` with the beans of the client's
/// `FeignClientFactory` context.
final class FeignClientFactory
    implements InvocationHandlerFactory, BeanFactoryAware {
  /// A factory that resolves placeholders and properties in [environment],
  /// writes and reads JSON with [mapper] and sends through [transport].
  FeignClientFactory({
    required this.environment,
    required this.mapper,
    required this.transport,
    this.interceptors,
    this.errorDecoder,
    this.retryer,
  });

  /// The configuration: the clients' properties and the placeholders of
  /// their URLs, paths and headers.
  final Environment environment;

  /// Writes request bodies as JSON and reads response bodies, for every
  /// client.
  final ObjectMapper mapper;

  /// Sends the requests of every client.
  final HttpTransport transport;

  /// Interceptors that replace the application's `RequestInterceptor`
  /// beans for every client; `null` (the default) uses the beans.
  final List<RequestInterceptor>? interceptors;

  /// The error decoder of clients that have none of their own; `null`
  /// uses the application's `ErrorDecoder` bean, else
  /// [DefaultErrorDecoder].
  final ErrorDecoder? errorDecoder;

  /// The retryer of clients that have none of their own; `null` uses the
  /// application's `Retryer` bean, else [Retryer.never].
  final Retryer? retryer;

  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<FeignClient>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final client = metadata.annotation<FeignClient>()!;
    final config = FeignClientConfig.of(environment, client.configKey);
    final beans = _ClientBeans(this, client, metadata.typeName);
    final fallbackType = client.fallback;
    Object? fallbackBean;
    return FeignInvocationHandler(
      metadata: metadata,
      client: client,
      config: config,
      environment: environment,
      mapper: mapper,
      transport: transport,
      // A `request-interceptors` bean that is also a context bean (or is
      // named twice) runs once.
      interceptors: _distinct([
        ...beans.interceptors(),
        for (final name in config.requestInterceptors)
          beans.named<RequestInterceptor>(name, 'request-interceptors'),
      ]),
      errorDecoder: switch (config.errorDecoder) {
        final name? => beans.named<ErrorDecoder>(name, 'error-decoder'),
        null =>
          beans.single<ErrorDecoder>(errorDecoder) ??
              const DefaultErrorDecoder(),
      },
      retryer: switch (config.retryer) {
        final name? => beans.named<Retryer>(name, 'retryer'),
        null => beans.single<Retryer>(retryer) ?? Retryer.never,
      },
      fallback: fallbackType == null
          ? null
          : () => fallbackBean ??= _fallback(fallbackType, metadata),
    );
  }

  static List<T> _distinct<T extends Object>(List<T> values) => [
    for (final (index, value) in values.indexed)
      if (!values.take(index).any((other) => identical(other, value))) value,
  ];

  // The configuration classes of every client bean (from the annotations
  // of their definitions), computed once.
  late final Set<Type> _configurationTypes = switch (_beanFactory) {
    final ConfigurableListableBeanFactory beans => {
      for (final name in beans.getBeanNamesForAnnotation<FeignClient>())
        ...?beans.findAnnotationOnBean<FeignClient>(name)?.configuration,
    },
    _ => const <Type>{},
  };

  final _configurationBeans = <Type, Set<String>>{};

  // The beans of configuration class [type]: the configuration bean and
  // the beans of its @Bean methods (instance and static ones).
  Set<String> _beansOf(Type type) => _configurationBeans.putIfAbsent(type, () {
    final beans = _beanFactory;
    if (beans is! ConfigurableListableBeanFactory) {
      return const {};
    }
    final owners = beans.getBeanNamesForType(type);
    final sources = {
      for (final owner in owners)
        if (beans.containsBeanDefinition(owner))
          ?beans.getBeanDefinition(owner).source,
    };
    return {
      ...owners,
      for (final name in beans.beanDefinitionNames)
        if (beans.getBeanDefinition(name) case final definition
            when owners.contains(definition.factoryBeanName) ||
                sources.any(
                  (source) =>
                      definition.source?.startsWith('$source.') ?? false,
                ))
          name,
    };
  });

  Object _fallback(Type type, InterfaceMetadata<Object> metadata) {
    final factory = _beanFactory;
    if (factory is! ListableBeanFactory) {
      throw StateError('No bean factory to look up the fallback $type');
    }
    final names = factory.getBeanNamesForType(type);
    if (names.isEmpty) {
      throw StateError(
        'The fallback $type of ${metadata.typeName} is not a bean: annotate '
        'it with @Component()',
      );
    }
    final bean = factory.getBeanByName(names.first);
    if (!metadata.isImplementedBy(bean)) {
      throw StateError(
        'The fallback $type must implement ${metadata.typeName}',
      );
    }
    return bean;
  }
}

// The beans one client sees: those of its configuration classes and the
// application's (minus every configuration class's).
final class _ClientBeans {
  _ClientBeans(this.factory, this.client, this.typeName);

  final FeignClientFactory factory;
  final FeignClient client;
  final String typeName;

  ConfigurableListableBeanFactory? get _beans => switch (factory._beanFactory) {
    final ConfigurableListableBeanFactory beans => beans,
    _ => null,
  };

  late final Set<String> _own = {
    for (final type in client.configuration) ...factory._beansOf(type),
  };

  late final Set<String> _others = {
    for (final type in factory._configurationTypes) ...factory._beansOf(type),
  }.difference(_own);

  Never _fail(String message) =>
      throw StateError('Invalid Feign client $typeName: $message');

  /// The client's interceptors: the application's (or the factory's) and
  /// the client's own, in `@Order`. Throws a [StateError] when a
  /// configuration class of the client is not a bean.
  List<RequestInterceptor> interceptors() {
    final beans = _beans;
    if (beans == null) {
      return factory.interceptors ?? const [];
    }
    for (final type in client.configuration) {
      if (beans.getBeanNamesForType(type).isEmpty) {
        _fail(
          'the configuration class $type is not a bean: annotate it with '
          '@Configuration()',
        );
      }
    }
    final names = beans.getBeanNamesForType(RequestInterceptor);
    final own = {
      for (final name in names)
        if (_own.contains(name)) beans.getBeanByName(name),
    };
    final excluded = {
      for (final name in names)
        if (_others.contains(name) ||
            (factory.interceptors != null && !_own.contains(name)))
          beans.getBeanByName(name),
    };
    final sorted = [
      for (final bean in beans.getSortedBeans<RequestInterceptor>())
        if (!excluded.any((other) => identical(other, bean))) bean,
    ];
    if (factory.interceptors case final given?) {
      return [
        ...given,
        for (final bean in sorted)
          if (own.any((other) => identical(other, bean))) bean,
      ];
    }
    return sorted;
  }

  /// The client's own bean of [T], else [given], else the application's
  /// only (or primary) one; `null` when there is none. Throws a
  /// [StateError] when several beans qualify and none is primary.
  T? single<T extends Object>(T? given) {
    final beans = _beans;
    if (beans == null) {
      return given;
    }
    final names = beans.getBeanNamesForType(T);
    final own = [
      for (final name in names)
        if (_own.contains(name)) name,
    ];
    if (own.isNotEmpty) {
      return beans.getBeanByName(_pick(beans, own, 'own')) as T;
    }
    if (given != null) {
      return given;
    }
    final application = [
      for (final name in names)
        if (!_others.contains(name)) name,
    ];
    if (application.isEmpty) {
      return null;
    }
    return beans.getBeanByName(_pick(beans, application, 'application')) as T;
  }

  String _pick(
    ConfigurableListableBeanFactory beans,
    List<String> names,
    String what,
  ) {
    if (names.length == 1) {
      return names.single;
    }
    final primary = [
      for (final name in names)
        if (beans.containsBeanDefinition(name) &&
            beans.getBeanDefinition(name).primary)
          name,
    ];
    if (primary.length == 1) {
      return primary.single;
    }
    _fail('several $what beans of one type: ${names.join(', ')}');
  }

  /// The bean that a [property] names with [reference]: a bean name, or
  /// a class name (`com.example.Audit` or `Audit`; the package part is
  /// ignored) matching the class of exactly one bean of [T]. Throws a
  /// [StateError] naming the property otherwise.
  T named<T extends Object>(String reference, String property) {
    final beans = _beans;
    final where =
        'spring.cloud.openfeign.client.config.'
        '${client.configKey}.$property';
    if (beans == null) {
      _fail('$where=$reference: no bean factory to look it up');
    }
    if (beans.containsBean(reference)) {
      final bean = beans.getBeanByName(reference);
      if (bean is! T) {
        _fail("$where=$reference: the bean '$reference' is not a $T");
      }
      return bean;
    }
    final simple = reference.substring(reference.lastIndexOf('.') + 1);
    // By the class of the bean (or the type of its definition).
    final matches = [
      for (final MapEntry(key: name, value: bean)
          in beans.getBeansOfType<T>().entries)
        if (_simpleName(bean.runtimeType) == simple ||
            (beans.containsBeanDefinition(name) &&
                _simpleName(beans.getBeanDefinition(name).beanType) == simple))
          name,
    ];
    if (matches.length != 1) {
      _fail(
        matches.isEmpty
            ? '$where=$reference: no $T bean with this name or class'
            : '$where=$reference: several beans of this class: '
                  '${matches.join(', ')}',
      );
    }
    return beans.getBeanByName(matches.single) as T;
  }

  static String _simpleName(Type type) {
    final name = '$type';
    final generic = name.indexOf('<');
    return generic < 0 ? name : name.substring(0, generic);
  }
}
