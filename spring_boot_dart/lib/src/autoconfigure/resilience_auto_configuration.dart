/// The source of the `retryAdvisor` and the `concurrencyLimitAdvisor`, the
/// beans that put `@Retryable` and `@ConcurrencyLimit` into effect (in
/// `springBootResilienceAutoConfiguration`, in the build only with
/// `spring.resilience.enabled: true`).
///
/// Spring (Java): `@EnableResilientMethods`
/// (`ResilientMethodsConfiguration`).
const resilienceSource = 'package:spring_boot_dart#ResilienceAutoConfiguration';
