import 'package:flutter/foundation.dart';

/// Where an asynchronous `@Computed` value is: being loaded, there, or
/// failed. What `books.state` gives for `Future<List<Book>> get books`,
/// and what an `AsyncView` shows.
///
/// ```dart
/// final state = context.catalog.books.state;
/// return state.when(
///   data: (books) => BookList(books),
///   loading: () => const Spinner(),
///   error: (error, _) => Text('$error'),
/// );
/// ```
///
/// While a value is asked for again with `refresh()` the last one stays:
/// [hasValue] and [isRefreshing] are both `true`, and [when] still gives
/// `data`. After a failure the last value is kept beside the [error] too.
@immutable
final class AsyncValue<T> {
  const AsyncValue._({
    required this.isLoading,
    required this.hasValue,
    required T? value,
    required this.error,
    required this.stackTrace,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _value = value;

  /// Nothing yet: the first load.
  const AsyncValue.loading()
    : this._(
        isLoading: true,
        hasValue: false,
        value: null,
        error: null,
        stackTrace: null,
      );

  /// The value [value].
  const AsyncValue.data(T value)
    : this._(
        isLoading: false,
        hasValue: true,
        value: value,
        error: null,
        stackTrace: null,
      );

  /// The failure [error].
  const AsyncValue.error(Object error, [StackTrace? stackTrace])
    : this._(
        isLoading: false,
        hasValue: false,
        value: null,
        error: error,
        stackTrace: stackTrace,
      );

  final T? _value;

  /// Whether a load is running: the first one, or a `refresh()`.
  final bool isLoading;

  /// Whether there is a value: of this load, or the last one kept while
  /// another runs or after it failed.
  final bool hasValue;

  /// What the last load threw; `null` when it did not fail.
  final Object? error;

  /// Where [error] was thrown.
  final StackTrace? stackTrace;

  /// The value, `null` when there is none (see [hasValue]: the value
  /// itself may be `null`).
  T? get value => _value;

  /// The value. Throws the [error] when the load failed without one, and a
  /// `StateError` while the first load runs.
  T get requireValue {
    if (hasValue) {
      return _value as T;
    }
    if (error case final error?) {
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
    }
    throw StateError('The value is still being loaded.');
  }

  /// Whether the last load failed.
  bool get hasError => error != null;

  /// Whether a load runs while the last value is still shown.
  bool get isRefreshing => isLoading && hasValue;

  /// One of three: [data] when there is a value (also while it is being
  /// refreshed), else [error] after a failure, else [loading].
  R when<R>({
    required R Function(T value) data,
    required R Function() loading,
    required R Function(Object error, StackTrace? stackTrace) error,
  }) {
    if (hasValue) {
      return data(_value as T);
    }
    if (this.error case final failure?) {
      return error(failure, stackTrace);
    }
    return loading();
  }

  /// The same state as a value of [R] (the untyped state kept by the
  /// starter, given the type of the member that asked).
  AsyncValue<R> cast<R>() => AsyncValue<R>._(
    isLoading: isLoading,
    hasValue: hasValue,
    value: hasValue ? _value as R : null,
    error: error,
    stackTrace: stackTrace,
  );

  /// This state with a load running; the value is kept when [keep].
  AsyncValue<T> toLoading({required bool keep}) => AsyncValue<T>._(
    isLoading: true,
    hasValue: keep && hasValue,
    value: keep ? _value : null,
    error: null,
    stackTrace: null,
  );

  /// This state after a failed load: the last value stays beside [error].
  AsyncValue<T> toError(Object error, StackTrace? stackTrace) =>
      AsyncValue<T>._(
        isLoading: false,
        hasValue: hasValue,
        value: _value,
        error: error,
        stackTrace: stackTrace,
      );

  @override
  bool operator ==(Object other) =>
      other is AsyncValue<T> &&
      other.isLoading == isLoading &&
      other.hasValue == hasValue &&
      other._value == _value &&
      other.error == error;

  @override
  int get hashCode => Object.hash(isLoading, hasValue, _value, error);

  @override
  String toString() => when(
    data: (value) => isLoading ? 'refreshing($value)' : 'data($value)',
    loading: () => 'loading',
    error: (error, _) => 'error($error)',
  );
}
