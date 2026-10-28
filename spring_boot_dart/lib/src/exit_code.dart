import 'package:spring_core_dart/spring_core_dart.dart';

/// An object that decides the exit code of the process when the
/// application ends.
///
/// A batch job or a command-line tool reports its result through the exit
/// code: `0` when everything went well, something else when it did not,
/// so that a script or a scheduler can react. The code often depends on
/// what the beans saw while running. Such a bean implements this
/// interface, and `SpringApplication.exit(context)` closes the context
/// and returns the code for `main` to pass to `exit`. Generators are asked
/// in `@Order` / `Ordered` order and the first non-zero code wins.
///
/// The error that stops the start can implement it too (also when a
/// `BeansException` wraps it as its cause): the failed run then keeps its
/// code for `SpringApplication.exitCodeOf`.
///
/// ```dart
/// // Counts the jobs that failed while the program ran.
/// @Component()
/// class FailedJobs implements ExitCodeGenerator {
///   int failed = 0;
///
///   @override
///   int getExitCode() => failed > 0 ? 2 : 0;
/// }
///
/// Future<void> main(List<String> args) async {
///   final context = await runApplicationAsync(args); // runs the jobs
///   exit(SpringApplication.exit(context)); // dart:io
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// System.exit(SpringApplication.exit(context));
/// ```
abstract interface class ExitCodeGenerator {
  /// The exit code to end the process with: `0` for success, or `0` when
  /// this generator has nothing to say. A generator that throws counts as
  /// `1`, unless a later generator returns a non-zero code.
  int getExitCode();
}

/// Turns the error that made a runner fail into an exit code.
///
/// When an `ApplicationRunner` throws, the program should usually end with
/// a code that says what went wrong (a missing input file, a database
/// that cannot be reached), and the error often comes from a library that
/// knows nothing about exit codes. Declare a bean of this type: after a
/// failing runner, `SpringApplication` asks the mappers in `@Order` order,
/// publishes the first non-zero code as an [ExitCodeEvent] and keeps it
/// for `SpringApplication.exitCodeOf(error)`.
///
/// Mappers are only asked while the context is active, so for a failing
/// runner and not for a start that fails while the beans are created.
///
/// ```dart
/// @Component()
/// class ImportExitCodes implements ExitCodeExceptionMapper {
///   @override
///   int getExitCode(Object exception) =>
///       exception is FileSystemException ? 3 : 0;
/// }
///
/// Future<void> main(List<String> args) async {
///   try {
///     await runApplicationAsync(args);
///   } catch (error) {
///     exit(SpringApplication.exitCodeOf(error) ?? 1);
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// ExitCodeExceptionMapper importExitCodes() {
///   return exception -> exception instanceof IOException ? 3 : 0;
/// }
/// ```
abstract interface class ExitCodeExceptionMapper {
  /// The exit code for [exception], the error thrown by the runner. Return
  /// `0` for an error this mapper does not handle, so the next mapper is
  /// asked.
  int getExitCode(Object exception);
}

/// Announces that the application is about to end with a non-zero exit
/// code.
///
/// `SpringApplication.exit` publishes it before closing the context, and
/// so does a failed runner whose error was given a code. A bean can listen
/// to it to record why the program ended, while the other beans are still
/// available. A code of `0` is never published.
///
/// ```dart
/// @Component()
/// class ExitAudit {
///   @EventListener()
///   void onExit(ExitCodeEvent event) =>
///       print('ending with exit code ${event.exitCode}');
/// }
/// ```
///
/// Spring (Java): `ExitCodeEvent`.
class ExitCodeEvent extends ApplicationEvent {
  /// The event for [exitCode]; [source] is the application's context.
  ExitCodeEvent(super.source, this.exitCode);

  /// The exit code the application ends with; never `0`.
  final int exitCode;
}

/// Combines several [ExitCodeGenerator]s into one exit code; used by
/// `SpringApplication` and not exported.
///
/// The generators are sorted by order: an `Ordered` generator's own order,
/// otherwise the order given when it was added; generators with the same
/// order keep the order they were added in. The first non-zero code wins.
/// A generator that throws gives `1`, which a later generator's non-zero
/// code replaces.
///
/// Spring (Java): `ExitCodeGenerators` (Spring Boot 3.0+), with the same
/// rules.
final class ExitCodeGenerators {
  final _generators = <(ExitCodeGenerator, int?)>[];

  /// Adds [generator]. [order] is the `@Order` of its bean definition,
  /// used when the generator is not `Ordered`; without either it comes
  /// last.
  void add(ExitCodeGenerator generator, [int? order]) =>
      _generators.add((generator, order));

  /// Adds [generators] without an `@Order` value: each is placed by its
  /// own `Ordered` order, or last, in the given order.
  void addAll(Iterable<ExitCodeGenerator> generators) =>
      generators.forEach(add);

  /// Adds a generator that asks [mapper] for the code of [exception],
  /// ordered by the mapper's own order or [order].
  void addMapped(
    Object exception,
    ExitCodeExceptionMapper mapper, [
    int? order,
  ]) => _generators.add((
    _Mapped(exception, mapper),
    OrderComparator.orderOf(mapper, order),
  ));

  /// Asks the generators in order and returns the first non-zero code,
  /// `1` when one threw and none later had a code, or `0`. Each call asks
  /// them again.
  int get exitCode {
    var exitCode = 0;
    final sorted = OrderComparator.sort<(ExitCodeGenerator, int?)>(
      _generators,
      (entry) => OrderComparator.orderOf(entry.$1, entry.$2),
    );
    for (final (generator, _) in sorted) {
      try {
        // A later 0 keeps the 1 of a generator that threw (Boot).
        final value = generator.getExitCode();
        if (value != 0) {
          exitCode = value;
          break;
        }
      } on Object catch (_) {
        exitCode = 1;
      }
    }
    return exitCode;
  }
}

final class _Mapped implements ExitCodeGenerator {
  const _Mapped(this.exception, this.mapper);
  final Object exception;
  final ExitCodeExceptionMapper mapper;

  @override
  int getExitCode() => mapper.getExitCode(exception);
}
