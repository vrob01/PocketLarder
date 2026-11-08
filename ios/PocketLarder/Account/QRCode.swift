import CoreImage.CIFilterBuiltins
import UIKit

/// A QR code of `text`, scaled by a whole number without interpolation, so that every module keeps sharp edges.
func qrImage(_ text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: image)
}
