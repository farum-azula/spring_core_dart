#ifndef FLUTTER_PLUGIN_SPRING_BOOT_STARTER_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_SPRING_BOOT_STARTER_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <memory>
#include <optional>
#include <string>

namespace spring_boot_starter_flutter {

// The window of a desktop app: channel
// "dev.farumazula/spring_boot_starter_flutter/window" (apply, describe,
// startDrag, toggleMaximize) and the top-level window procedure delegate
// that answers WM_GETMINMAXINFO (the minimum and maximum sizes), WM_NCCALCSIZE and
// WM_NCHITTEST (the client area under the title bar).
class SpringBootStarterFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit SpringBootStarterFlutterPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~SpringBootStarterFlutterPlugin() override;

  SpringBootStarterFlutterPlugin(const SpringBootStarterFlutterPlugin&) = delete;
  SpringBootStarterFlutterPlugin& operator=(
      const SpringBootStarterFlutterPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  HWND TopLevelWindow() const;
  void Apply(HWND hwnd, const flutter::EncodableMap& arguments);
  flutter::EncodableMap Insets(HWND hwnd) const;
  flutter::EncodableMap Describe(HWND hwnd) const;
  void NonClientSize(HWND hwnd, int* width, int* height);

  flutter::PluginRegistrarWindows* registrar_;
  int window_proc_id_ = -1;
  std::string title_bar_ = "default";
  bool has_min_size_ = false;
  double min_width_ = 0;
  double min_height_ = 0;
  bool has_max_size_ = false;
  double max_width_ = 0;
  double max_height_ = 0;
  // The window frame's size beyond the client area, from the last time it
  // could be measured (not while the window is minimized).
  int non_client_width_ = 0;
  int non_client_height_ = 0;
};

}  // namespace spring_boot_starter_flutter

#endif  // FLUTTER_PLUGIN_SPRING_BOOT_STARTER_FLUTTER_PLUGIN_H_
