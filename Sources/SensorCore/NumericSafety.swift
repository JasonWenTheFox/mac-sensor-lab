import Foundation

enum SensorNumericSafety {
  static func sum(_ lhs: UInt64, _ rhs: UInt64) -> UInt64? {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? nil : result.partialValue
  }

  static func product(_ lhs: UInt64, _ rhs: UInt64) -> UInt64? {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    return result.overflow ? nil : result.partialValue
  }

  static func uint64(_ value: Double) -> UInt64? {
    // `Double(UInt64.max)` rounds up to 2^64, so the upper comparison must be strict.
    guard value.isFinite, value >= 0, value < Double(UInt64.max) else { return nil }
    return UInt64(value)
  }

  /// Preserves integer registry counters without allowing signed values to wrap through
  /// `NSNumber.uint64Value` or accepting fractional/floating-point payloads.
  static func uint64(_ value: NSNumber?) -> UInt64? {
    guard let value, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
    let text = value.stringValue
    guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else {
      return nil
    }
    return UInt64(text)
  }

  static func boundedNonnegativeInteger(_ value: Double, maximum: Int) -> Int? {
    guard value.isFinite, value >= 0, maximum >= 0 else { return nil }
    return Int(min(value.rounded(.down), Double(maximum)))
  }
}

struct OptionalUInt64CounterAccumulator: Equatable {
  private(set) var value: UInt64?
  private(set) var didOverflow = false

  mutating func add(_ next: UInt64?) {
    guard !didOverflow, let next else { return }
    guard let value else {
      self.value = next
      return
    }
    guard let total = SensorNumericSafety.sum(value, next) else {
      self.value = nil
      didOverflow = true
      return
    }
    self.value = total
  }
}
