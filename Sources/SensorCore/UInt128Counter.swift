struct UInt128Counter: Equatable, Comparable, Sendable {
  let low: UInt64
  let high: UInt64

  static let zero = UInt128Counter(low: 0, high: 0)

  var isZero: Bool { low == 0 && high == 0 }

  static func < (lhs: UInt128Counter, rhs: UInt128Counter) -> Bool {
    lhs.high == rhs.high ? lhs.low < rhs.low : lhs.high < rhs.high
  }

  func multiplied(by multiplier: UInt64) -> UInt128Counter? {
    if multiplier == 0 || isZero { return .zero }

    let lowerProduct = low.multipliedFullWidth(by: multiplier)
    let upperProduct = high.multipliedFullWidth(by: multiplier)
    guard upperProduct.high == 0 else { return nil }

    let (resultHigh, overflow) = upperProduct.low.addingReportingOverflow(lowerProduct.high)
    guard !overflow else { return nil }
    return UInt128Counter(low: lowerProduct.low, high: resultHigh)
  }

  var decimalString: String {
    if isZero { return "0" }

    var words = [
      UInt32(truncatingIfNeeded: high >> 32),
      UInt32(truncatingIfNeeded: high),
      UInt32(truncatingIfNeeded: low >> 32),
      UInt32(truncatingIfNeeded: low),
    ]
    var digits = ""

    while words.contains(where: { $0 != 0 }) {
      var remainder: UInt64 = 0
      for index in words.indices {
        let dividend = (remainder << 32) | UInt64(words[index])
        words[index] = UInt32(dividend / 10)
        remainder = dividend % 10
      }
      digits.append(Character(String(remainder)))
    }

    return String(digits.reversed())
  }
}
