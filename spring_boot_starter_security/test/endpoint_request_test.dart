// EndpointRequest: matchers of the actuator's endpoints, read from the
// target the actuator starter records on the request; and the roles of an
// Authentication for the actuator's `when-authorized`.
import 'package:spring_boot_actuator/spring_boot_actuator.dart'
    show EndpointId, EndpointRequestTarget, PrincipalRoleChecker;
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

ServerHttpRequest request([EndpointRequestTarget? target]) {
  final request = MockServerHttpRequest(HttpMethod.get, '/anything');
  if (target != null) {
    request.attributes[EndpointRequestTarget.attribute] = target;
  }
  return request;
}

ServerHttpRequest endpoint(String id) =>
    request(EndpointRequestTarget.endpoint(EndpointId.of(id)));

final ServerHttpRequest links = request(const EndpointRequestTarget.links());

void main() {
  group('EndpointRequest', () {
    test('toAnyEndpoint: every endpoint and the links', () {
      final matcher = EndpointRequest.toAnyEndpoint();
      expect(matcher.matches(endpoint('health')), isTrue);
      expect(matcher.matches(endpoint('mappings')), isTrue);
      expect(matcher.matches(links), isTrue);
      expect(matcher.matches(request()), isFalse);
      expect(matcher.matcher(endpoint('health')).isMatch, isTrue);
    });

    test('to: the endpoints named, by id without case or dashes', () {
      final matcher = EndpointRequest.to(['health', 'Info']);
      expect(matcher.matches(endpoint('health')), isTrue);
      expect(matcher.matches(endpoint('info')), isTrue);
      expect(matcher.matches(endpoint('mappings')), isFalse);
      expect(matcher.matches(links), isFalse);
      expect(
        EndpointRequest.to(['my-thing']).matches(endpoint('mything')),
        isTrue,
      );
    });

    test('excluding and excludingLinks', () {
      final matcher = EndpointRequest.toAnyEndpoint().excluding(['health']);
      expect(matcher.matches(endpoint('health')), isFalse);
      expect(matcher.matches(endpoint('info')), isTrue);
      expect(matcher.matches(links), isTrue);
      final noLinks = matcher.excludingLinks();
      expect(noLinks.matches(links), isFalse);
      expect(noLinks.matches(endpoint('info')), isTrue);
      expect(
        EndpointRequest.to(['health', 'info'])
            .excluding(['info'])
            .matches(
              endpoint('info'),
            ),
        isFalse,
      );
    });

    test('toLinks: the discovery page only', () {
      final matcher = EndpointRequest.toLinks();
      expect(matcher.matches(links), isTrue);
      expect(matcher.matches(endpoint('health')), isFalse);
      expect(matcher.matches(request()), isFalse);
    });

    test('descriptions for the logs', () {
      expect(
        '${EndpointRequest.toAnyEndpoint().excluding(['env'])}',
        'EndpointRequest [any excluding env, links]',
      );
      expect('${EndpointRequest.to(['health'])}', 'EndpointRequest [health]');
    });
  });

  group('AuthenticationRoleChecker', () {
    const checker = AuthenticationRoleChecker();
    final admin = UsernamePasswordAuthenticationToken.authenticated(
      'root',
      null,
      [SimpleGrantedAuthority('ROLE_ADMIN'), SimpleGrantedAuthority('audit')],
    );

    test('ROLE_ADMIN is the role ADMIN; an authority counts as itself', () {
      expect(checker, isA<PrincipalRoleChecker>());
      expect(checker.isUserInRole(admin, 'ADMIN'), isTrue);
      expect(checker.isUserInRole(admin, 'ROLE_ADMIN'), isTrue);
      expect(checker.isUserInRole(admin, 'audit'), isTrue);
      expect(checker.isUserInRole(admin, 'USER'), isFalse);
    });

    test('another kind of principal has no role', () {
      expect(checker.isUserInRole(_Plain(), 'ADMIN'), isFalse);
    });
  });
}

final class _Plain implements Principal {
  @override
  String get name => 'plain';
}
