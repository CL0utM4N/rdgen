// Comtech: iPhones save updates to Files, and share them on to AltStore or
// SideStore. iOS can't install an app by itself, so the app only gets as far
// as handing the downloaded IPA over. comtech_phone_update.dart calls this
// through the "comtech_update" channel.
import Flutter
import UIKit

func comtechRegisterUpdates(_ registry: FlutterPluginRegistry) {
  guard let registrar = registry.registrar(forPlugin: "ComtechUpdate") else { return }
  let channel = FlutterMethodChannel(name: "comtech_update", binaryMessenger: registrar.messenger())
  channel.setMethodCallHandler { call, result in
    guard call.method == "comtech_share_file",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    comtechShareFile(URL(fileURLWithPath: path))
    result(true)
  }
}

private func comtechTopViewController() -> UIViewController? {
  let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.flatMap { $0.windows }.first
  var top = window?.rootViewController
  while let presented = top?.presentedViewController {
    top = presented
  }
  return top
}

private func comtechShareFile(_ url: URL) {
  DispatchQueue.main.async {
    guard let top = comtechTopViewController() else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // iPads show the sheet as a popover, which needs somewhere to point
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = top.view
      popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
  }
}
