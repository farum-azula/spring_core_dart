import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';

/// The host of `spring.supabase.url` on the allow list of the
/// application's HTTP transport (the bean `supabaseAllowedAddresses`):
/// the project was given by hand, so its REST API, Auth, Storage and Edge
/// Functions are reached without listing it in
/// `spring.http.clients.allowed-addresses` too. A local stack's
/// `http://127.0.0.1:54321` is the loopback address itself, and so is
/// allowed as well. Nothing is added while the property is not set.
final class SupabaseAllowedAddresses implements AllowedAddressesContributor {
  /// The project of [properties].
  const SupabaseAllowedAddresses(this.properties);

  /// The `spring.supabase.*` properties.
  final SupabaseProperties properties;

  @override
  Iterable<String> allowedAddresses() {
    final host = Uri.tryParse(properties.url?.trim() ?? '')?.host ?? '';
    return host.isEmpty ? const [] : [host];
  }
}
