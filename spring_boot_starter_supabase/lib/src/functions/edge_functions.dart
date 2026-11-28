import 'dart:async';

import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_credentials_interceptor.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/http/timed_request.dart';

/// Marks an interface whose methods call the project's Edge Functions: an
/// HTTP service interface whose methods are `POST` unless they say
/// otherwise. Import it into the group [group], whose `RestClient` the
/// starter points at `<spring.supabase.url>/functions/v1` with the key
/// and the token of `SupabaseCredentials`; the generator writes its bean.
///
/// ```dart
/// @EdgeFunctions()
/// abstract interface class Functions {
///   @EdgeFunction('send-invite')
///   Future<InviteResult> sendInvite(@RequestBody() Invite invite);
///
///   @EdgeFunction('stats', method: HttpMethod.get)
///   Future<Stats> stats(@RequestParam('from') DateTime from);
/// }
///
/// @SpringBootApplication()
/// @ImportHttpServices(group: EdgeFunctions.group, types: [Functions])
/// void main(List<String> args) => runApplication(args);
/// ```
///
/// Parameters (`@RequestBody`, `@RequestParam`, `@RequestHeader`,
/// `@PathVariable`, `@CookieValue`), results (JSON, `String`, a file as
/// `Uint8List`, `ResponseEntity<T>`, an `EventStream<T>` of server-sent
/// events, a `Stream<List<int>>` of the body as it arrives) and errors (a
/// `RestClientResponseException` for an error status, a
/// `ResourceAccessException` for no answer) are those of HTTP service
/// interfaces. The group's settings are
/// `spring.http.serviceclient.supabase-functions.*`, except its base URL
/// and its redirects: a call goes to the project only and never follows a
/// redirect, which could carry the token to another host.
class EdgeFunctions extends HttpExchange {
  /// Marks the interface.
  const EdgeFunctions() : super.of(method: _post);

  /// The HTTP service group of the Edge Functions interfaces, which the
  /// starter configures (`spring.http.serviceclient.supabase-functions.*`
  /// for the rest of its settings).
  static const String group = 'supabase-functions';

  static const HttpMethod _post = HttpMethod.post;
}

/// Calls the Edge Function [name] (on a method of an [EdgeFunctions]
/// interface): an `@HttpExchange` of the function's path, `POST` unless
/// [method] says otherwise.
///
/// `${property}` in the name is resolved from the configuration; a part
/// that changes per call is a `{name}` filled by a `@PathVariable()`
/// parameter, as in any HTTP service interface.
///
/// ```dart
/// @EdgeFunction('reports/{year}', method: HttpMethod.get)
/// Future<Report> report(@PathVariable() int year);
/// ```
class EdgeFunction extends HttpExchange {
  /// The function [name], called with [method]; [headers] (`'Name=value'`),
  /// [accept] and [contentType] as on `@HttpExchange`.
  const EdgeFunction(
    String name, {
    HttpMethod method = HttpMethod.post,
    super.headers,
    super.accept,
    super.contentType,
  }) : super.of(url: name, method: method);

  /// The function's name, as deployed (its path under
  /// `/functions/v1`).
  String get name => url;
}

