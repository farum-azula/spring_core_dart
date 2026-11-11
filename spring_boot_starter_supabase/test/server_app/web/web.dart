// The endpoints of the server the token tests call (scanned from here),
// beside the repositories of ../../app/supabase_app.dart. The generator
// writes its beans (../../spring_gen/server_app/web/web.spring.dart).
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../../spring_gen/server_app/web/web.spring.dart';

@ComponentScan()
final BeanModule supabaseServerBeans = $supabaseServerBeans;
