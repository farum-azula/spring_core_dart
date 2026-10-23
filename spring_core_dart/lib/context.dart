/// Application context, annotations, conditions, events, lifecycle and
/// messages (Spring's `spring-context`).
///
/// ```dart
/// final context = ApplicationContext.run([appBeans]);
/// context.addListener<UserCreated>((event) => print(event.name));
/// context.publishEvent(UserCreated('Ada'));
/// print(context.getMessage('greeting', args: ['Ada'], locale: 'en'));
/// context.close();
/// ```
///
/// Spring (Java):
/// ```java
/// var context = new AnnotationConfigApplicationContext(AppConfig.class);
/// context.addApplicationListener(
///     (PayloadApplicationEvent<UserCreated> e) -> ...);
/// context.publishEvent(new UserCreated("Ada"));
/// context.getMessage("greeting", new Object[] {"Ada"}, Locale.ENGLISH);
/// context.close();
/// ```
library;

export 'package:spring_core_dart/src/context/annotations.dart';
export 'package:spring_core_dart/src/context/application_context.dart';
export 'package:spring_core_dart/src/context/bean_module.dart';
export 'package:spring_core_dart/src/context/condition.dart';
export 'package:spring_core_dart/src/context/context_aware.dart';
export 'package:spring_core_dart/src/context/event/application_event.dart';
export 'package:spring_core_dart/src/context/event/application_event_multicaster.dart';
export 'package:spring_core_dart/src/context/event/application_listener.dart';
export 'package:spring_core_dart/src/context/event/context_events.dart';
export 'package:spring_core_dart/src/context/event/event_listener_method.dart';
export 'package:spring_core_dart/src/context/lifecycle.dart';
export 'package:spring_core_dart/src/context/message/abstract_message_source.dart';
export 'package:spring_core_dart/src/context/message/message_format.dart';
export 'package:spring_core_dart/src/context/message/message_source.dart';
export 'package:spring_core_dart/src/context/message/message_source_accessor.dart';
export 'package:spring_core_dart/src/context/message/reloadable_resource_bundle_message_source.dart';
