// A Flutter web site with real HTML on every page: the generator writes a
// page per route and per Markdown file into web/ (spring.flutter.web.seo.*
// in lib/resources/application-web.yml). See README.md.
import 'package:flutter/widgets.dart';
import 'package:seo_site_app/spring_gen/main.spring.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

@SpringBootApplication()
void main() =>
    runApp(SpringApplicationWidget(application: () => springApplication));
