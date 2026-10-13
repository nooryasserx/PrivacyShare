import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// A transparent, click-through window that sits exactly on top of a private window.
final class OverlayWindow: NSWindow {
    let imageLayer = CALayer()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make(frame: NSRect, hiddenFromCapture: Bool, coverColor: NSColor?) -> OverlayWindow {
        let w = OverlayWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true          // clicks & typing go straight to the real app
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        if hiddenFromCapture {
            w.sharingType = .none            // visible to you, invisible to screen sharing
        }

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = coverColor?.cgColor
        w.imageLayer.frame = view.bounds
        w.imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        w.imageLayer.contentsGravity = .resize
        view.layer?.addSublayer(w.imageLayer)
        w.contentView = view
        return w
    }
}

/// Protects one private window with two overlays:
///  1. `blurWindow`  – blurred copy. Screen sharing sees this.
///  2. `clearWindow` – live clear copy, excluded from capture. Only you see this.
final class WindowMirror: NSObject {
    let windowID: CGWindowID

    private let blurWindow: OverlayWindow
    private let clearWindow: OverlayWindow
    private var activeStream: SCStream?
    private var stopped = false
    private var lastSize: CGSize = .zero
    private var gotFirstFrame = false
    private var held: [CVPixelBuffer] = []                 // main thread

    private let queue = DispatchQueue(label: "privacyshare.mirror", qos: .userInteractive)
    private var pool: CVPixelBufferPool?                   // queue
    private var poolSize: CGSize = .zero                   // queue

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    init(target: TargetWindow) {
        windowID = target.id
        let rect = Self.nsRect(fromCG: target.frame)
        // Starts as a solid cover so nothing leaks before the first blurred frame arrives.
        blurWindow = OverlayWindow.make(frame: rect, hiddenFromCapture: false,
                                   coverColor: NSColor(white: 0.18, alpha: 1))
        clearWindow = OverlayWindow.make(frame: rect, hiddenFromCapture: true, coverColor: nil)
        lastSize = rect.size
        super.init()
    }

    // MARK: Positioning (main thread, called ~30×/sec)

    func update(target: TargetWindow, appActive: Bool) {
        guard !stopped else { return }
        let rect = Self.nsRect(fromCG: target.frame)
        if rect != blurWindow.frame {
            blurWindow.setFrame(rect, display: false)
            clearWindow.setFrame(rect, display: false)
            if abs(rect.width - lastSize.width) > 1 || abs(rect.height - lastSize.height) > 1 {
                lastSize = rect.size
                resizeStream(to: rect.size)
            }
        }

        let level: NSWindow.Level
        if target.layer > 0 {
            level = NSWindow.Level(rawValue: target.layer)
        } else {
            // When the private app is in front, keep our overlays above it so clicking it
            // never pops it over the blur, even for a single frame.
            level = appActive ? .floating : .normal
        }
        if blurWindow.level != level {
            blurWindow.level = level
            clearWindow.level = level
        }

        if level == .normal {
            blurWindow.order(.above, relativeTo: Int(windowID))
        } else {
            blurWindow.orderFrontRegardless()
        }
        clearWindow.order(.above, relativeTo: blurWindow.windowNumber)
    }

    // MARK: Capture

    @MainActor
    func start(scWindow: SCWindow) async {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let newStream = SCStream(filter: filter, configuration: Self.config(for: scWindow.frame.size), delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await newStream.startCapture()
        } catch {
            return
        }
        if stopped {
            try? await newStream.stopCapture()
            return
        }
        activeStream = newStream
    }

    func stop() {
        stopped = true
        blurWindow.orderOut(nil)
        clearWindow.orderOut(nil)
        held.removeAll()
        if let current = activeStream {
            activeStream = nil
            Task { try? await current.stopCapture() }
        }
    }

    private func resizeStream(to size: CGSize) {
        activeStream?.updateConfiguration(Self.config(for: size)) { _ in }
    }

    private static func config(for size: CGSize) -> SCStreamConfiguration {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.width = max(2, Int(size.width * scale))
        config.height = max(2, Int(size.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.queueDepth = 6
        if #available(macOS 14.0, *) {
            config.ignoreShadowsSingleWindow = true
        }
        return config
    }

    /// CoreGraphics (top-left origin) -> AppKit (bottom-left origin of the primary screen).
    static func nsRect(fromCG r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Frame processing (runs on `queue`)

    fileprivate func handle(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: width, height: height)

        if pool == nil || poolSize != size {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &newPool)
            pool = newPool
            poolSize = size
        }

        var outBuffer: CVPixelBuffer?
        guard let pool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer) == kCVReturnSuccess,
              let out = outBuffer
        else { return }

        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let rules = PrivacySettings.shared.snapshot()
        let covered = Obscurer.obscure(input, style: rules.style, intensity: rules.intensity)
        Self.ciContext.render(covered, to: out, bounds: input.extent, colorSpace: Self.sRGB)
        CVBufferSetAttachment(out, kCVImageBufferCGColorSpaceKey, Self.sRGB, .shouldPropagate)

        guard let blurSurface = CVPixelBufferGetIOSurface(out)?.takeUnretainedValue(),
              let clearSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.blurWindow.imageLayer.contents = blurSurface
            self.clearWindow.imageLayer.contents = clearSurface
            if !self.gotFirstFrame {
                self.gotFirstFrame = true
                self.blurWindow.contentView?.layer?.backgroundColor = nil
            }
            CATransaction.commit()

            self.held.append(pixelBuffer)
            self.held.append(out)
            if self.held.count > 6 { self.held.removeFirst(self.held.count - 6) }
        }
    }
}

extension WindowMirror: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        handle(pixelBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {}
}
