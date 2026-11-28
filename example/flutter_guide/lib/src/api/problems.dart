import 'dart:convert';

import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The field errors of a 400 `application/problem+json` answer to a
/// `@Valid` body, as the server's web starter writes them:
/// `{"status": 400, "errors": [{"field": "isbn", "message": "..."}]}`.
/// Field name → message; empty when the body is no such problem.
Map<String, String> fieldErrorsOf(RestClientResponseException error) {
  try {
    final problem = ProblemDetail.fromJson(
      jsonDecode(error.bodyText) as Map<String, Object?>,
    );
    return {
      for (final entry
          in (problem.properties['errors'] as List<Object?>? ?? const []))
        if (entry case {'field': final String field, 'message': final String m})
          field: m,
    };
  } on FormatException {
    return const {};
  } on TypeError {
    return const {};
  }
}

/// The `detail` of a problem answer, else the status line.
String problemDetailOf(RestClientResponseException error) {
  try {
    final json = jsonDecode(error.bodyText);
    if (json is Map<String, Object?> && json['detail'] is String) {
      return json['detail']! as String;
    }
  } on FormatException {
    // not JSON: the status below
  }
  return 'HTTP ${error.statusCode}';
}
