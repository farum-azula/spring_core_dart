// The desktop window on Linux (GTK 3): channel
// "dev.farumazula/spring_boot_starter_flutter/window" with apply, describe,
// startDrag and toggleMaximize.
//
// title-bar=transparent: GTK draws a header bar next to the content, never
// under it, so the closest is a header bar of our own that is flat (no
// background, border, shadow or title) with the window buttons in it, and
// zero insets. title-bar=hidden: no decoration at all.

#include "include/spring_boot_starter_flutter/spring_boot_starter_flutter_plugin.h"

#include <gtk/gtk.h>

#include <math.h>
#include <string.h>

#define SPRING_BOOT_STARTER_FLUTTER_PLUGIN(obj)                          \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),                                     \
                              spring_boot_starter_flutter_plugin_get_type(), \
                              SpringBootStarterFlutterPlugin))

struct _SpringBootStarterFlutterPlugin {
  GObject parent_instance;

  FlPluginRegistrar* registrar;
  gchar* title_bar;
  gboolean has_min_size;
  double min_width;
  double min_height;
  // The last button press on the Flutter view: begin_move_drag needs its
  // time and position, and the call from Dart arrives after it.
  gboolean tracking_presses;
  gboolean has_press;
  guint32 press_time;
  gdouble press_x_root;
  gdouble press_y_root;
};

G_DEFINE_TYPE(SpringBootStarterFlutterPlugin,
              spring_boot_starter_flutter_plugin,
              g_object_get_type())

static const char kFlatHeaderBarCss[] =
    "headerbar.spring-flat {"
    " background: none; border: none; box-shadow: none; }";

static GtkWindow* get_window(SpringBootStarterFlutterPlugin* self) {
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return nullptr;
  }
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  return GTK_IS_WINDOW(top) ? GTK_WINDOW(top) : nullptr;
}

static gboolean on_button_press(GtkWidget* widget, GdkEventButton* event,
                                gpointer user_data) {
  (void)widget;
  SpringBootStarterFlutterPlugin* self =
      SPRING_BOOT_STARTER_FLUTTER_PLUGIN(user_data);
  if (event->button == 1) {
    self->has_press = TRUE;
    self->press_time = event->time;
    self->press_x_root = event->x_root;
    self->press_y_root = event->y_root;
  }
  // Only watching: Flutter gets the press as always.
  return FALSE;
}

static void track_presses(SpringBootStarterFlutterPlugin* self) {
  if (self->tracking_presses) {
    return;
  }
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return;
  }
  self->tracking_presses = TRUE;
  g_signal_connect(view, "button-press-event", G_CALLBACK(on_button_press),
                   self);
}

static gboolean read_number(FlValue* arguments, const char* key,
                            double* value) {
  if (arguments == nullptr || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* entry = fl_value_lookup_string(arguments, key);
  if (entry == nullptr) {
    return FALSE;
  }
  if (fl_value_get_type(entry) == FL_VALUE_TYPE_FLOAT) {
    *value = fl_value_get_float(entry);
    return TRUE;
  }
  if (fl_value_get_type(entry) == FL_VALUE_TYPE_INT) {
    *value = static_cast<double>(fl_value_get_int(entry));
    return TRUE;
  }
  return FALSE;
}

// The height of our own title bar (client-side decorations): window sizes
// of GTK include it, the sizes of the properties do not.
static int title_bar_height(GtkWindow* window) {
  GtkWidget* titlebar = gtk_window_get_titlebar(window);
  if (titlebar == nullptr || !gtk_widget_get_visible(titlebar)) {
    return 0;
  }
  int height = gtk_widget_get_allocated_height(titlebar);
  if (height <= 1) {
    gtk_widget_get_preferred_height(titlebar, &height, nullptr);
  }
  return height;
}

static void apply_min_size(SpringBootStarterFlutterPlugin* self,
                           GtkWindow* window) {
  if (!self->has_min_size) {
    return;
  }
  GdkGeometry geometry = {};
  geometry.min_width = static_cast<int>(ceil(self->min_width));
  geometry.min_height =
      static_cast<int>(ceil(self->min_height)) + title_bar_height(window);
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);
}

static void apply_title_bar(SpringBootStarterFlutterPlugin* self,
                            GtkWindow* window) {
  if (strcmp(self->title_bar, "hidden") == 0) {
    GtkWidget* titlebar = gtk_window_get_titlebar(window);
    if (titlebar != nullptr) {
      gtk_widget_hide(titlebar);
    }
    gtk_window_set_decorated(window, FALSE);
    return;
  }
  if (strcmp(self->title_bar, "transparent") != 0) {
    return;
  }
  GtkWidget* titlebar = gtk_window_get_titlebar(window);
  if (titlebar == nullptr) {
    // The system draws the title bar (server-side decorations): ours
    // replaces it. GTK warns that the window is realized and realizes it
    // again.
    titlebar = gtk_header_bar_new();
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(titlebar), TRUE);
    gtk_widget_show(titlebar);
    gtk_window_set_titlebar(window, titlebar);
  }
  if (!GTK_IS_HEADER_BAR(titlebar)) {
    // An app's own title bar widget: not ours to restyle.
    return;
  }
  // No title: an empty box in its place.
  GtkWidget* empty = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_show(empty);
  gtk_header_bar_set_custom_title(GTK_HEADER_BAR(titlebar), empty);
  gtk_style_context_add_class(gtk_widget_get_style_context(titlebar),
                              "spring-flat");
  GtkCssProvider* provider = gtk_css_provider_new();
  gtk_css_provider_load_from_data(provider, kFlatHeaderBarCss, -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(provider);
}

