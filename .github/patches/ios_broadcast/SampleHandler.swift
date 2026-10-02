// Comtech: the broadcast extension that shares an iPhone or iPad screen.
// iOS runs it while the user broadcasts (Control Center → Screen Recording,
// choosing this app). It starts RustDesk's sharing side, which registers the
// device and takes connections, and hands it each screen frame.
import CoreMedia
import CoreVideo
import ReplayKit
import UIKit
import os

@_silgen_name("comtech_share_start")
func comtech_share_start(_ appDir: UnsafePointer<CChar>, _ custom: UnsafePointer<CChar>,
                         _ vendorId: UnsafePointer<CChar>, _ code: UnsafePointer<CChar>,
                         _ deviceName: UnsafePointer<CChar>)

@_silgen_name("comtech_share_stop")
func comtech_share_stop()

@_silgen_name("comtech_share_frame_nv12")
func comtech_share_frame_nv12(_ y: UnsafePointer<UInt8>, _ yStride: Int32,
                              _ uv: UnsafePointer<UInt8>, _ uvStride: Int32,
                              _ width: Int32, _ height: Int32, _ maxSide: Int32)

@_silgen_name("comtech_share_note")
func comtech_share_note(_ message: UnsafePointer<CChar>)

class SampleHandler: RPBroadcastSampleHandler {
    private var lastFrame: CFAbsoluteTime = 0
    private var lastNote: CFAbsoluteTime = 0
    // the size frames are shared at, chosen once: a size change mid-way
    // would stall the picture
    private var maxSide: Int32 = 1280

    /// what iOS still lets the extension use before ending it (about 50 MB in all)
    private func availableMB() -> Int {
        if #available(iOS 13.0, *) {
            return Int(os_proc_available_memory() / 1_048_576)
        }
        return 0
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // the extension's own folder; it can't write to the app's
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RustDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // the signed settings the Client Builder put in the app this
        // extension sits in (App.app/PlugIns/ComtechBroadcast.appex)
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let customUrl = app.appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/custom.txt")
        let custom = (try? String(contentsOf: customUrl, encoding: .utf8)) ?? ""
        // the app shows an ID made from this, so the user can read it out
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        // the extension makes the one-time code and the app shows it
        comtech_share_start(dir.path, custom, vendorId, "", UIDevice.current.name)
        // a sharper picture when there's room for it
        let free = availableMB()
        maxSide = free >= 45 ? 1800 : (free >= 32 ? 1440 : 1280)
        comtech_share_note("broadcast started: \(free) MB free, sharing at up to \(maxSide) px")
    }

    override func broadcastFinished() {
        comtech_share_stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // up to 30 frames a second
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastFrame < 1.0 / 30 { return }
        lastFrame = now
        if now - lastNote > 30 {
            lastNote = now
            comtech_share_note("\(availableMB()) MB free")
        }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        // iOS broadcasts in NV12: a Y plane and an interleaved UV plane
        guard CVPixelBufferGetPlaneCount(pb) == 2,
              let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0),
              let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return }
        comtech_share_frame_nv12(
            y.assumingMemoryBound(to: UInt8.self), Int32(CVPixelBufferGetBytesPerRowOfPlane(pb, 0)),
            uv.assumingMemoryBound(to: UInt8.self), Int32(CVPixelBufferGetBytesPerRowOfPlane(pb, 1)),
            Int32(CVPixelBufferGetWidth(pb)), Int32(CVPixelBufferGetHeight(pb)), maxSide)
    }
}
