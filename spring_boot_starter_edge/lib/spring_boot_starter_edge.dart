/// The edge starter: a Spring Boot for Dart application as a function on
/// Supabase Edge Functions, Cloudflare Workers and AWS Lambda.
///
/// `runFetchApplication` is the `main` of a function;
/// `dart run spring_boot_starter_edge:build` compiles it and writes the
/// platform's entry file.
library;

export 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

export 'src/cloudflare/cloudflare.dart';
export 'src/config/edge_properties.dart';
export 'src/edge_auto_configuration.dart'
    show OnD1RateLimitDatabase, OnSupabaseFunction;
export 'src/edge_runtime.dart';
export 'src/edge_scheduled.dart';
export 'src/edge_warnings.dart';
export 'src/fetch/fetch_application.dart';
export 'src/fetch/fetch_exchange.dart';
export 'src/fetch/fetch_web_server.dart';
export 'src/fetch/run_fetch_application.dart';
export 'src/supabase_anon_key_filter.dart';
