/// Reactive state in the beans of Spring Boot Flutter apps.
///
/// - `@Signal()` on a field of a component: its readers are told when it
///   is assigned;
/// - `@Computed()` on a getter: a value kept until what it read changes,
///   also from a `Future` or a `Stream` (`books.state`, `books.refresh()`);
/// - `@Effect()` on a method: run again when what it read changes;
/// - `untracked` and `batch`, for a read that is not followed and for
///   several changes told as one.
library;

export 'package:signals_core/signals_core.dart' show batch;

export 'src/follow_keeper.dart' show untracked;

export 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

export 'src/annotations.dart';
export 'src/async_extensions.dart';
export 'src/async_value.dart';
export 'src/debug/signals_section.dart';
export 'src/followed_collections.dart';
export 'src/properties/signals_properties.dart';
export 'src/signal_bean.dart';
export 'src/signal_members.dart';
export 'src/signals_advice.dart';
export 'src/signals_processors.dart';
export 'src/widgets/async_view.dart';
export 'src/widgets/signal_build_tracker.dart';
export 'src/widgets/watch.dart';
