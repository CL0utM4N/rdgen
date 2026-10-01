// Comtech: lets the app start screen sharing itself. It opens iOS's
// broadcast picker with the app's screen sharing extension chosen, so the
// user doesn't have to find it in Control Center, and says when the
// extension isn't in the installed app (some signing tools drop it).
// Added to the Runner target by add_broadcast.rb.
import Flutter
import ReplayKit
import UIKit

enum ComtechBroadcastPicker {
    static func register(with delegate: FlutterAppDelegate) {
        guard let controller = delegate.window?.rootViewController as? FlutterViewController else { return }
        let channel = FlutterMethodChannel(name: "comtech/broadcast", binaryMessenger: controller.binaryMessenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "start":
                result(start(in: controller.view))
            case "installed":
                result(extensionId() != nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// The bundle ID of the screen sharing extension inside this app, if it's there
    static func extensionId() -> String? {
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for item in items where item.pathExtension == "appex" {
            guard let bundle = Bundle(url: item),
                  let ext = bundle.infoDictionary?["NSExtension"] as? [String: Any],
                  ext["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload" else { continue }
            return bundle.bundleIdentifier
        }
        return nil
    }

    /// Opens the broadcast picker; "missing" when the extension isn't installed
    static func start(in view: UIView) -> String {
        guard let id = extensionId() else { return "missing" }
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: -100, y: -100, width: 44, height: 44))
        picker.preferredExtension = id
        picker.showsMicrophoneButton = false
        view.addSubview(picker)
        // the picker is a button; tapping it in code opens the system sheet
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .touchUpInside)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { picker.removeFromSuperview() }
        return "ok"
    }
}