/// Points the HTTP service group [EdgeFunctions.group] at the project's
/// Edge Functions (the bean `edgeFunctionsGroupConfigurer`): the base URL
/// `<spring.supabase.url>/functions/v1`, no redirects, an
/// [EdgeFunctionsInterceptor] and, last, the key and the token of
/// `SupabaseCredentials` (with `spring.supabase.functions.region` as
/// `x-region`). Declare a bean of this type to replace it, for instance
/// with a [retryTemplate].
final class EdgeFunctionsGroupConfigurer
    implements RestClientHttpServiceGroupConfigurer {
  /// The configurer of the functions of [http]'s project.
  EdgeFunctionsGroupConfigurer({
    required this.http,
    this.retryTemplate,
    ObservationRegistry? observations,
  }) : observations = observations ?? ObservationRegistry.noop;

  /// The project.
  final SupabaseHttp http;

  /// What tries a failed call again (see [EdgeFunctionsInterceptor]);
  /// `null`, the default, for never.
  final RetryTemplate? retryTemplate;

  /// Where each call is recorded (`supabase.functions`).
  final ObservationRegistry observations;

  @override
  void configureGroups(HttpServiceGroupBuilders groups) => groups
      .filterByName(const [EdgeFunctions.group])
      .forEachClient((_, builder) {
        final base = http.url(SupabaseService.functions, '');
        final properties = http.properties;
        final region = properties.functions.region?.trim();
        builder
            .baseUrl('$base')
            // A redirect could carry the key and the token to another host.
            .followRedirects(false)
            .sensitiveHeaders(const ['apikey'])
            .requestInterceptor(
              EdgeFunctionsInterceptor(
                timeout: properties.functions.timeout ?? properties.timeout,
                basePath: base.path,
                retryTemplate: retryTemplate,
                observations: observations,
              ),
            )
            .requestInterceptor(
              SupabaseCredentialsInterceptor(
                credentials: http.credentials,
                origin: http.baseUrl,
                headers: {
                  if (region != null && region.isNotEmpty) 'x-region': region,
                },
              ),
            );
      });
}

/// What every call of an [EdgeFunctions] interface goes through before
/// the key and the token are put on: an `Observation` named
/// `supabase.functions` with the function's name, the time limit
/// [timeout] (`spring.supabase.functions.timeout`, else
/// `spring.supabase.timeout`) for the whole call, its retries included,
/// and the retries of [retryTemplate].
///
/// Nothing is retried without a [retryTemplate]. With one, a call is tried
/// again as its policy allows when it got no answer (no connection, a
/// timeout before the limit) or an error status with a `Retry-After`
/// header (seconds or an HTTP date), after the pause the server asked for;
/// an error status without one is never retried. Each attempt passes the
/// interceptors after this one again, so a refreshed token reaches it. A
/// retry whose pause would end after [timeout] (or the deadline of the
/// code that calls) is not made: the last answer goes to the status
/// handlers as any other, the last failure to the caller.
///
/// ```dart
/// @Bean()
/// EdgeFunctionsGroupConfigurer edgeFunctionsGroupConfigurer(
///   SupabaseHttp http,
/// ) => EdgeFunctionsGroupConfigurer(
///   http: http,
///   retryTemplate: RetryTemplate(
///     retryPolicy: RetryPolicy.builder()
///         .maxRetries(2)
///         .delay(const Duration(milliseconds: 150))
///         .multiplier(1.5)
///         .build(),
///   ),
/// );
/// ```
final class EdgeFunctionsInterceptor implements ClientHttpRequestInterceptor {
  /// The interceptor of the calls under [basePath] (`/functions/v1`).
  EdgeFunctionsInterceptor({
    required this.timeout,
    required this.basePath,
    this.retryTemplate,
    ObservationRegistry? observations,
  }) : observations = observations ?? ObservationRegistry.noop;

  /// The longest a call may take, retries and pauses included.
  final Duration timeout;

  /// The path of the functions under the project's address.
  final String basePath;

  /// What tries a failed call again; `null` for never.
  final RetryTemplate? retryTemplate;

