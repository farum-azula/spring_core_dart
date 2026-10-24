import 'package:spring_core_dart/spring_core_dart.dart';

/// Supplies the exit code of the process, like Spring Boot's
/// `ExitCodeGenerator`: a bean (or one passed to `SpringApplication.exit`)
/// that returns a non-zero code when the application should end with an
/// error.
///
/// ```dart
/// @Component()
/// class FailedJobs implements ExitCodeGenerator {
///   int failed = 0;
///   @override
///   int getExitCode() => failed > 0 ? 2 : 0;
/// }
///
/// exit(SpringApplication.exit(context)); // dart:io
/// ```
///
/// Spring (Java):
/// ```java
/// System.exit(SpringApplication.exit(context));
/// ```
abstract interface class ExitCodeGenerator {
  /// The exit code, `0` for success.
  int getExitCode();
}

/// Maps the exception that stopped the application to an exit code, like
/// Spring Boot's `ExitCodeExceptionMapper`. Beans of this type are asked
/// when a run fails after the context was started (see
/// `SpringApplication.exitCodeOf`).
abstract interface class ExitCodeExceptionMapper {
  /// The exit code for [exception], `0` when this mapper has none.
  int getExitCode(Object exception);
}

/// Published by `SpringApplication.exit` (and a failed run) when the exit
/// code is not `0`, like Spring Boot's `ExitCodeEvent`.
class ExitCodeEvent extends ApplicationEvent {
  /// The [exitCode] chosen for the application of [source] (its context).
  ExitCodeEvent(super.source, this.exitCode);

  /// The exit code.
  final int exitCode;
}

/// Spring Boot's `ExitCodeGenerators` (3.0+): the generators sorted by
/// order (`Ordered`, else the order given when adding, stable otherwise);
/// the first non-zero code wins. A generator that throws gives `1`, which
/// a later generator's code replaces (as in Boot).
final class ExitCodeGenerators {
  final _generators = <(ExitCodeGenerator, int?)>[];

  /// Adds [generator] with its `@Order` value [order] (used when it is not
  /// `Ordered`).
  void add(ExitCodeGenerator generator, [int? order]) =>
      _generators.add((generator, order));

  /// Adds [generators].
  void addAll(Iterable<ExitCodeGenerator> generators) =>
      generators.forEach(add);

  /// Adds a generator that asks [mapper] for the code of [exception].
  void addMapped(
    Object exception,
    ExitCodeExceptionMapper mapper, [
    int? order,
  ]) => _generators.add((
    _Mapped(exception, mapper),
    OrderComparator.orderOf(mapper, order),
  ));

  /// The exit code of all the generators.
  int get exitCode {
    var exitCode = 0;
    final sorted = OrderComparator.sort<(ExitCodeGenerator, int?)>(
      _generators,
      (entry) => OrderComparator.orderOf(entry.$1, entry.$2),
    );
    for (final (generator, _) in sorted) {
      try {
        exitCode = generator.getExitCode();
        if (exitCode != 0) {
          break;
        }
      } catch (_) {
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
