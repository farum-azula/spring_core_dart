/// The beans the edge starter adds to an application: the fetch server of
/// a function, the runtime and the list of what works differently.
///
/// The generator finds this library in every dependency that has one and
/// registers its module, so listing the starter in `pubspec.yaml` is
/// enough. Applications do not import it; a test that builds a context by
/// hand may name [springBootStarterEdgeAutoConfiguration].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_edge/src/config/config.dart';
import 'package:spring_boot_starter_edge/src/edge_auto_configuration.dart';

export 'package:spring_boot_starter_web/spring_auto_configuration.dart';

/// The edge starter's auto-configuration module: the bean definitions of
/// `edgeAutoConfiguration`, before the web starter's, whose `dart:io`
/// server factory backs off in a function.
///
/// In a Supabase Edge Function it also gives `spring.supabase.url`,
/// `spring.supabase.anon-key` and `spring.supabase.service-role-key` the
/// values of the function's environment (`SUPABASE_URL`,
/// `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`), below everything
/// the application sets itself.
@AutoConfigurationModule(
  before: [
    'springBootStarterWebAutoConfiguration',
    'springBootStarterSupabaseDataAutoConfiguration',
    'springBootStarterSupabaseAutoConfiguration',
    'springBootStarterSupabaseServerAutoConfiguration',
  ],
)
final BeanModule springBootStarterEdgeAutoConfiguration = BeanModule(
  'springBootStarterEdgeAutoConfiguration',
  [...edgeAutoConfiguration],
  imports: [edgeConfigBeans],
  propertySources: const [
    PropertySourceDeclaration(
      ['resources:edge/supabase-function.properties'],
      name: 'supabaseFunctionDefaults',
      conditions: [OnSupabaseFunction()],
    ),
  ],
  resources: const {
    'edge/supabase-function.properties': EmbeddedResource.text(
      r'spring.supabase.url=${SUPABASE_URL}'
      '\n'
      r'spring.supabase.anon-key=${SUPABASE_ANON_KEY:}'
      '\n'
      r'spring.supabase.service-role-key=${SUPABASE_SERVICE_ROLE_KEY:}'
      '\n',
    ),
  },
);
