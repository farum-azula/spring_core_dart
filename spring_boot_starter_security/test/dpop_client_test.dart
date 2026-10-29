// The OAuth2 client's DPoP proofs (DPoPProofBuilder, SoftwareDPoPKey)
// against this starter's resource server: proofs written by the client
// side, checked by the real filter chain of the JWT test application.
// The client package cannot depend on this one, so the interoperability
// of both halves is tested here.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/jwt.dart';
import 'app/jwt/keys.dart';
import 'support.dart';

Future<void> _app(Future<void> Function(MockMvc mvc) body) =>
    withApp(jwtSecurityBeans, (mvc, _) => body(mvc));

void main() {
  final key = SoftwareDPoPKey.generate();
  final proofs = DPoPProofBuilder(key);
  String boundToken([DPoPKey? to]) => testKeys.token(
    claims: {
      'cnf': {
        'jkt': JwkThumbprint.of((to ?? key).publicJwk),
      },
    },
  );

  test(
    "the client's proofs are accepted, GET and POST, query and all",
    () => _app((mvc) async {
      final token = boundToken();
      await mvc
          .get(
            '/api/me',
            headers: {
              'authorization': 'DPoP $token',
              'dpop': await proofs.build(
                method: 'GET',
                url: Uri.parse('http://localhost/api/me?verbose=1#top'),
                accessToken: token,
              ),
            },
          )
          .andExpect(
            status: 200,
            json: {
              'name': 'ada',
              'authorities': ['SCOPE_read'],
            },
          );
      await mvc
          .post(
            '/api/data',
            body: 'x',
            headers: {
              'authorization': 'DPoP $token',
              'dpop': await proofs.build(
                method: 'POST',
                url: Uri.parse('http://localhost/api/data'),
                accessToken: token,
              ),
            },
          )
          .andExpect(status: 200);
    }),
  );

  test(
    'a restored key (toJwk / fromJwk) still matches the bound token',
    () => _app((mvc) async {
      final token = boundToken();
      final restored = SoftwareDPoPKey.fromJwk(key.toJwk());
      await mvc
          .get(
            '/api/me',
            headers: {
              'authorization': 'DPoP $token',
              'dpop': await DPoPProofBuilder(restored).build(
                method: 'GET',
                url: Uri.parse('http://localhost/api/me'),
                accessToken: token,
              ),
            },
          )
          .andExpect(status: 200);
    }),
  );

  test(
    "the server refuses the client's proof for another request, token or "
    'key',
    () => _app((mvc) async {
      final token = boundToken();
      final url = Uri.parse('http://localhost/api/me');
      for (final (why, proof) in [
        (
          'another method',
          await proofs.build(method: 'POST', url: url, accessToken: token),
        ),
        (
          'another URL',
          await proofs.build(
            method: 'GET',
            url: Uri.parse('http://localhost/api/data'),
            accessToken: token,
          ),
        ),
        (
          'another token',
          await proofs.build(method: 'GET', url: url, accessToken: 'other'),
        ),
        ('no ath', await proofs.build(method: 'GET', url: url)),
        (
          'another key',
          await DPoPProofBuilder(
            SoftwareDPoPKey.generate(),
          ).build(method: 'GET', url: url, accessToken: token),
        ),
      ]) {
        final result = await mvc.get(
          '/api/me',
          headers: {'authorization': 'DPoP $token', 'dpop': proof},
        );
        expect(result.status, 401, reason: why);
        expect(
          result.header('www-authenticate'),
          startsWith('DPoP error="invalid_dpop_proof"'),
          reason: why,
        );
      }
    }),
  );

  test(
    'a proof is used once: the second request with it is refused',
    () => _app((mvc) async {
      final token = boundToken();
      final proof = await proofs.build(
        method: 'GET',
        url: Uri.parse('http://localhost/api/me'),
        accessToken: token,
      );
      final headers = {'authorization': 'DPoP $token', 'dpop': proof};
      await mvc.get('/api/me', headers: headers).andExpect(status: 200);
      await mvc.get('/api/me', headers: headers).andExpect(status: 401);
    }),
  );
}
