import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The site's API. A controller always wins over a static file, so
/// `/api/info` is answered here even with a file of that name in the
/// build.
@RestController()
@RequestMapping('/api')
class InfoController {
  InfoController(@Value(r'${spring.application.name}') this.name);

  final String name;

  @GetMapping('/info')
  Map<String, Object?> info() => {
    'name': name,
    'time': DateTime.now().toUtc().toIso8601String(),
  };
}
