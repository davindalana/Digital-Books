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
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

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
