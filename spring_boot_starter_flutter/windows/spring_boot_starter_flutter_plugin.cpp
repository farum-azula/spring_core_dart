#include "spring_boot_starter_flutter_plugin.h"

#include <windowsx.h>
#include <dwmapi.h>

#include <algorithm>
#include <cmath>
#include <variant>

namespace spring_boot_starter_flutter {

namespace {

const char kChannelName[] = "dev.farumazula/spring_boot_starter_flutter/window";

// DWMWA_CAPTION_BUTTON_BOUNDS, in case an older SDK header lacks it.
const DWORD kCaptionButtonBounds = 5;

// Logical pixels of the caption buttons when Windows cannot say (the
// window is not shown yet): three buttons of 46 by 32.
const double kFallbackButtonsWidth = 138;
const double kFallbackButtonsHeight = 32;

std::optional<double> ReadNumber(const flutter::EncodableMap& map,
                                 const char* key) {
  auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return std::nullopt;
  }
  if (const double* value = std::get_if<double>(&it->second)) {
    return *value;
  }
  if (const int32_t* value = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  if (const int64_t* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  return std::nullopt;
}

std::string ReadString(const flutter::EncodableMap& map, const char* key,
                       const std::string& fallback) {
  auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it != map.end()) {
    if (const std::string* value = std::get_if<std::string>(&it->second)) {
      return *value;
    }
  }
  return fallback;
}

double ScaleOf(HWND hwnd) {
  UINT dpi = ::GetDpiForWindow(hwnd);
  return dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
}

// The thickness of the sizing border of a window at the DPI of [hwnd].
int FrameThickness(HWND hwnd) {
  UINT dpi = ::GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = 96;
  }
  return ::GetSystemMetricsForDpi(SM_CXFRAME, dpi) +
         ::GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

int CaptionHeight(HWND hwnd) {
  UINT dpi = ::GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = 96;
  }
  return ::GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
}

int ToPixels(double logical, double scale) {
  return static_cast<int>(std::lround(logical * scale));
}

}  // namespace

// static
void SpringBootStarterFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SpringBootStarterFlutterPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

SpringBootStarterFlutterPlugin::SpringBootStarterFlutterPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

