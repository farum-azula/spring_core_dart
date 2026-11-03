import 'package:flutter/cupertino.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/theme_picture.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// Images from the theme: an asset here, an https URL with a cache and an
/// asset fallback in the `network` profile.
class ImagesPage extends StatelessWidget {
  const ImagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final colors = theme.colors;
    final badge = theme.tokens.brand.badge;
    final backgroundImage = theme.background?.image?.image;
    Widget fact(String name, Object? value) => Text(
      '$name: ${value ?? '-'}',
      style: theme.typography.code.copyWith(color: colors.onSurfaceVariant),
    );
    Widget facts(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    return PageFrame(
      title: context.messages.nav.images,
      intro:
          'An image is a source (an asset path or a URL) and a few options. '
          'The background, the screens\' backgrounds and image tokens take '
          'the same map. This app never goes online on its own: the network '
          'form is in the `network` profile.',
      children: [
        Section(
          title: 'An asset',
          note:
              'tokens.brand.badge is a ThemeImage; ThemePicture paints its '
              'provider.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'badge: { source: assets/images/badge.png }',
                label: 'application.yml: tokens.brand',
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.l,
                runSpacing: space.m,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      theme.tokens.corner.roomy,
                    ),
                    child: ThemePicture(badge, width: 140, height: 140),
                  ),
                  facts([
                    fact('source', badge.source),
                    fact('isNetwork', badge.isNetwork),
                    fact('fallback', badge.fallback),
                    fact('refresh', badge.refresh),
                  ]),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'The same image from the network',
          note:
              'Start with --dart-define=SPRING_PROFILES_ACTIVE=network and '
              'application-network.yml replaces the sources. The app shows '
              'the cache at once; with no cache, the fallback; the download '
              'never delays the start. Replace the hosts with your own.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'source: https://cdn.example.com/theme-showcase-cupertino/badge.png\n'
                'fallback: assets/images/badge.png\n'
                'refresh: 1d',
                label: 'application-network.yml: tokens.brand.badge',
              ),
              SizedBox(height: space.m),
              const YamlBox(
                'refresh: 1d\n'
                'timeout: 10s\n'
                r'# source-sha256: <64 hexadecimal digits>   pins the content'
                '\n'
                r"# headers: { Authorization: 'Bearer ${cdn.token}' }",
                label: 'more keys of an image (application-network.yml)',
              ),
            ],
          ),
        ),
        Section(
          title: 'The background image',
          note: 'themes.sunset.background.image takes the same keys.',
          child: backgroundImage == null
              ? Text(
                  'This theme has no background image. Try sunset.',
                  style: theme.typography.code.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: space.l,
                  runSpacing: space.m,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(space.m),
                      child: ThemePicture(
                        backgroundImage,
                        width: 320,
                        height: 200,
                      ),
                    ),
                    facts([
                      fact('source', backgroundImage.source),
                      fact('isNetwork', backgroundImage.isNetwork),
                      fact('fallback', backgroundImage.fallback),
                    ]),
                  ],
                ),
        ),
      ],
    );
  }
}
