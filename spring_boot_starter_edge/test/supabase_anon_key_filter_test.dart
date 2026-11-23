// SupabaseAnonKeyFilter: only the project's exact anon key, as the one
// bearer token of the request, is taken away; every other Authorization
// value reaches the security chain unchanged.
import 'package:spring_boot_starter_edge/src/supabase_anon_key_filter.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

final class _Capture implements WebFilterChain {
  List<String>? seen;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    seen = request.headers.getAll(HttpHeaders.authorizationHeader);
  }
}

void main() {
  const anon = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig';

  Future<List<String>?> downstream(
    List<String> values, {
    String key = ' $anon ',
  }) async {
    final headers = HttpHeaders();
    for (final value in values) {
      headers.add(HttpHeaders.authorizationHeader, value);
    }
    final chain = _Capture();
    await SupabaseAnonKeyFilter(key).doFilter(
      MockServerHttpRequest(HttpMethod.get, '/x', headers: headers),
      MockServerHttpResponse(),
      chain,
    );
    return chain.seen;
  }

  test('the anon key as the bearer token is taken away', () async {
    expect(await downstream(['Bearer $anon']), isEmpty);
    expect(await downstream(['bearer $anon']), isEmpty);
    expect(await downstream(['Bearer    $anon  ']), isEmpty);
  });

  test('every other value goes on unchanged', () async {
    for (final values in [
      ['Bearer ${anon}x'],
      ['Bearer service-role'],
      ['Bearer $anon', 'Bearer user.jwt.x'],
      ['Bearer $anon, Bearer user.jwt.x'],
      ['DPoP $anon'],
      ['Bearer\t$anon'],
      [anon],
    ]) {
      expect(await downstream(values), values, reason: '$values');
    }
  });

  test('without an anon key nothing is taken away', () async {
    expect(await downstream(['Bearer '], key: '  '), ['Bearer ']);
  });

  test('before the rate limiter and the security chain', () {
    expect(
      SupabaseAnonKeyFilter(anon).order,
      lessThan(Ordered.highestPrecedence + 1000),
    );
  });
}
