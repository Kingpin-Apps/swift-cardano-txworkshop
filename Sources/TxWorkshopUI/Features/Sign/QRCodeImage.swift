import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code for `text`, drawn crisply at any size.
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            image
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(Text("QR code", bundle: #bundle))
        }
    }

    static func image(_ text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage,
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