SpringBootStarterFlutterPlugin::~SpringBootStarterFlutterPlugin() {
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

HWND SpringBootStarterFlutterPlugin::TopLevelWindow() const {
  flutter::FlutterView* view = registrar_->GetView();
  if (view == nullptr) {
    return nullptr;
  }
  return ::GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void SpringBootStarterFlutterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND hwnd = TopLevelWindow();
  if (hwnd == nullptr) {
    result->Error("no_window", "The Flutter view has no window");
    return;
  }
  const std::string& method = call.method_name();
  if (method == "apply") {
    flutter::EncodableMap empty;
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    Apply(hwnd, arguments == nullptr ? empty : *arguments);
    flutter::EncodableMap answer;
    answer[flutter::EncodableValue("insets")] =
        flutter::EncodableValue(Insets(hwnd));
    result->Success(flutter::EncodableValue(answer));
  } else if (method == "describe") {
    result->Success(flutter::EncodableValue(Describe(hwnd)));
  } else if (method == "startDrag") {
    // What a click on the caption does: the system's move loop, started
    // from the button that is down. Posted, so this call answers first.
    POINT cursor;
    ::GetCursorPos(&cursor);
    ::ReleaseCapture();
    ::PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION,
                  MAKELPARAM(cursor.x, cursor.y));
    result->Success();
  } else if (method == "toggleMaximize") {
    ::ShowWindow(hwnd, ::IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void SpringBootStarterFlutterPlugin::NonClientSize(HWND hwnd, int* width,
                                                   int* height) {
  RECT window_rect;
  RECT client_rect;
  if (!::IsIconic(hwnd) && ::GetWindowRect(hwnd, &window_rect) &&
      ::GetClientRect(hwnd, &client_rect) &&
      client_rect.right - client_rect.left > 0) {
    non_client_width_ = (window_rect.right - window_rect.left) -
                        (client_rect.right - client_rect.left);
    non_client_height_ = (window_rect.bottom - window_rect.top) -
                         (client_rect.bottom - client_rect.top);
  }
  *width = non_client_width_;
  *height = non_client_height_;
}

void SpringBootStarterFlutterPlugin::Apply(
    HWND hwnd, const flutter::EncodableMap& arguments) {
  title_bar_ = ReadString(arguments, "titleBar", "default");

  auto min_width = ReadNumber(arguments, "minWidth");
  auto min_height = ReadNumber(arguments, "minHeight");
  if (min_width && min_height) {
    has_min_size_ = true;
    min_width_ = *min_width;
    min_height_ = *min_height;
  }

  if (title_bar_ == "transparent") {
    // The frame is extended into the client area: the system keeps the
    // caption buttons and draws them over the content, which now starts at
    // the top edge (WM_NCCALCSIZE below).
    MARGINS margins = {0, 0, FrameThickness(hwnd) + CaptionHeight(hwnd), 0};
    ::DwmExtendFrameIntoClientArea(hwnd, &margins);
  } else if (title_bar_ == "hidden") {
    // No caption, no system menu: no buttons. The sizing border stays; one
    // extended pixel gives the borderless window its shadow.
    LONG_PTR style = ::GetWindowLongPtr(hwnd, GWL_STYLE);
    style &= ~static_cast<LONG_PTR>(WS_CAPTION | WS_SYSMENU);
    style |= WS_THICKFRAME;
    ::SetWindowLongPtr(hwnd, GWL_STYLE, style);
    MARGINS margins = {0, 0, 1, 0};
    ::DwmExtendFrameIntoClientArea(hwnd, &margins);
  }
  if (title_bar_ != "default") {
    // The new frame: WM_NCCALCSIZE runs again.
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE);
  }

  auto width = ReadNumber(arguments, "initialWidth");
  auto height = ReadNumber(arguments, "initialHeight");
  if (width && height) {
    // The size is the client area's; the frame comes on top. Centered on
    // the work area of the monitor the window is on.
    double scale = ScaleOf(hwnd);
    int frame_width = 0;
    int frame_height = 0;
    NonClientSize(hwnd, &frame_width, &frame_height);
    int outer_width = ToPixels(*width, scale) + frame_width;
    int outer_height = ToPixels(*height, scale) + frame_height;
    MONITORINFO monitor = {};
    monitor.cbSize = sizeof(monitor);
    int x = 0;
    int y = 0;
    if (::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                         &monitor)) {
      x = monitor.rcWork.left +
          ((monitor.rcWork.right - monitor.rcWork.left) - outer_width) / 2;
      y = monitor.rcWork.top +
          ((monitor.rcWork.bottom - monitor.rcWork.top) - outer_height) / 2;
    }
    ::SetWindowPos(hwnd, nullptr, x, y, outer_width, outer_height,
                   SWP_NOZORDER | SWP_NOACTIVATE);
  }
}

flutter::EncodableMap SpringBootStarterFlutterPlugin::Insets(HWND hwnd) const {
  double right = 0;
  double top = 0;
  if (title_bar_ == "transparent") {
    double scale = ScaleOf(hwnd);
    RECT bounds = {};
    if (SUCCEEDED(::DwmGetWindowAttribute(hwnd, kCaptionButtonBounds, &bounds,
                                          sizeof(bounds))) &&
        bounds.right > bounds.left) {
      right = std::ceil((bounds.right - bounds.left) / scale);
      top = std::ceil(bounds.bottom / scale);
    } else {
      right = kFallbackButtonsWidth;
      top = kFallbackButtonsHeight;
    }
  }
  flutter::EncodableMap insets;
  insets[flutter::EncodableValue("left")] = flutter::EncodableValue(0.0);
  insets[flutter::EncodableValue("top")] = flutter::EncodableValue(top);
  insets[flutter::EncodableValue("right")] = flutter::EncodableValue(right);
  insets[flutter::EncodableValue("bottom")] = flutter::EncodableValue(0.0);
  return insets;
}

flutter::EncodableMap SpringBootStarterFlutterPlugin::Describe(
    HWND hwnd) const {
  double scale = ScaleOf(hwnd);
  RECT client = {};
  RECT window = {};
  ::GetClientRect(hwnd, &client);
  ::GetWindowRect(hwnd, &window);
  flutter::EncodableMap map;
  map[flutter::EncodableValue("contentWidth")] =
      flutter::EncodableValue((client.right - client.left) / scale);
  map[flutter::EncodableValue("contentHeight")] =
      flutter::EncodableValue((client.bottom - client.top) / scale);
  map[flutter::EncodableValue("minWidth")] =
      flutter::EncodableValue(has_min_size_ ? min_width_ : 0.0);
  map[flutter::EncodableValue("minHeight")] =
      flutter::EncodableValue(has_min_size_ ? min_height_ : 0.0);
  map[flutter::EncodableValue("titleBar")] = flutter::EncodableValue(title_bar_);
  map[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(window.left));
  map[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(window.top));
  return map;
}

std::optional<LRESULT> SpringBootStarterFlutterPlugin::HandleWindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  const bool transparent = title_bar_ == "transparent";

  if (transparent) {
    // The caption buttons are the system's: it handles their hover and
    // clicks, given the messages first.
    LRESULT dwm_result = 0;
    if (::DwmDefWindowProc(hwnd, message, wparam, lparam, &dwm_result)) {
      return dwm_result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      if (!has_min_size_) {
        break;
      }
      double scale = ScaleOf(hwnd);
      int frame_width = 0;
      int frame_height = 0;
      NonClientSize(hwnd, &frame_width, &frame_height);
      MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = ToPixels(min_width_, scale) + frame_width;
      info->ptMinTrackSize.y = ToPixels(min_height_, scale) + frame_height;
      return 0;
    }
    case WM_NCCALCSIZE: {
      if (!transparent || wparam != TRUE) {
        break;
      }
      // The client area starts at the top edge: let the system take the
      // frame off the other three sides, then give the title bar's height
      // back. A maximized window overhangs the screen by its sizing
      // border, which stays out of the client area.
      NCCALCSIZE_PARAMS* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG proposed_top = params->rgrc[0].top;
      LRESULT result = ::DefWindowProc(hwnd, message, wparam, lparam);
      if (result != 0) {
        return result;
      }
      params->rgrc[0].top =
          proposed_top + (::IsZoomed(hwnd) ? FrameThickness(hwnd) : 0);
      return 0;
    }
    case WM_NCHITTEST: {
      if (!transparent || ::IsZoomed(hwnd)) {
        break;
      }
      // The top sizing border is inside the client area now.
      LRESULT hit = ::DefWindowProc(hwnd, message, wparam, lparam);
      if (hit != HTCLIENT) {
        return hit;
      }
      POINT cursor = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RECT window;
      ::GetWindowRect(hwnd, &window);
      const int border = FrameThickness(hwnd);
      if (cursor.y >= window.top && cursor.y < window.top + border) {
        if (cursor.x < window.left + border) {
          return HTTOPLEFT;
        }
        if (cursor.x >= window.right - border) {
          return HTTOPRIGHT;
        }
        return HTTOP;
      }
      return HTCLIENT;
    }
    default:
      break;
  }
  return std::nullopt;
}

}  // namespace spring_boot_starter_flutter
