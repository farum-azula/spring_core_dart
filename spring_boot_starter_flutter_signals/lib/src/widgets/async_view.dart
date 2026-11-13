import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_signals/src/async_extensions.dart';
import 'package:spring_boot_starter_flutter_signals/src/async_value.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/watch.dart';

/// Shows an asynchronous `@Computed` value: its data, the load, or the
/// failure.
///
/// ```dart
/// AsyncView(
///   () => context.catalog.books,
///   data: (context, books) => BookList(books),
/// )
/// ```
///
/// The value is read inside the view (hence the function), so the view
/// builds again by itself when the load moves on and when the future
/// changes (the genre it depends on was assigned); the widget around it
/// is not built again.
///
/// While a value is asked for again with `refresh()` the last one stays
/// on screen. Without [loading] nothing is shown during the first load;
/// without [error] the failure's text is.
class AsyncView<T> extends StatelessWidget {
  /// The view of the future [value] gives.
  const AsyncView(
    Future<T> Function() value, {
    required this.data,
    this.loading,
    this.error,
    super.key,
  }) : _future = value,
       _stream = null;

  /// The view of the stream [value] gives: its last event.
  const AsyncView.stream(
    Stream<T> Function() value, {
    required this.data,
    this.loading,
    this.error,
    super.key,
  }) : _stream = value,
       _future = null;

  final Future<T> Function()? _future;
  final Stream<T> Function()? _stream;

  /// Builds the value.
  final Widget Function(BuildContext context, T value) data;

  /// Builds the first load; nothing by default.
  final WidgetBuilder? loading;

  /// Builds a failure; its text by default.
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  )?
  error;

  @override
  Widget build(BuildContext context) => Watch((context) {
    final AsyncValue<T> state = switch (_future) {
      final future? => future().state,
      null => _stream!().state,
    };
    return state.when(
      data: (value) => data(context, value),
      loading: () => loading?.call(context) ?? const SizedBox.shrink(),
      error: (failure, stackTrace) =>
          error?.call(context, failure, stackTrace) ??
          Text('$failure', textDirection: TextDirection.ltr),
    );
  });
}
