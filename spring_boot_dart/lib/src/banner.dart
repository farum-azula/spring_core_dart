import 'package:spring_boot_dart/src/version.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Where the startup banner goes: the console, the log, or nowhere.
///
/// Usually set with the property `spring.main.banner-mode` (`off`,
/// `console` or `log`), which wins over `SpringApplication(bannerMode:)`.
/// Any other property value fails the start. `log` is useful when the
/// console is not read but the log file is.
///
/// ```properties
/// # A service whose output goes to a log collector: no ASCII art.
/// spring.main.banner-mode=off
/// ```
///
/// Spring (Java): `Banner.Mode`, set the same way.
enum BannerMode {
  /// No banner is printed. The property value `false` means this too.
  off,

  /// Printed with `print` (Spring Boot's `System.out`). The default.
  console,

  /// Logged at INFO under the logger `spring_boot_dart.SpringApplication`,
  /// so it goes wherever the log goes (a log file, for example).
  log,
}

/// Text printed once when the application starts, before the context is
/// created.
///
/// By default it is the Spring logo ([SpringBootBanner]). Most
/// applications that want their own banner just add a
/// `lib/resources/banner.txt` file (or point `spring.banner.location` at
/// one), which is printed as a [ResourceBanner]. Implement this interface
/// when the banner is computed, for example from properties, and pass it
/// as `SpringApplication(banner:)`; a banner file still wins over it.
///
/// ```dart
/// // The shop's name and stage, from the configuration.
/// final class ShopBanner implements Banner {
///   const ShopBanner();
///
///   @override
///   void printBanner(Environment environment, void Function(String) out) =>
///       out('== ${environment.getProperty('shop.name')} '
///           '(${environment.activeProfiles.join(', ')}) ==');
/// }
///
/// SpringApplication([appBeans], banner: const ShopBanner()).run(args);
/// ```
///
/// Spring (Java):
/// ```java
/// app.setBanner((environment, sourceClass, out) -> out.println("== Shop =="));
/// ```
abstract interface class Banner {
  /// Writes the banner through [out], which prints or logs it depending on
  /// the [BannerMode]. Call [out] once per line or once for the whole text.
  /// [environment] is fully prepared: config files and profiles are
  /// loaded.
  void printBanner(Environment environment, void Function(String text) out);
}

/// The banner printed when the application sets none: the Spring logo in
/// ASCII art and the `spring_boot_dart` version.
///
/// There is no reason to create it yourself, except to print it from
/// another [Banner].
///
/// Spring (Java): `SpringBootBanner`.
final class SpringBootBanner implements Banner {
  /// The default banner; it has no settings.
  const SpringBootBanner();

  static const _lines = [
    '  .   ____          _            __ _ _',
    r" /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \",
    r"( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \",
    r' \\/  ___)| |_)| | | | | || (_| |  ) ) ) )',
    r"  '  |____| .__|_| |_|_| |_\__, | / / / /",
    ' =========|_|==============|___/=/_/_/_/',
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

/// A banner whose text comes from a file, such as
/// `lib/resources/banner.txt`.
///
/// `SpringApplication` uses it by itself when `classpath:banner.txt` (or
/// the file named by `spring.banner.location`) exists, so applications
/// only write the file. `${...}` placeholders in the text are resolved
/// against the environment, and unresolvable ones are printed as they
/// are. Two more are known: `${spring-boot.version}` (`0.4.0`) and
/// `${spring-boot.formatted-version}` (` (v0.4.0)`).
///
/// ```text
/// ${spring.application.name}${spring-boot.formatted-version}
/// ```
///
/// The file is read synchronously when the banner is printed. In Flutter,
/// where assets can only be read asynchronously, `runAsync` reads it
/// first.
///
/// Spring (Java): `ResourceBanner`, with the same placeholders.
final class ResourceBanner implements Banner {
  /// A banner that prints the text of [resource].
  const ResourceBanner(this.resource);

  /// The file holding the banner text; it must be readable synchronously
  /// when the banner is printed.
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
