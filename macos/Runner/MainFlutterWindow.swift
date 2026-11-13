import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let targetToolbarHeight: CGFloat = 80.0
  private let targetTrafficLightCenterY: CGFloat = 40.0
  private let targetTrafficLightLeftX: CGFloat = 20.0
  private var windowChromeChannel: FlutterMethodChannel?
  private var trafficLightsVisible = true

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set expansive default window size (1280x850, centered on screen) with 700x500 minimum.
    let defaultWidth: CGFloat = 1280.0
    let defaultHeight: CGFloat = 850.0
    let minWidth: CGFloat = 700.0
    let minHeight: CGFloat = 500.0

    self.minSize = NSSize(width: minWidth, height: minHeight)

    let screen = self.screen ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1800, height: 1169)
    let finalWidth = min(defaultWidth, max(minWidth, visibleFrame.width * 0.92))
    let finalHeight = min(defaultHeight, max(minHeight, visibleFrame.height * 0.92))
    let originX = visibleFrame.origin.x + (visibleFrame.width - finalWidth) / 2.0
    let originY = visibleFrame.origin.y + (visibleFrame.height - finalHeight) / 2.0
    let targetFrame = NSRect(x: originX, y: originY, width: finalWidth, height: finalHeight)

    self.setFrame(targetFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    windowChromeChannel = FlutterMethodChannel(
      name: "digital_books/window_chrome",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChromeChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setTrafficLightsVisible",
            let visible = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        self?.trafficLightsVisible = visible
        self?.adjustTrafficLights()
        result(nil)
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowStateDidChange),
      name: NSWindow.didResizeNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowStateDidChange),
      name: NSWindow.didExitFullScreenNotification,
      object: self
    )

    super.awakeFromNib()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func windowStateDidChange() {
    adjustTrafficLights()
  }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    adjustTrafficLights()
  }

  private func adjustTrafficLights() {
    if styleMask.contains(.fullScreen) { return }
    guard let close = standardWindowButton(.closeButton),
          let min = standardWindowButton(.miniaturizeButton),
          let zoom = standardWindowButton(.zoomButton),
          let titlebarView = close.superview,
          let containerView = titlebarView.superview else { return }

    close.isHidden = !trafficLightsVisible
    min.isHidden = !trafficLightsVisible
    zoom.isHidden = !trafficLightsVisible

    let winH = frame.height
    let containerOriginY = winH - targetToolbarHeight
    containerView.setFrameOrigin(NSPoint(x: 0, y: containerOriginY))
    containerView.setFrameSize(NSSize(width: frame.width, height: targetToolbarHeight))
    titlebarView.setFrameOrigin(NSPoint(x: 0, y: 0))
    titlebarView.setFrameSize(NSSize(width: frame.width, height: targetToolbarHeight))

    let btnH = close.frame.height
    let desiredMidYInWin = winH - targetTrafficLightCenterY
    let desiredOriginYInSuper = desiredMidYInWin - (btnH / 2.0) - containerOriginY

    let btnSpacing: CGFloat = 8.0
    let closeX = targetTrafficLightLeftX
    let minX = closeX + close.frame.width + btnSpacing
    let zoomX = minX + min.frame.width + btnSpacing

    close.setFrameOrigin(NSPoint(x: closeX, y: desiredOriginYInSuper))
    min.setFrameOrigin(NSPoint(x: minX, y: desiredOriginYInSuper))
    zoom.setFrameOrigin(NSPoint(x: zoomX, y: desiredOriginYInSuper))
  }
}
