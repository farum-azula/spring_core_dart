## 0.1.1

- Hot reload: `SpringApplication(fingerprint:)`, `reload` / `reloadAsync` keep the running context when the generated code is unchanged and restart it with the same arguments otherwise; `runners: false` skips `ApplicationRunner` / `CommandLineRunner` beans after such a restart.
- Example on pub.dev (`example/`) and a description within 180 characters.
- Failure reports point to `lib/resources/application.properties` and suggest `@Lazy()` for dependency cycles.

## 0.1.0

Initial version.

- `@SpringBootApplication` (with `spring_core_dart_generator`: package-wide
  scan and a generated `runApplication`), `SpringApplication.run` /
  `runAsync`.
- `@ConfigurationProperties` binding (kebab-case, camelCase and environment
  variable names) with validation.
- `@AutoConfiguration`, `@ConditionalOnProperty`, `@ConditionalOnBean`,
  `@ConditionalOnMissingBean`.
- Starters: `@AutoConfigurationModule` in `lib/spring_auto_configuration.dart`,
  discovered by the generator in all dependencies;
  `MessageSourceAutoConfiguration`; `ConditionalOnMissingBean.named`.
- `AutoConfigurationModule(requires:)` with a build-time compatibility
  check against `springBootVersion`.
- Generated `runApplicationAsync` for asynchronous config (Flutter assets).
- `ApplicationArguments`, `ApplicationRunner`, `CommandLineRunner` (both
  kinds sorted together by order, a bean implementing both called as
  both), startup line and failure analysis reports.
- `logging.level.root`, `logging.level.<logger>`, `logging.group.*` and
  `LOGGING_LEVEL_*` variables applied to `SpringLog`
  (`SpringApplication.applyLoggingLevels`).
- `SpringApplication(initializers:)` (`ApplicationContextInitializer`) and
  `run(args, properties:)` with the highest precedence.
