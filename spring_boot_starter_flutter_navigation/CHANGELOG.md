## 0.7.1

- First version: screens on routes (`ScreenRoutes` in Dart configuration),
  Spring's path patterns, shells with a stack per branch, `RouteTemplate`
  and `context.route`, the `route` and `branch` scopes, route filters,
  `spring.flutter.navigation.*`; `@ScreenRoute` and `@RouteShell` read by
  the generator (`<Page>Route.to(...)`); `RouteAttributes.preAuthorize`
  and `RouteAuthorizationRequirement`, enforced by a
  `RouteAuthorizationFilter` bean (`spring_boot_starter_flutter_security`):
  without one, a guarded route stops the start. The router is made only
  for an app with routes, so an app with a `home` keeps Flutter's own
  addresses.
- **Behavior change:** no page transition by default, in every app type; the theme (`motion.page-transition: platform`, `fade`, ...) or a screen turns one on.
- Page transitions follow the theme's `motion.page-transition` in every app type (Material, Cupertino, `widgets`), with its duration and curve, and none with reduced motion. `PageTransition` gains `theme` (the default), `fadeUpwards`, `zoom` and `cupertino`; a screen chooses its own with `@ScreenRoute(transition: ...)`, one navigation with `go(path, transition: ...)` / `push(path, transition: ...)` (a menu switching pages at once). A screen can open in a branch its path is not under: `@ScreenRoute('/motion', branch: '/more')`, or `screen(..., branch:)` and a screen declared in a branch builder outside its path (no longer refused).
- It brings and re-exports `spring_boot_starter_flutter` (and through it
  `spring_web_dart`): an app lists this package alone.
- Deep links: `spring.flutter.navigation.deep-links.*` (the scheme, the
  domains, the platforms' ids; the generator writes the platforms' files
  and the domains' files from them). On a device an address from the
  platform opens its screen unless `deep-links.exclude` or
  `@RouteInfo(link: false)` (a route's `link: false`) keeps it out, when
  the app's first screen opens.
- `RouteContentView`: the Markdown of the screen's route (`content:`) with
  `MarkdownView`; a link to another Markdown file of the site opens its
  screen, as on the pages the build writes.
- Addresses that could leave a route's folder are refused: an encoded slash or backslash, a backslash, an encoded NUL, or a `.` / `..` segment once decoded (`Navigation.refusedPath`). The app stays on its screen, or opens its first screen when nothing is open yet (a link). A `{*rest}` value with such a segment never names a content file, so a public `{*path}` screen cannot show a file of a guarded screen's folder.
- Languages: `spring.flutter.navigation.languages` (`[en, ja]`) gives each language its addresses, the default without a prefix, the others under `/<language>`. Such an address opens the same screen with the app's locale set (`RouteLanguageCustomizer`); the app's own paths keep the current language; `RouteTemplate.language` and `switchLanguage`; `RouteContentView` shows `<file>.<language>.md` when there is one. `RouteLocation.withPath`.
