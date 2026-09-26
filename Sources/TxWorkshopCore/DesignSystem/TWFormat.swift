import Foundation

/// Formatting shared across the app.
public enum TWFormat {
    /// Lovelace as ada, with all six decimals: `₳ 1,234.500000`.
    public static func ada(_ lovelace: Int64) -> String {
        let sign = lovelace < 0 ? "−" : ""
        let magnitude = lovelace.magnitude
        let fraction = String(format: "%06d", Int(magnitude % 1_000_000))
        return "\(sign)₳ \((magnitude / 1_000_000).formatted()).\(fraction)"
    }

    public static func ada(_ lovelace: UInt64) -> String {
        ada(Int64(clamping: lovelace))
    }
}