static void apply_initial_size(GtkWindow* window, double width,
                               double height) {
  const int outer_width = static_cast<int>(lround(width));
  const int outer_height =
      static_cast<int>(lround(height)) + title_bar_height(window);
  gtk_window_resize(window, outer_width, outer_height);
  // Centered on the work area of the monitor the window is on (ignored on
  // Wayland, where the compositor places windows).
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  GdkMonitor* monitor =
      gdk_window != nullptr
          ? gdk_display_get_monitor_at_window(display, gdk_window)
          : gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    GdkRectangle area;
    gdk_monitor_get_workarea(monitor, &area);
    gtk_window_move(window, area.x + (area.width - outer_width) / 2,
                    area.y + (area.height - outer_height) / 2);
  }
}

static FlValue* insets_value() {
  // GTK never draws content under the title bar: nothing to leave room for.
  FlValue* insets = fl_value_new_map();
  fl_value_set_string_take(insets, "left", fl_value_new_float(0));
  fl_value_set_string_take(insets, "top", fl_value_new_float(0));
  fl_value_set_string_take(insets, "right", fl_value_new_float(0));
  fl_value_set_string_take(insets, "bottom", fl_value_new_float(0));
  return insets;
}

static FlMethodResponse* apply(SpringBootStarterFlutterPlugin* self,
                               GtkWindow* window, FlValue* arguments) {
  g_free(self->title_bar);
  self->title_bar = g_strdup("default");
  if (arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP) {
    FlValue* title_bar = fl_value_lookup_string(arguments, "titleBar");
    if (title_bar != nullptr &&
        fl_value_get_type(title_bar) == FL_VALUE_TYPE_STRING) {
      g_free(self->title_bar);
      self->title_bar = g_strdup(fl_value_get_string(title_bar));
    }
  }
  double min_width = 0;
  double min_height = 0;
  if (read_number(arguments, "minWidth", &min_width) &&
      read_number(arguments, "minHeight", &min_height)) {
    self->has_min_size = TRUE;
    self->min_width = min_width;
    self->min_height = min_height;
  }
  track_presses(self);
  apply_title_bar(self, window);
  apply_min_size(self, window);
  double width = 0;
  double height = 0;
  if (read_number(arguments, "initialWidth", &width) &&
      read_number(arguments, "initialHeight", &height)) {
    apply_initial_size(window, width, height);
  }
  g_autoptr(FlValue) answer = fl_value_new_map();
  fl_value_set_string_take(answer, "insets", insets_value());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(answer));
}

static FlMethodResponse* describe(SpringBootStarterFlutterPlugin* self,
                                  GtkWindow* window) {
  gint width = 0;
  gint height = 0;
  gint x = 0;
  gint y = 0;
  gtk_window_get_size(window, &width, &height);
  gtk_window_get_position(window, &x, &y);
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "contentWidth", fl_value_new_float(width));
  fl_value_set_string_take(
      map, "contentHeight",
      fl_value_new_float(height - title_bar_height(window)));
  fl_value_set_string_take(
      map, "minWidth", fl_value_new_float(self->has_min_size ? self->min_width : 0));
  fl_value_set_string_take(
      map, "minHeight",
      fl_value_new_float(self->has_min_size ? self->min_height : 0));
  fl_value_set_string_take(map, "titleBar", fl_value_new_string(self->title_bar));
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static void start_drag(SpringBootStarterFlutterPlugin* self,
                       GtkWindow* window) {
  gint x = 0;
  gint y = 0;
  guint32 time = GDK_CURRENT_TIME;
  if (self->has_press) {
    x = static_cast<gint>(self->press_x_root);
    y = static_cast<gint>(self->press_y_root);
    time = self->press_time;
  } else {
    GdkSeat* seat =
        gdk_display_get_default_seat(gtk_widget_get_display(GTK_WIDGET(window)));
    gdk_device_get_position(gdk_seat_get_pointer(seat), nullptr, &x, &y);
  }
  gtk_window_begin_move_drag(window, 1, x, y, time);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  (void)channel;
  SpringBootStarterFlutterPlugin* self =
      SPRING_BOOT_STARTER_FLUTTER_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);
  GtkWindow* window = get_window(self);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (window == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "no_window", "The Flutter view has no window", nullptr));
  } else if (strcmp(method, "apply") == 0) {
    response = apply(self, window, arguments);
  } else if (strcmp(method, "describe") == 0) {
    response = describe(self, window);
  } else if (strcmp(method, "startDrag") == 0) {
    track_presses(self);
    start_drag(self, window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "toggleMaximize") == 0) {
    if (gtk_window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void spring_boot_starter_flutter_plugin_dispose(GObject* object) {
  SpringBootStarterFlutterPlugin* self =
      SPRING_BOOT_STARTER_FLUTTER_PLUGIN(object);
  g_clear_pointer(&self->title_bar, g_free);
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(spring_boot_starter_flutter_plugin_parent_class)->dispose(object);
}

static void spring_boot_starter_flutter_plugin_class_init(
    SpringBootStarterFlutterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = spring_boot_starter_flutter_plugin_dispose;
}

static void spring_boot_starter_flutter_plugin_init(
    SpringBootStarterFlutterPlugin* self) {
  self->title_bar = g_strdup("default");
}

void spring_boot_starter_flutter_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  SpringBootStarterFlutterPlugin* plugin = SPRING_BOOT_STARTER_FLUTTER_PLUGIN(
      g_object_new(spring_boot_starter_flutter_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.farumazula/spring_boot_starter_flutter/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
