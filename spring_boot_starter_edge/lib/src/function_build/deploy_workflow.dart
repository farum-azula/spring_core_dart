import 'package:spring_boot_starter_edge/src/function_build/edge_build.dart';

/// A GitHub Actions workflow that builds the function and deploys it on
/// every push to [branch]: what
/// `dart run spring_boot_starter_edge:workflow` writes.
///
/// With [streaming] (AWS) the build is the response-streaming one, as
/// `--streaming` of the build command.
///
/// [directory] is the application's directory from the root of the
/// repository (`.` for the root). What the deploy needs comes from the
/// repository's secrets and variables, named in the workflow's first
/// lines; nothing secret is written.
///
/// Throws an [ArgumentError] for a platform without a workflow here
/// (Deno Deploy, Netlify and Vercel deploy from the repository
/// themselves: give them the build command).
String deployWorkflow({
  required EdgePlatform platform,
  required String name,
  String directory = '.',
  String branch = 'main',
  EdgeTarget target = EdgeTarget.js,
  bool streaming = false,
}) {
  // What goes into the workflow's YAML as it is.
  if (!RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(branch)) {
    throw ArgumentError.value(branch, 'branch', 'Not the name of a branch');
  }
  if (!RegExp(r'^[A-Za-z0-9._/ -]+$').hasMatch(directory)) {
    throw ArgumentError.value(directory, 'directory', 'Not a plain path');
  }
  final build =
      'dart run spring_boot_starter_edge:build --platform ${platform.name} '
      '--name $name${target == EdgeTarget.wasm ? ' --target wasm' : ''}'
      '${streaming ? ' --streaming' : ''}';
  final (needs, deploy) = switch (platform) {
    EdgePlatform.supabase => (
      '''
#   secrets.SUPABASE_ACCESS_TOKEN   an access token of the account
#   secrets.SUPABASE_PROJECT_REF    the project (<ref>.supabase.co)
# The function's own secrets are set once, outside the repository:
#   supabase secrets set NAME=value --project-ref <ref>''',
      '''
      - uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Deploy
        env:
          SUPABASE_ACCESS_TOKEN: \${{ secrets.SUPABASE_ACCESS_TOKEN }}
        run: supabase functions deploy $name --project-ref "\${{ secrets.SUPABASE_PROJECT_REF }}"''',
    ),
    EdgePlatform.cloudflare => (
      '''
#   secrets.CLOUDFLARE_API_TOKEN    a token that may edit Workers
#   secrets.CLOUDFLARE_ACCOUNT_ID   the account
# The Worker's bindings and variables are in wrangler.toml; its secrets
# are set once, outside the repository: npx wrangler secret put NAME''',
      r'''
      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Deploy
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
        run: npx --yes wrangler@4 deploy''',
    ),
    EdgePlatform.aws => (
      '''
#   secrets.AWS_ROLE_ARN            a role GitHub may assume (OIDC) that
#                                   may update the function's code
#   vars.AWS_REGION                 the region of the function
#   vars.AWS_LAMBDA_FUNCTION        the name of the function (Node.js 22,
#                                   handler index.handler)
# The function's environment variables are set on the function itself.''',
      r'''
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Deploy
        run: |
          (cd build/aws && zip -q -r ../function.zip .)
          aws lambda update-function-code \
            --function-name "${{ vars.AWS_LAMBDA_FUNCTION }}" \
            --zip-file fileb://build/function.zip''',
    ),
    _ => throw ArgumentError.value(
      platform.name,
      'platform',
      'No deploy workflow for this platform: it deploys from the '
          'repository itself; give it the build command',
    ),
  };
  final permissions = platform == EdgePlatform.aws
      ? '''
permissions:
  contents: read
  id-token: write'''
      : '''
permissions:
  contents: read''';
  return '''
# Written by `dart run spring_boot_starter_edge:workflow`; yours to change.
# Builds the function `$name` and deploys it to ${_title(platform)} on
# every push to $branch. It needs:
$needs
name: Deploy $name

on:
  push:
    branches: [$branch]
  workflow_dispatch:

concurrency:
  group: deploy-$name
  cancel-in-progress: false

$permissions

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    defaults:
      run:
        working-directory: "$directory"
    steps:
      - uses: actions/checkout@v4

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Install dependencies
        run: dart pub get

      - name: Generate
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Build
        run: $build

$deploy
''';
}

String _title(EdgePlatform platform) => switch (platform) {
  EdgePlatform.supabase => 'Supabase Edge Functions',
  EdgePlatform.cloudflare => 'Cloudflare Workers',
  EdgePlatform.aws => 'AWS Lambda',
  EdgePlatform.deno => 'Deno Deploy',
  EdgePlatform.netlify => 'Netlify',
  EdgePlatform.vercel => 'Vercel',
};
