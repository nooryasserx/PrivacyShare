import CoreImage

enum Obscurer {
    static func obscure(_ image: CIImage, style: ObscureStyle, intensity: Double) -> CIImage {
        let extent = image.extent
        switch style {
        case .blur:
            // Downscale -> blur -> upscale: fast on the GPU and makes text unreadable.
            let s: CGFloat = 0.125
            return image
                .transformed(by: CGAffineTransform(scaleX: s, y: s))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: intensity)
                .transformed(by: CGAffineTransform(scaleX: 1 / s, y: 1 / s))
                .cropped(to: extent)
        case .pixelate:
            return image
                .clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: max(8, intensity * 4),
                    kCIInputCenterKey: CIVector(x: 0, y: 0),
                ])
                .cropped(to: extent)
        case .solid:
            return CIImage(color: CIColor(red: 0.13, green: 0.14, blue: 0.16)).cropped(to: extent)
        }
    }
}
