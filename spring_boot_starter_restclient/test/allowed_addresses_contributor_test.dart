// AllowedAddressesContributor beans: what another starter was given by hand
// joins the transport's allow list; nothing else does.
import 'package:spring_boot_starter_restclient/spring_auto_configuration.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

void main() {
  test("the contributors' entries join the allow list", () {
    const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
        .withPropertyValues(['spring.http.clients.allowed-addresses=a.test'])
        .withBean<AllowedAddressesContributor>(
          () => const AllowedAddressesContributor.of([
            'https://id.partner.test/oauth2/token',
            '10.1.0.0/16',
          ]),
        )
        .run((context) {
          expect(context.startupFailure, isNull);
          final allowed = context.getBean<AllowedAddresses>()
            ..checkUrl(Uri.parse('https://a.test/'))
            ..checkUrl(Uri.parse('https://id.partner.test/x'))
            ..checkUrl(Uri.parse('http://10.1.2.3/'));
          expect(
            () => allowed.checkUrl(Uri.parse('https://partner.test/')),
            throwsA(isA<FilteredHostException>()),
          );
        });
  });
}
