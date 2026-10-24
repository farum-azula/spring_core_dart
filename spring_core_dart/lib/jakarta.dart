/// Jakarta / JSR-330 / JSR-250 types whose names clash with other
/// libraries: `Provider<T>` injection points and the `@Resource`
/// annotation. Import with a prefix where a name clashes:
///
/// ```dart
/// import 'package:spring_core_dart/jakarta.dart' as jakarta;
/// ```
library;

export 'package:spring_core_dart/src/beans/jakarta.dart';
