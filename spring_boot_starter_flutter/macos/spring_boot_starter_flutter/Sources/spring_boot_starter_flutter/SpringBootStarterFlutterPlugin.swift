import Cocoa
import FlutterMacOS

/// The macOS side of the desktop window of spring_boot_starter_flutter: one
/// method channel, `dev.farumazula/spring_boot_starter_flutter/window`.
///
/// - `apply`: the title (`NSWindow.title`), the title bar (`transparent`,
///   `hidden`), the minimum and maximum sizes (`NSWindow.contentMinSize`,
///   `contentMaxSize`; the zoom button respects the maximum) and the
///   initial size (centered); answers the space the window buttons take.
/// - `describe`: the window as it is now (for tests).
/// - `startDrag`: `NSWindow.performDrag`; `toggleMaximize`: the system's
///   double-click action on a title bar.
public final class SpringBootStarterFlutterPlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private var titleBar = "default"
  // The last left mouse down: performDrag needs an event, and the call
  // from Dart arrives after the one that started the drag.
  private var lastMouseDown: NSEvent?
  private var monitor: Any?

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      self?.lastMouseDown = event
      return event
    }
  }

  deinit {
    if let monitor = monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.farumazula/spring_boot_starter_flutter/window",
      binaryMessenger: registrar.messenger)
    let instance = SpringBootStarterFlutterPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let window = registrar.view?.window else {
      result(FlutterError(code: "no_window", message: "The Flutter view has no window", details: nil))
      return
    }
    switch call.method {
    case "apply":
      apply(call.arguments as? [String: Any] ?? [:], to: window)
      result(["insets": insets(of: window)])
    case "describe":
      result(describe(window))
    case "startDrag":
      startDrag(window)
      result(nil)
    case "toggleMaximize":
      toggleMaximize(window)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func apply(_ arguments: [String: Any], to window: NSWindow) {
    // The title bar first: with the full-size content view the content is
    // the whole window, which the sizes below are the sizes of.
    if let title = arguments["title"] as? String {
      window.title = title
    }
    titleBar = arguments["titleBar"] as? String ?? "default"
    if titleBar == "transparent" || titleBar == "hidden" {
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.styleMask.insert(.fullSizeContentView)
    }
    if titleBar == "hidden" {
      for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
      }
    }
    if let width = (arguments["minWidth"] as? NSNumber)?.doubleValue,
      let height = (arguments["minHeight"] as? NSNumber)?.doubleValue
    {
      window.contentMinSize = NSSize(width: width, height: height)
    }
    if let width = (arguments["maxWidth"] as? NSNumber)?.doubleValue,
      let height = (arguments["maxHeight"] as? NSNumber)?.doubleValue
    {
      window.contentMaxSize = NSSize(width: width, height: height)
    }
    if let width = (arguments["initialWidth"] as? NSNumber)?.doubleValue,
      let height = (arguments["initialHeight"] as? NSNumber)?.doubleValue
    {
      window.setContentSize(NSSize(width: width, height: height))
      window.center()
    }
  }

  // The traffic lights' area: from the left edge to the zoom button and a
  // margin, the title bar's height. (Their frames are not laid out before
  // the window is shown: the system's usual measures stand in.)
  private func insets(of window: NSWindow) -> [String: Double] {
    guard titleBar == "transparent" else {
      return ["left": 0, "top": 0, "right": 0, "bottom": 0]
    }
    var left = 70.0
    if let zoom = window.standardWindowButton(.zoomButton) {
      let right = zoom.convert(zoom.bounds, to: nil).maxX
      if right > 0 {
        left = Double(right) + 8
      }
    }
    var top = Double(window.frame.height - window.contentLayoutRect.height)
    if top <= 0 {
      top = 28
    }
    return ["left": left.rounded(.up), "top": top.rounded(.up), "right": 0, "bottom": 0]
  }

  private func describe(_ window: NSWindow) -> [String: Any] {
    let content = window.contentView?.bounds.size ?? .zero
    // No maximum is the system's "unbounded" (the largest float).
    let max = window.contentMaxSize
    let hasMax = max.width < 1_000_000 && max.height < 1_000_000
    return [
      "contentWidth": Double(content.width),
      "contentHeight": Double(content.height),
      "minWidth": Double(window.contentMinSize.width),
      "minHeight": Double(window.contentMinSize.height),
      "maxWidth": hasMax ? Double(max.width) : 0.0,
      "maxHeight": hasMax ? Double(max.height) : 0.0,
      "title": window.title,
      "titleBar": titleBar,
      "titlebarAppearsTransparent": window.titlebarAppearsTransparent,
      "titleHidden": window.titleVisibility == .hidden,
      "fullSizeContentView": window.styleMask.contains(.fullSizeContentView),
      "buttonsHidden": window.standardWindowButton(.closeButton)?.isHidden ?? false,
      "x": Double(window.frame.origin.x),
      "y": Double(window.frame.origin.y),
    ]
  }

  private func startDrag(_ window: NSWindow) {
    if let current = NSApp.currentEvent,
      current.type == .leftMouseDown || current.type == .leftMouseDragged
    {
      window.performDrag(with: current)
    } else if let down = lastMouseDown {
      window.performDrag(with: down)
    }
  }

  // What a double click on the title bar does is the user's setting
  // (System Settings > Desktop & Dock): zoom, minimize or nothing.
  private func toggleMaximize(_ window: NSWindow) {
    switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
    case "Minimize":
      window.miniaturize(nil)
    case "None":
      break
    default:
      window.zoom(nil)
    }
  }
}
