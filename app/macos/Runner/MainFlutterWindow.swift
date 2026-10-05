import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable desktop size, centred on the current screen.
    let size = NSSize(width: 1320, height: 860)
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
    self.setFrame(NSRect(origin: origin, size: size), display: true)
    self.minSize = NSSize(width: 420, height: 560)
    self.title = "LocalAILine"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
