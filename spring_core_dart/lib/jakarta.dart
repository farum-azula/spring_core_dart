/// The standard Java injection names, for code that prefers them to the
/// Spring ones: the JSR-330 `Provider<T>` (a bean looked up on each use)
/// and the JSR-250 annotations `@Resource` (inject by bean name) and
/// `@Priority` (rank beans of one type).
///
/// They are not part of `spring_core_dart.dart` because their names clash:
/// `Provider` with `package:provider`, `Resource` with this package's own
/// resource type. Import this library on its own, with a prefix where a
/// name clashes. Applications that use `ObjectProvider`, `@Autowired`,
/// `@Qualifier` and `@Order` do not need it.
///
/// ```dart
/// import 'package:spring_core_dart/jakarta.dart' as jakarta;
///
/// @Service()
/// class Reports {
///   // Two stores exist; the archive one is wanted here.
///   @jakarta.Resource(name: 'archiveStore')
///   late final Store store;
/// }
/// ```
library;

export 'package:spring_core_dart/src/beans/jakarta.dart';
