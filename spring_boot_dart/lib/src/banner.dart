import 'package:spring_boot_dart/src/version.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Where `SpringApplication` prints the banner, like Spring Boot's
/// `Banner.Mode` (`spring.main.banner-mode`).
enum BannerMode {
  /// No banner.
  off,

  /// Printed to the console (`print`; Boot's `System.out`).
  console,

  /// Logged at INFO (logger `spring_boot_dart.SpringApplication`).
  log,
}

/// The banner printed when the application starts, like Spring Boot's
/// `Banner`. Pass one as `SpringApplication(banner:)`; a
/// `classpath:banner.txt` (or `spring.banner.location`) wins over it, like
/// in Boot.
///
/// ```dart
/// final class TextBanner implements Banner {
///   const TextBanner();
///
///   @override
///   void printBanner(Environment environment, void Function(String) out) =>
///       out('== Shop ==');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// app.setBanner((environment, sourceClass, out) -> out.println("== Shop =="));
/// ```
abstract interface class Banner {
  /// Writes the banner through [out], one call per line or block.
  void printBanner(Environment environment, void Function(String text) out);
}

/// The default banner, like Spring Boot's `SpringBootBanner`.
final class SpringBootBanner implements Banner {
  /// The default banner.
  const SpringBootBanner();

  static const _lines = [
    r"  .   ____          _            __ _ _",
    r" /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \",
    r"( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \",
    r" \\/  ___)| |_)| | | | | || (_| |  ) ) ) )",
    r"  '  |____| .__|_| |_|_| |_\__, | / / / /",
    r" =========|_|==============|___/=/_/_/_/",
  ];

  @override
  void printBanner(Environment environment, void Function(String text) out) {
    const name = ' :: Spring Boot for Dart :: ';
    const version = ' (v$springBootVersion)';
    out(
      '\n${_lines.join('\n')}\n\n'
      '$name${version.padLeft(42 - name.length)}\n',
    );
  }
}

/// A banner read from a text resource, like Spring Boot's
/// `ResourceBanner`: `${...}` placeholders are resolved against the
/// environment (unresolvable ones are kept), plus `spring-boot.version`
/// and `spring-boot.formatted-version` (` (v0.1.7)`).
final class ResourceBanner implements Banner {
  /// The banner in [resource].
  const ResourceBanner(this.resource);

  /// The banner text.
  final Resource resource;

  @override
  void printBanner(Environment environment, void Function(String text) out) {
    final text = resource
        .readAsStringSync()
        .replaceAll(r'${spring-boot.version}', springBootVersion)
        .replaceAll(
          r'${spring-boot.formatted-version}',
          ' (v$springBootVersion)',
        );
    out(environment.resolvePlaceholders(text));
  }
}
