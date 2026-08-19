import Foundation

public enum SensorFormatting {
  public static func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
  }

  public static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
  }

  public static func percentage(_ value: Double) -> String {
    "\(decimal(value, fractionDigits: 1))%"
  }

  public static func csvCell(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
      return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}
