import 'package:spring_boot_starter_supabase/spring_auto_configuration.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import 'spring_gen/app/supabase_app.spring.dart';
import 'support.dart';

export 'app/supabase_app.dart';

/// [application] with the starter's auto-configurations and nothing
/// else: no project, no transport.
///
/// The generator gives a real application the order of the modules
/// (`before` / `after` of their `@AutoConfigurationModule`); a runner
/// needs it by hand.
ApplicationContextRunner supabaseRunner(BeanModule application) =>
    const ApplicationContextRunner()
        .withUserConfiguration(application)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterSupabaseDataAutoConfiguration,
          const AutoConfigurationModule(
            before: ['springBootStarterDataAutoConfiguration'],
          ),
        )
        .withAutoConfiguration(springBootStarterDataAutoConfiguration)
        .withAutoConfiguration(springBootStarterCacheAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterSupabaseAutoConfiguration,
          const AutoConfigurationModule(
            after: [
              'springBootStarterFeignAutoConfiguration',
              'springBootStarterWebsocketAutoConfiguration',
              'springBootStarterDataAutoConfiguration',
              'springSecurityCoreAutoConfiguration',
            ],
          ),
        );

/// The test application with the starter's auto-configurations.
ApplicationContextRunner baseRunner() => supabaseRunner($application);

/// The test application talking to [projectUrl] through [transport].
ApplicationContextRunner appRunner(
  MockHttpTransport transport, [
  List<String> properties = const [],
]) => baseRunner()
    .withPropertyValues([
      'spring.supabase.url=$projectUrl',
      'spring.supabase.anon-key=anon-key',
      'spring.supabase.service-role-key=service-key',
      ...properties,
    ])
    .withBean<HttpTransport>(() => transport);

/// Runs [body] as the signed-in user [name] (of the application's own
/// login: no token of Supabase).
Future<T> asUser<T>(String name, Future<T> Function() body) =>
    SecurityContextHolder.runWithContext(() {
      SecurityContextHolder.getContext().authentication =
          TestingAuthenticationToken(name, null);
      return body();
    });
