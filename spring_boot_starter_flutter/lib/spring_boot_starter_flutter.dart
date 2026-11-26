/// Spring Boot inside a Flutter app: import it to keep the app's state and
/// services in beans and to give those beans to the widgets.
///
/// `SpringApplicationWidget` at the root starts the application context
/// (beans, configuration files, messages) while a splash screen shows, and
/// hands it to the widget tree. Widgets get their beans without passing
/// them through constructors: as a `beans` record declared in the widget's
/// type (`SpringStatelessWidget`, `SpringStatefulWidget`), with
/// `context.bean<T>()`, or with getters generated for `@BuildContextAccess`
/// beans. State beans marked `@ChangeNotifierComponent` or
/// `@NotifyListeners` rebuild the widgets that show them. The app widget
/// itself, its themes and its locales can come from properties
/// (`spring.flutter.app.*`, `spring.flutter.theme.*`), the platform is an
/// active profile, and a hot reload restarts the context when the beans
/// changed.
///
/// ```dart
/// @SpringBootApplication()
/// void main() => runApp(
///   SpringApplicationWidget(
///     application: () => springApplication, // generated in main.spring.dart
///     home: const CounterPage(),
///   ),
/// );
/// ```
///
/// The package also brings and exports `spring_core_dart`,
/// `spring_boot_dart` (`@Component`, `@Value`, `@ConfigurationProperties`,
/// `@SpringBootApplication`, events, validation, JSON, ...) and
/// `spring_boot_starter_logging` (switched on: `SpringLog` output with
/// levels and patterns from `logging.*`, an in-memory `LogBuffer`), so an
/// app depends on and imports only this package. Two names would clash
/// with Flutter's and are left out: Boot's startup `Banner` (Flutter has a
/// `Banner` widget) and the validation constraint `Size` (`dart:ui` has
/// `Size`), exported here as [SizeConstraint].
///
/// Logins and secrets (the Keychain, the Android Keystore, the system's
/// login window, widgets that follow the logged-in user) come with
/// `spring_boot_starter_flutter_security`, which brings this package: an
/// app without a login carries none of that code.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart' as boot;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    hide Banner, Size;
// The HTTP model and clients: the starter's API takes an `HttpTransport`
// (`RemoteCache`, the theme's network images), and an app sending its own
// requests needs no other dependency.
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/annotations.dart';
export 'src/app_lifecycle.dart';
export 'src/asset_resource.dart';
export 'src/resource_prefetch.dart';
export 'src/debug/overlay/debug_dock.dart';
export 'src/debug/overlay/debug_overlay.dart';
export 'src/debug/overlay/debug_overlay_drag.dart';
export 'src/debug/sections/overlays_section.dart';
export 'src/bean_lookup_scope.dart';
export 'src/bean_reads.dart' show BeanReadsPointcut, BeanReadsInterceptor;
export 'src/context_extensions.dart';
export 'src/desktop_window/desktop_window.dart';
export 'src/desktop_window/desktop_window_settings.dart';
export 'src/files/file_cache_store.dart';
export 'src/files/file_store.dart';
export 'src/files/file_template.dart' show FileArea, FileTemplate;
export 'src/files/memory_file_store.dart' show InMemoryFileStore;
export 'src/markdown/code_tokens.dart';
export 'src/markdown/markdown_outline.dart';
export 'src/markdown/markdown_view.dart';
export 'src/properties/flutter_properties.dart';
export 'src/resources/resource_cache.dart'
    show CachedResource, CachedResourceRegistrar, ResourceCache;
