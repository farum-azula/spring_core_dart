/// `RequestDeadline` and `RequestDeadlineExceededException` live in the
/// core (`package:spring_core_dart/core.dart`), so that the retries and
/// code without the web packages read the same deadline; this library
/// exports them for the code that imports them from here.
library;

export 'package:spring_core_dart/core.dart'
    show RequestDeadline, RequestDeadlineExceededException;
