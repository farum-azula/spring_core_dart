# What the site asks of the framework

The site (github.com/farum-azula/neon_farum_azula, November 2026) is the
first real app on the navigation starter. What it had to work around, to
add to the starters:

- **A page index of a content folder.** `@ScreenRoute(content:)` knows
  every Markdown file of its folder (the SEO pages are made from them), but
  the app cannot list them: a menu of the pages, a sidebar, "next/previous"
  need their paths and titles (front matter `title`). The site writes a
  `contents.md` by hand. Wanted: the generated module gives the pages of a
  content route (path, title, description, per language), as a bean or
  constants (the "constants per Markdown file" left in
  spring_boot_starter_flutter_navigation.md).
- **The language's own file in `MarkdownView.resource`.** `RouteContentView`
  picks `<file>.ja.md` for `/ja/...`; `MarkdownView.resource` does not, so
  the site builds the name itself. Wanted: the same choice (and the same
  fallback to the default language) in `MarkdownView.resource`.
- **Links of a `MarkdownView` outside a content route.** A relative link
  (`beans/component.md`) reaches `onLink` as written; the site maps it to a
  route itself. Wanted: `MarkdownView.resource` resolves links to the
  route of the file when a content route has it.
- **The name of a language.** A language menu needs each language's name
  in itself (English, 日本語). The site reads `language.name` of each
  bundle through `MessageSource`. Wanted: a convention or a getter
  (`Navigation.languageName`), from the messages or from the locale data.
- **Typed text styles exist only when declared.** `context.theme.typography.titleMedium`
  is missing unless some theme writes `title-medium`; the site declares it
  empty. Wanted: every Material text style typed, defaulted from the
  scheme.
- **A test helper for a package's files.** `Isolate.resolvePackageUriSync`
  is unsupported under `flutter test`; the NEON showcase reads
  `.dart_tool/package_config.json` to find neon_ui's fonts. Wanted: a
  helper in the Flutter test support, or loading a dependency's fonts in
  tests by itself.
- **Nested selection.** A page wrapped in `SelectionArea` around a
  `RouteContentView` (selectable by default) asserts on a narrow window
  during the splash. Wanted: `RouteContentView` / `MarkdownView` join an
  enclosing `SelectionArea` instead of opening their own.

neon_ui (github.com/farum-azula/themes): `NeonPanel` needs a bounded
height (its child is `Expanded`); the site has a card of its own that
sizes to its content. Wanted: a panel that sizes to its child.
