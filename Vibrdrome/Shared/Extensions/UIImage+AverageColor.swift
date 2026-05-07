#if os(iOS)
import UIKit

extension UIImage {
    /// Returns the average color of the image by scaling to 1x1 pixel.
    var averageColor: UIColor? {
        guard let cgImage else { return nil }
        let size = CGSize(width: 1, height: 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1.0
        )
    }
}
#endif

#if os(macOS)
import AppKit

extension NSImage {
    /// Returns the average color of the image by scaling to 1x1 pixel.
    var averageColor: NSColor? {
        var rect = CGRect(origin: .zero, size: self.size)
        guard let cgImage = self.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1.0
        )
    }
}
#endif
