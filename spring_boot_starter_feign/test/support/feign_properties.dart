import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_feign/src/config/config.dart';

/// What the starter does at startup: binds `spring.feign.client.*` of
/// [environment].
FeignProperties bindFeignProperties(ConfigurableEnvironment environment) {
  ConfigurationPropertySources.attach(environment);
  final binder = ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: feignConfigBeans.introspections),
  );
  return binder.postProcessBeforeInitialization(
    FeignProperties(),
    'feignProperties',
  ) as FeignProperties;
}
