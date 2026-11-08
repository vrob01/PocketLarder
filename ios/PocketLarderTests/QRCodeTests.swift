import CoreImage
import Testing
import UIKit
@testable import PocketLarder

/// Shaped like an invite, with a dummy code.
private let example = "pocketlarder://invite?server=https%3A%2F%2Flists.example.test&code=00000000-0000-4000-8000-000000000000.dummy-code-for-tests"

@Test func qrCodeEncodesInviteURL() throws {
    let image = try #require(qrImage(example)?.cgImage)
    let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    let features = detector.features(in: CIImage(cgImage: image))
    #expect(features.count == 1)
    #expect((features.first as? CIQRCodeFeature)?.messageString == example)
}