  /// Where each call is recorded.
  final ObservationRegistry observations;

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) {
    Future<HttpResponse> limited() {
      final template = retryTemplate;
      final outer = RequestDeadline.current;
      if (template != null) {
        // The retries see the deadline: one under the time limit.
        return RequestDeadline.run(
          timeout,
          () => _retried(template, request, body, execution),
        );
      }
      // One attempt: under an earlier deadline of the caller the client
      // applies that one, under none the request carries the limit.
      return switch (outer) {
        null => execution.execute(timedRequest(request, timeout), body),
        _ when outer.remaining <= timeout => execution.execute(request, body),
        _ => RequestDeadline.run(
          timeout,
          () => execution.execute(request, body),
        ),
      };
    }

    if (observations.isNoop) {
      return limited();
    }
    return observations
        .observation('supabase.functions')
        .lowCardinalityKeyValue('function', _function(request.url))
        .observe(limited);
  }

  // The deployed function: the first segment under [basePath].
  String _function(Uri url) {
    final path = url.path.startsWith(basePath)
        ? url.path.substring(basePath.length)
        : url.path;
    return path.split('/').firstWhere((s) => s.isNotEmpty, orElse: () => '');
  }

  Future<HttpResponse> _retried(
    RetryTemplate template,
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) async {
    final call = _Attempts();
    final retries = RetryTemplate(
      retryPolicy: _EdgeFunctionsRetryPolicy(template.retryPolicy, call),
      retryListener: template.retryListener,
    );
    try {
      return await retries.invoke(() async {
        final response = await execution.execute(request, body);
        final after = response.statusCode.isError
            ? retryAfter(response.headers[HttpHeaders.retryAfterHeader])
            : null;
        if (after == null) {
          return response;
        }
        call.answered(response, after);
        throw call.answer!;
      }, name: '${request.method.value} ${request.url.path}');
    } on RestClientResponseException catch (error) {
      if (identical(error, call.answer)) {
        return call.response!;
      }
      rethrow;
    }
  }

  /// The pause a `Retry-After` header [value] asks for: whole seconds, or
  /// an HTTP date (`Wed, 21 Oct 2026 07:28:00 GMT`); `null` when there is
  /// none or it is neither (`-5`), which is not retried.
  static Duration? retryAfter(String? value, {DateTime? now}) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (_seconds.firstMatch(text) case final match?) {
      final digits = match[1]!;
      return digits.length > 9
          ? _longest
          : Duration(seconds: int.parse(digits));
    }
    final match = _httpDate.firstMatch(text);
    if (match == null) {
      return null;
    }
    final month = _months.indexOf(match[2]!.toLowerCase()) + 1;
    if (month == 0) {
      return null;
    }
    final at = DateTime.utc(
      int.parse(match[3]!),
      month,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
    final pause = at.difference(now ?? DateTime.now());
    return pause.isNegative ? Duration.zero : pause;
  }

  static final _seconds = RegExp(r'^(\d+)(?:\.0*)?$');

  // A pause no deadline holds: the call is not retried.
  static const _longest = Duration(days: 365);

  static final _httpDate = RegExp(
    r'^(?:[A-Za-z]{3}, )?(\d{1,2}) ([A-Za-z]{3}) (\d{4}) '
    r'(\d{2}):(\d{2}):(\d{2}) (?:GMT|UTC|Z|\+0000)$',
  );

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
}

// What one call's attempts learnt: the last error answer that asked to be
// called again, and when.
final class _Attempts {
  RestClientResponseException? answer;
  HttpResponse? response;
  Duration? _retryAfter;

  void answered(HttpResponse response, Duration retryAfter) {
    this.response = response;
    answer = RestClientResponseException.of(response);
    _retryAfter = retryAfter;
  }

  // The pause the last answer asked for, once.
  Duration? takeRetryAfter() {
    final pause = _retryAfter;
    _retryAfter = null;
    return pause;
  }
}

// The application's policy, narrowed to what a call of a function may
// retry, with the pause of `Retry-After` instead of its own.
final class _EdgeFunctionsRetryPolicy implements RetryPolicy {
  _EdgeFunctionsRetryPolicy(this._policy, this._call);

  final RetryPolicy _policy;
  final _Attempts _call;

  @override
  bool shouldRetry(Object error) {
    final retryable =
        identical(error, _call.answer) ||
        (error is ResourceAccessException && error.isRetryable);
    return retryable && _policy.shouldRetry(error);
  }

  @override
  BackOff get backOff => _RetryAfterBackOff(_policy.backOff, _call);

  @override
  Duration get timeout => _policy.timeout;
}

final class _RetryAfterBackOff implements BackOff {
  _RetryAfterBackOff(this._backOff, this._call);

  final BackOff _backOff;
  final _Attempts _call;

  @override
  BackOffExecution start() => _RetryAfterExecution(_backOff.start(), _call);
}

final class _RetryAfterExecution implements BackOffExecution {
  _RetryAfterExecution(this._execution, this._call);

  final BackOffExecution _execution;
  final _Attempts _call;

  @override
  Duration? nextBackOff() {
    final pause = _execution.nextBackOff();
    final asked = _call.takeRetryAfter();
    return pause == null ? null : asked ?? pause;
  }
}