export 'src/resources/resource_image.dart';
export 'src/resources/resource_view.dart';
export 'src/notify_listeners.dart';
export 'src/platform_profiles.dart';
export 'src/shortcuts/touch_pattern.dart';
export 'src/shortcuts/keyboard_shortcuts.dart';
export 'src/shortcuts/keyboard_shortcuts_scope.dart';
export 'src/shortcuts/shortcut.dart';
export 'src/shortcuts/shortcut_handler.dart';
export 'src/shortcuts/shortcut_handlers.dart';
export 'src/shortcuts/shortcut_intent.dart';
export 'src/shortcuts/shortcut_invocation.dart';
export 'src/shortcuts/shortcut_keys.dart';
export 'src/shortcuts/shortcut_label.dart';
export 'src/spring_app.dart';
export 'src/spring_application_widget.dart';
export 'src/spring_scope.dart';
export 'src/widget_build_tracker.dart';
export 'src/spring_widgets.dart';
export 'src/text/highlighted_text.dart';
export 'src/text/text_morph.dart';
export 'src/theme/content_change.dart';
export 'src/theme/wheel_scroll.dart';
export 'src/debug/beans_graph/beans_graph_layer.dart';
export 'src/debug/beans_graph/debug_bean.dart';
export 'src/debug/beans_graph/debug_bean_edge.dart';
export 'src/debug/beans_graph/debug_bean_event.dart';
export 'src/debug/beans_graph/debug_bean_graph.dart';
export 'src/debug/beans_graph/debug_bean_graph_reader.dart';
export 'src/debug/beans_graph/debug_bean_graph_snapshot.dart';
export 'src/debug/beans_graph/debug_bean_lifecycle_recorder.dart';
export 'src/debug/beans_graph/debug_bean_module.dart';
export 'src/debug/beans_graph/debug_bean_role.dart';
export 'src/debug/beans_graph/debug_skipped_bean.dart';
export 'src/debug/console/console_annotations.dart';
export 'src/debug/console/debug_console.dart';
export 'src/debug/console/debug_console_command.dart';
export 'src/debug/console/debug_console_command_line.dart';
export 'src/debug/console/debug_console_commands.dart';
export 'src/debug/console/debug_console_commands_pane.dart';
export 'src/debug/console/debug_console_export_command.dart';
export 'src/debug/console/debug_console_logs_pane.dart';
export 'src/debug/console/debug_console_logs_view.dart';
export 'src/debug/console/debug_console_names.dart';
export 'src/debug/console/debug_console_pane.dart';
export 'src/debug/console/debug_console_resize.dart';
export 'src/debug/console/debug_console_scroll.dart';
export 'src/debug/console/debug_console_section.dart';
export 'src/debug/console/debug_console_segment.dart';
export 'src/debug/console/debug_console_segments.dart';
export 'src/debug/console/debug_console_selection.dart';
export 'src/debug/console/debug_console_view.dart';
export 'src/debug/debug_frame_meter.dart';
export 'src/debug/graph/debug_graph_assembly.dart';
export 'src/debug/graph/debug_graph_card.dart';
export 'src/debug/graph/debug_graph_fit_action.dart';
export 'src/debug/graph/debug_graph_layer.dart';
export 'src/debug/graph/debug_graph_layout.dart';
export 'src/debug/graph/debug_graph_legend.dart';
export 'src/debug/graph/debug_graph_memory.dart';
export 'src/debug/graph/debug_graph_model.dart';
export 'src/debug/graph/debug_graph_pane.dart';
export 'src/debug/graph/debug_graph_routes.dart';
export 'src/debug/graph/debug_graph_scene.dart';
export 'src/debug/graph/debug_graph_screen.dart';
export 'src/debug/graph/debug_graph_section.dart';
export 'src/debug/graph/debug_graph_toolbar.dart';
export 'src/debug/graph/debug_graph_view.dart';
export 'src/debug/graph/debug_graph_widgets.dart';
export 'src/debug/graph/layered_debug_graph_layout.dart';
export 'src/debug/graph/tree_debug_graph_layout.dart';
export 'src/debug/widgets_graph/app_widget_files.dart';
export 'src/debug/widgets_graph/debug_navigator_stack.dart';
export 'src/debug/widgets_graph/debug_widget_fields.dart';
export 'src/debug/widgets_graph/widget_highlight.dart';
export 'src/debug/widgets_graph/widget_properties.dart';
export 'src/debug/widgets_graph/widget_rebuilds.dart';
export 'src/debug/widgets_graph/widgets_graph_layer.dart';
export 'src/debug/flutter_tools/debug_flutter_tools.dart';
export 'src/debug/flutter_tools/debug_flutter_tools_customizer.dart';
export 'src/debug/flutter_tools/devtools_link.dart';
export 'src/debug/flutter_tools/flutter_tool_switches.dart';
export 'src/debug/flutter_tools/flutter_tools_mode.dart';
export 'src/debug/flutter_tools/flutter_tools_section.dart';
export 'src/debug/flutter_tools/inspector_selection_view.dart';
export 'src/debug/debug_host.dart';
export 'src/debug/debug_layout.dart';
export 'src/debug/debug_markers.dart';
export 'src/debug/debug_motion.dart';
export 'src/debug/debug_panel.dart';
export 'src/debug/debug_panel_menu.dart';
export 'src/debug/debug_style.dart';
export 'src/debug/theme/configured_debug_theme.dart';
export 'src/debug/theme/debug_theme.dart';
export 'src/debug/theme/debug_theme_scope.dart';
export 'src/debug/theme/debug_themes.dart';
export 'src/debug/isolates/debug_isolates.dart';
export 'src/debug/isolates/isolate_loads_watch.dart';
export 'src/debug/isolates/isolates_section.dart';
export 'src/debug/isolates/isolates_view.dart';
export 'src/debug/isolates/memory/big_number.dart';
export 'src/debug/isolates/memory/image_cache_memory.dart';
export 'src/debug/isolates/memory/memory_block.dart';
export 'src/debug/isolates/memory/memory_chart.dart';
export 'src/debug/isolates/memory/memory_console_segment.dart';
export 'src/debug/isolates/memory/memory_figure.dart';
export 'src/debug/isolates/memory/memory_watch.dart';
export 'src/debug/isolates/size/page_resources.dart';
export 'src/debug/isolates/size/size_block.dart';
export 'src/debug/network/debug_network_filter.dart';
export 'src/debug/network/debug_network_journal.dart';
export 'src/debug/network/debug_network_recorder.dart';
export 'src/debug/network/network_detail.dart';
export 'src/debug/network/network_console_pane.dart';
export 'src/debug/network/network_console_segment.dart';
export 'src/debug/network/network_entry.dart';
export 'src/debug/network/network_format.dart';
export 'src/debug/network/network_masking.dart';
export 'src/debug/network/network_section.dart';
export 'src/debug/network/network_view.dart';
export 'src/debug/network/network_waterfall.dart';
export 'src/debug/network/recording_http_transport.dart';
export 'src/debug/network/recording_web_socket_transport.dart';
export 'src/debug/network/resource_timing.dart';
export 'src/debug/network/web_socket_frame_labeler.dart';
export 'src/debug/network/web_socket_ping_matcher.dart';
export 'src/debug/logs/debug_file_export.dart';
export 'src/debug/logs/debug_log_export.dart';
export 'src/debug/logs/debug_log_filter.dart';
export 'src/debug/logs/debug_log_format.dart';
export 'src/debug/logs/debug_log_marks.dart';
export 'src/debug/logs/debug_log_selection.dart';
export 'src/debug/logs/debug_log_text.dart';
export 'src/debug/logs/debug_logs_action.dart';
export 'src/debug/sections/beans_section.dart';
export 'src/debug/sections/configuration_section.dart';
export 'src/debug/sections/frames_section.dart';
export 'src/debug/sections/motion_section.dart';
export 'src/debug/sections/logs_section.dart';
export 'src/debug/sections/start_section.dart';
export 'src/debug/sections/theme_section.dart';
export 'src/debug/timeline/debug_timeline.dart';
export 'src/debug/timeline/timeline_chart.dart';
export 'src/debug/timeline/timeline_observations.dart';
export 'src/debug/timeline/timeline_section.dart';
export 'src/debug/timeline/timeline_view.dart';
export 'src/frame_meter/frame_meter.dart';
export 'src/frame_meter/frame_stats.dart';
export 'src/frame_meter/outside_frames.dart';
export 'src/isolates/engine_load_probe.dart';
export 'src/isolates/flutter_engine_loads.dart';
export 'src/splash/frame_pacer.dart';
export 'src/splash/splash_properties.dart';
export 'src/splash/splash_stage.dart';
export 'src/splash/splash_stage_event.dart';
export 'src/splash/splash_stages.dart';
export 'src/splash/splash_task.dart';
export 'src/splash/splash_tasks.dart';
export 'src/splash/splash_trace.dart';
export 'src/splash/startup_events.dart';
export 'src/splash/text_warm_up.dart';
export 'src/design_scope.dart';
export 'src/text/selection_controls.dart';
export 'src/theme/loader_tracks.dart';
export 'src/theme/spring_color_scheme.dart';
export 'src/theme/spring_theme_data.dart' show SpringThemeData, SpringTextSpec;
export 'src/theme/spring_type_scale.dart';
export 'src/theme/theme_design.dart';
export 'src/theme/spring_themes.dart';
export 'src/theme/theme_animation.dart';
export 'src/theme/theme_background.dart';
export 'src/theme/theme_background_widget.dart' show ThemeBackground;
export 'src/theme/page_underlay.dart';
export 'src/theme/theme_fonts.dart';
export 'src/theme/theme_image.dart' show ThemeImage;
export 'src/theme/theme_loader.dart'
    show
        BuiltInLoaderLook,
        LoaderFrame,
        LoaderKindRegistration,
        LoaderValues,
        ThemeLoaderKinds,
        ThemeLoaderPainter,
        ThemeLoaderPhase,
        ThemeLoaderSpec,
        ThemeLoaderWidget;
export 'src/theme/theme_loader_widget.dart'
    show LoaderTimeline, ThemeLoader, ThemeSkeleton;
export 'src/theme/frame_meter_theme.dart';
export 'src/theme/theme_choice_store.dart';
export 'src/theme/theme_splash.dart' show ThemeSplash, ThemeSplashData;
export 'src/theme/theme_key_reader.dart';
export 'src/theme/theme_states.dart';
export 'src/theme/theme_text.dart';
export 'src/theme/theme_styles.dart';
export 'src/theme/theme_values.dart' show ThemePropertyException;

/// The validation constraint that keeps a string's length or a
/// collection's size between `min` and `max`.
///
/// It is the `@Size` of `spring_core_dart` (Jakarta's `@Size`) under
/// another name, because Flutter's `Size` (`dart:ui`) is everywhere in
/// widget code. Use it on validated configuration properties or on objects
/// checked by the validator.
///
/// ```dart
/// // A display name from the settings must be 2 to 40 characters long.
/// @ConfigurationProperties('profile')
/// @Validated()
/// class ProfileProperties {
///   @SizeConstraint(min: 2, max: 40)
///   String displayName = 'Reader';
/// }
/// ```
typedef SizeConstraint = boot.Size;
