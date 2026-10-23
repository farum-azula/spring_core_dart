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

/// Spring Boot's `ExitCodeGenerators`: the highest positive (or lowest
/// negative) code wins; a generator that throws makes it `1` unless another
/// code was found.
final class ExitCodeGenerators {
  final _generators = <ExitCodeGenerator>[];

  /// Adds [generators].
  void addAll(Iterable<ExitCodeGenerator> generators) =>
      _generators.addAll(generators);

  /// Adds a generator that asks each of [mappers] for the code of
  /// [exception].
  void addMapped(Object exception, Iterable<ExitCodeExceptionMapper> mappers) =>
      _generators.addAll([
        for (final mapper in mappers) _Mapped(exception, mapper),
      ]);

  /// The exit code of all the generators.
  int get exitCode {
    var exitCode = 0;
    for (final generator in _generators) {
      try {
        final value = generator.getExitCode();
        if ((value > 0 && value > exitCode) ||
            (value < 0 && value < exitCode)) {
          exitCode = value;
        }
      } catch (_) {
        exitCode = exitCode != 0 ? exitCode : 1;
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
