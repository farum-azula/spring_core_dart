# Bloc Showcase

[Bloc](https://pub.dev/packages/flutter_bloc) and Cubit in a Spring Boot
Flutter app, with no starter for them. A bloc is a class, so it is a
bean: its dependencies come by injection, its lifetime is its scope, and a
widget takes it from the context. The app has no `BlocProvider`, no
service locator and no `close()` of its own.

## What it shows

| Where | What |
|---|---|
| `lib/src/blocs/counter_cubit.dart` | a Cubit for the whole app: `@Component()`, one for the application |
| `lib/src/blocs/books_bloc.dart` (`books_event.dart`, `books_state.dart`) | a Bloc with events and states; its repository comes through the constructor |
| `lib/src/blocs/draft_cubit.dart` | a Cubit of one screen: `@Scope(NavigationScopes.route)`, made when the screen opens and closed when it does |
| `lib/src/blocs/closed_with_bean.dart` | a mixin with a `@PreDestroy` method that closes the bloc when its bean is destroyed |
| `lib/src/events/` | `SpringBlocObserver`: Bloc's observer as a bean, which publishes every bloc's events, state changes and errors as application events |
| `lib/src/journal.dart` | a bean that hears the blocs with `@EventListener` (all of them, or one by a `condition`) and subscribes to none |
| `lib/src/pages/` | the screens: `BlocBuilder(bloc: context.bean<CounterCubit>(), ...)`, Bloc's own widget given the bean |
| `test/blocs_test.dart` | the beans started with `springBootTest` and a repository replaced by `BeanOverride`; the blocs closed with the application; a screen's cubit closed with the screen |

## Two things to know

- **The container does not close a bloc by itself.** A bean's `close()`
  is not called when a component is destroyed, so each bloc has the
  `ClosedWithBean` mixin (one `@PreDestroy` method).
- **A bloc keeps the observer there was when it was made.** So the
  observer must take its place before the first bloc is created:
  `SpringBlocObserver` is a `BeanFactoryPostProcessor`, which the
  container runs before it makes any other bean.

## Run

```bash
flutter pub get
dart run build_runner build
flutter run -d chrome          # http://localhost:5076/, or another device
flutter test
```
