import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// A failure as a sentence for the screen, from the messages files.
String errorMessage(BuildContext context, Object error) => switch (error) {
  RetryableException() => context.message('error.offline'),
  AccessDeniedException() => context.message('error.denied'),
  AuthenticationException() => context.message('error.login'),
  FeignException(:final status) => context.message(
    'error.status',
    args: [status],
  ),
  _ => '$error',
};

/// A price, with two decimals.
String price(double value) => value.toStringAsFixed(2);
