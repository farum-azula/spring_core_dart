import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// In a Supabase Edge Function: a request whose bearer token is the
/// project's anon key goes on without its `Authorization` header (the
/// bean `supabaseAnonKeyFilter`, before every other filter).
///
/// The Supabase clients send the anon key as the bearer token of everyone
/// who is not signed in (`supabase.functions.invoke`, this family's
/// `@EdgeFunctions`). The key is public, the same for every visitor and
/// names nobody: such a request is anonymous. Without the filter the
/// resource server would answer 401 to it, also on a path open to
/// everyone, because the key is not a user's token.
///
/// Nothing is gained by sending the key: the request is treated exactly
/// as one without the header, which any client can send. A user's token,
/// the service role key and every other value reach the security chain
/// unchanged.
///
/// `spring.edge.supabase.anon-key-as-anonymous: false` removes the filter.
final class SupabaseAnonKeyFilter implements WebFilter, Ordered {
  /// The filter for the project whose anon key is [anonKey].
  SupabaseAnonKeyFilter(String anonKey) : _anonKey = anonKey.trim();

  final String _anonKey;

  /// Before the rate limiter and the security chain.
  @override
  int get order => Ordered.highestPrecedence + 100;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    if (_anonKey.isEmpty) {
      return chain.doFilter(request, response);
    }
    final values = request.headers.getAll(HttpHeaders.authorizationHeader);
    if (values.length != 1) {
      return chain.doFilter(request, response);
    }
    final value = values.single.trim();
    if (value.length < 7 ||
        value.substring(0, 7).toLowerCase() != 'bearer ' ||
        value.substring(7).trim() != _anonKey) {
      return chain.doFilter(request, response);
    }
    return chain.doFilter(_WithoutAuthorization(request), response);
  }
}

final class _WithoutAuthorization extends ServerHttpRequestDecorator {
  _WithoutAuthorization(super.delegate)
    : headers = HttpHeaders.readOnly(
        delegate.headers.copy()..remove(HttpHeaders.authorizationHeader),
      );

  @override
  final HttpHeaders headers;
}
