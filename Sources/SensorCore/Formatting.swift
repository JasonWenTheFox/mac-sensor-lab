import Foundation

public enum SensorFormatting {
  public static func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
  }

  public static func bytesPerSecond(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "Unavailable" }
    return "\(bytes(UInt64(value.rounded())))/s"
  }

  public static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
  }

  public static func percentage(_ value: Double) -> String {
    "\(decimal(value, fractionDigits: 1))%"
  }

  public static func csvCell(_ value: String) -> String {
    guard
      value.contains(",") || value.contains("\"") || value.contains("\n")
        || value.contains("\r")
    else {
      return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  /// Escapes a text field for CSV and prevents spreadsheet formula interpretation.
  /// Numeric raw-value columns intentionally continue to use `csvCell` directly.
  public static func csvTextCell(_ value: String) -> String {
    let protectedValue: String
    if let first = value.first, "=+-@\t\r".contains(first) {
      protectedValue = "'\(value)"
    } else {
      protectedValue = value
    }
    return csvCell(protectedValue)
  }
}
