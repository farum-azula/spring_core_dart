// A Flutter app with tabs (a shell with a stack per branch), a book screen
// with a path variable, a query parameter and an extra object, a screen
// over the tabs that returns a result, and a not-found screen. The
// generator writes example.spring.dart (`dart run build_runner build`):
// the routes and `BookPageRoute.to(...)`.
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

import 'spring_gen/example.spring.dart';

/// What the catalog shows of a book before it is loaded.
class BookSummary {
  /// The summary of the book titled [title].
  const BookSummary(this.title);

  /// The book's title.
  final String title;
}

/// The tabs: the catalog and the profile, each with its own stack.
@RouteShell(branches: ['/catalog', '/profile'])
class MainTabs extends StatelessWidget {
  /// The tabs of [shell].
  const MainTabs(this.shell, {super.key});

  /// The current branch and the way to switch.
  final ShellState shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell.child,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.index,
      onDestinationSelected: shell.select,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.book), label: 'Catalog'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    ),
  );
}

/// The catalog: a list of books.
@ScreenRoute('/catalog', title: 'Catalog')
class CatalogPage extends StatelessWidget {
  /// The catalog.
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      ListTile(
        title: const Text('Dune'),
        onTap: () => context.route.go(
          BookPageRoute.to(
            isbn: '978-0441013593',
            page: 1,
            extra: const BookSummary('Dune'),
          ),
        ),
      ),
    ],
  );
}

/// One book: its ISBN from the path, the page from the query, the summary
/// passed along (gone after a reload: the screen loads from the ISBN).
@ScreenRoute(
  '/catalog/books/{isbn}',
  title: 'Book',
  params: {'page': int},
  extra: BookSummary,
)
class BookPage extends StatelessWidget {
  /// The book screen.
  const BookPage({super.key});

  @override
  Widget build(BuildContext context) {
    final route = context.route;
    final summary = route.get(BookPageRoute.extra);
    final page = route.get(BookPageRoute.page) ?? 1;
    return Column(
      children: [
        Text(summary?.title ?? route.get(BookPageRoute.isbn)),
        Text('page $page'),
        TextButton(
          onPressed: () => route.replaceParams({'page': page + 1}),
          child: const Text('next page'),
        ),
        TextButton(
          onPressed: () async {
            final paid = await route.push<bool>(CheckoutPageRoute.to());
            if (paid ?? false) {
              await route.go(CatalogPageRoute.to());
            }
          },
          child: const Text('buy'),
        ),
      ],
    );
  }
}

/// The profile tab.
@ScreenRoute('/profile', title: 'Profile')
class ProfilePage extends StatelessWidget {
  /// The profile.
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Text('profile'));
}

/// The payment, over the tabs; it returns whether it was paid.
@ScreenRoute('/checkout', title: 'Checkout')
class CheckoutPage extends StatelessWidget {
  /// The payment screen.
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => context.route.pop(true),
        child: const Text('pay'),
      ),
    ),
  );
}

/// An address no route has.
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  /// The not-found screen.
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Nothing at ${context.route.uri}'));
}

/// The app: no home, the router shows the screens; `/` goes to the
/// catalog (`spring.flutter.navigation.initial=/catalog`, or a redirect).
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(application: () => springApplication),
);
