// dart run spring_boot_starter_edge:workflow --platform supabase --name api
//
// Writes .github/workflows/deploy-<name>.yml into the repository of the
// application: a workflow that builds the function and deploys it on
// every push (deployWorkflow).

// A command line tool: the result goes to the console.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';

const _usage = '''
Writes a GitHub Actions workflow that builds and deploys the function.

  dart run spring_boot_starter_edge:workflow --platform <platform> [options]

  --platform, -p   supabase | cloudflare | aws
  --name, -n       the function's name (default: api)
  --branch         the branch whose pushes deploy (default: main)
  --target, -t     js (default) | wasm
  --force          replace the workflow when it exists
''';

void main(List<String> args) {
  final options = <String, String>{};
  var force = false;
  const short = {'-p': '--platform', '-n': '--name', '-t': '--target'};
  for (var i = 0; i < args.length; i++) {
    var arg = args[i];
    if (arg == '--help' || arg == '-h') {
      print(_usage);
      return;
    }
    if (arg == '--force') {
      force = true;
      continue;
    }
    arg = short[arg] ?? arg;
    final at = arg.indexOf('=');
    if (!arg.startsWith('--')) {
      _fail('Unknown argument "$arg"');
    } else if (at > 0) {
      options[arg.substring(2, at)] = arg.substring(at + 1);
    } else if (i + 1 < args.length) {
      options[arg.substring(2)] = args[++i];
    } else {
      _fail('"$arg" needs a value');
    }
  }
  for (final key in options.keys) {
    if (!const {'platform', 'name', 'branch', 'target'}.contains(key)) {
      _fail('Unknown option "--$key"');
    }
  }
  final platform = EdgePlatform.values
      .where((p) => p.name == options['platform'])
      .firstOrNull;
  final target = EdgeTarget.values
      .where((t) => t.name == (options['target'] ?? 'js'))
      .firstOrNull;
  if (platform == null || target == null) {
    _fail(
      '--platform must be supabase, cloudflare or aws; --target js or wasm',
    );
  }
  final name = options['name'] ?? 'api';
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(name)) {
    _fail('--name: letters, digits, "-" and "_" only');
  }
  // The root of the repository: the nearest directory with .git.
  final application = Directory.current.absolute;
  var root = application;
  while (!FileSystemEntity.isDirectorySync('${root.path}/.git') &&
      !FileSystemEntity.isFileSync('${root.path}/.git')) {
    if (root.parent.path == root.path) {
      _fail('Not in a git repository: no .git above ${application.path}');
    }
    root = root.parent;
  }
  final directory = application.path == root.path
      ? '.'
      : application.path.substring(root.path.length + 1);
  final String content;
  try {
    content = deployWorkflow(
      platform: platform,
      name: name,
      directory: directory,
      branch: options['branch'] ?? 'main',
      target: target,
    );
  } on ArgumentError catch (error) {
    _fail('${error.message}');
  }
  final file = File('${root.path}/.github/workflows/deploy-$name.yml');
  if (file.existsSync() && !force) {
    _fail('${file.path} exists; --force replaces it');
  }
  file
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
  print('Wrote ${file.path}');
}

Never _fail(String message) {
  stderr
    ..writeln(message)
    ..writeln()
    ..writeln(_usage);
  exit(64);
}
