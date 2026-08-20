import Foundation

public struct SensorSeriesStatistics: Equatable, Sendable {
  public let sampleCount: Int
  public let latest: Double
  public let minimum: Double
  public let maximum: Double
  public let average: Double

  public var range: Double { maximum - minimum }

  /// Latest value mapped into the observed range. Nil until the range is non-zero.
  public var relativePosition: Double? {
    guard maximum > minimum else { return nil }
    let magnitude = max(abs(minimum), abs(maximum), 1)
    let normalizedRange = maximum / magnitude - minimum / magnitude
    let position = (latest / magnitude - minimum / magnitude) / normalizedRange
    guard position.isFinite else { return nil }
    return min(max(position, 0), 1)
  }

  public init?(values: [Double]) {
    let finiteValues = values.filter(\.isFinite)
    guard let latest = finiteValues.last,
      let minimum = finiteValues.min(),
      let maximum = finiteValues.max()
    else { return nil }

    let magnitude = finiteValues.reduce(0) { max($0, abs($1)) }
    let normalizedAverage =
      magnitude == 0
      ? 0
      : finiteValues.reduce(0) { $0 + $1 / magnitude } / Double(finiteValues.count)
    let average = normalizedAverage * magnitude
    guard average.isFinite else { return nil }

    self.sampleCount = finiteValues.count
    self.latest = latest
    self.minimum = minimum
    self.maximum = maximum
    self.average = average
  }
}

/// A zero-offset, one-point illuminance estimate supplied by the user.
///
/// This intentionally does not claim that the Apple SPU raw channel is lux.
/// It scales a positive raw reference to a positive external lux reference.
public struct AmbientLuxCalibration: Codable, Equatable, Sendable {
  public let rawReference: Double
  public let luxReference: Double
  public let capturedAt: Date

  public var scale: Double { luxReference / rawReference }

  public init?(rawReference: Double, luxReference: Double, capturedAt: Date = .now) {
    let scale = luxReference / rawReference
    guard rawReference.isFinite, rawReference > 0,
      luxReference.isFinite, luxReference > 0,
      scale.isFinite, scale > 0,
      capturedAt.timeIntervalSinceReferenceDate.isFinite
    else { return nil }
    self.rawReference = rawReference
    self.luxReference = luxReference
    self.capturedAt = capturedAt
  }

  private enum CodingKeys: String, CodingKey {
    case rawReference
    case luxReference
    case capturedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawReference = try container.decode(Double.self, forKey: .rawReference)
    let luxReference = try container.decode(Double.self, forKey: .luxReference)
    let capturedAt = try container.decode(Date.self, forKey: .capturedAt)
    guard
      let calibration = AmbientLuxCalibration(
        rawReference: rawReference,
        luxReference: luxReference,
        capturedAt: capturedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .rawReference,
        in: container,
        debugDescription: "Ambient-light calibration values must be finite and positive."
      )
    }
    self = calibration
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rawReference, forKey: .rawReference)
    try container.encode(luxReference, forKey: .luxReference)
    try container.encode(capturedAt, forKey: .capturedAt)
  }

  public func estimatedLux(for rawValue: Double) -> Double? {
    guard rawValue.isFinite, rawValue >= 0 else { return nil }
    let estimate = rawValue * scale
    return estimate.isFinite ? estimate : nil
  }

  public func estimatedChannel(for rawValue: Double) -> SensorChannel? {
    guard let estimate = estimatedLux(for: rawValue) else { return nil }
    return SensorChannel(
      id: "ambient_estimated_lux",
      label: "Estimated illuminance",
      value: estimate,
      formattedValue: SensorFormatting.decimal(estimate, fractionDigits: 1),
      unit: "lux",
      kind: .estimated,
      note: "Single-point user calibration; not calibrated or certified by Apple."
    )
  }
}

public struct RelativeAngleMeasurement: Equatable, Sendable {
  public let current: Double
  public let reference: Double
  public let delta: Double

  public init?(current: Double, reference: Double) {
    let delta = current - reference
    guard current.isFinite, reference.isFinite, delta.isFinite else { return nil }
    self.current = current
    self.reference = reference
    self.delta = delta
  }
}
