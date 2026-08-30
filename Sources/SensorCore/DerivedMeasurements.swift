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

/// Low-rate variation statistics for acceleration-magnitude history.
///
/// These values describe the dashboard samples only. They do not estimate vibration frequency or
/// replace a high-rate acquisition pipeline.
public struct MotionVariationStatistics: Equatable, Sendable {
  public let sampleCount: Int
  public let mean: Double
  public let rmsDeviation: Double
  public let peakToPeak: Double

  public init?(values: [Double]) {
    let finiteValues = values.filter(\.isFinite)
    guard finiteValues.count >= 2,
      let minimum = finiteValues.min(),
      let maximum = finiteValues.max()
    else { return nil }

    let magnitude = max(finiteValues.reduce(0) { max($0, abs($1)) }, 1)
    let normalizedValues = finiteValues.map { $0 / magnitude }
    var normalizedMean = 0.0
    for (index, value) in normalizedValues.enumerated() {
      normalizedMean += (value - normalizedMean) / Double(index + 1)
    }

    var normalizedMeanSquareDeviation = 0.0
    for (index, value) in normalizedValues.enumerated() {
      let squaredDeviation = (value - normalizedMean) * (value - normalizedMean)
      normalizedMeanSquareDeviation +=
        (squaredDeviation - normalizedMeanSquareDeviation) / Double(index + 1)
    }

    let mean = normalizedMean * magnitude
    let rmsDeviation = sqrt(max(normalizedMeanSquareDeviation, 0)) * magnitude
    let peakToPeak = (maximum / magnitude - minimum / magnitude) * magnitude
    guard mean.isFinite, rmsDeviation.isFinite, peakToPeak.isFinite else { return nil }

    self.sampleCount = finiteValues.count
    self.mean = mean
    self.rmsDeviation = rmsDeviation
    self.peakToPeak = peakToPeak
  }
}

/// A relative four-channel fingerprint for comparing ambient light sources on one Mac.
///
/// The undocumented SPU channels do not have a published spectral response or color-matching
/// matrix. Normalizing them can reveal relative changes, but cannot produce lux, chromaticity, or
/// correlated color temperature.
public struct AmbientSpectralFingerprint: Equatable, Sendable {
  public static let channelCount = 4

  public let components: [Double]

  public init?(values: [Double]) {
    guard values.count == Self.channelCount,
      values.allSatisfy({ $0.isFinite && $0 >= 0 }),
      let maximum = values.max(),
      maximum > 0
    else { return nil }

    let scaled = values.map { $0 / maximum }
    let scaledTotal = scaled.reduce(0, +)
    guard scaledTotal.isFinite, scaledTotal > 0 else { return nil }
    let components = scaled.map { $0 / scaledTotal }
    guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
    self.components = components
  }

  /// Total-variation distance in the closed range 0...1.
  public func distance(to reference: AmbientSpectralFingerprint) -> Double {
    var total = 0.0
    for (current, baseline) in zip(components, reference.components) {
      total += abs(current - baseline)
    }
    guard total.isFinite else { return 1 }
    return min(max(total / 2, 0), 1)
  }

  public func largestShiftChannel(comparedTo reference: AmbientSpectralFingerprint) -> Int? {
    zip(components, reference.components)
      .enumerated()
      .max { abs($0.element.0 - $0.element.1) < abs($1.element.0 - $1.element.1) }?
      .offset
  }
}

/// A deliberately conservative estimate from recent public battery-charge history.
///
/// The estimate is only about the observed dashboard window. Callers must additionally verify that
/// the current power source is the battery and that charging is off before presenting it.
public struct BatteryDischargeEstimate: Equatable, Sendable {
  public static let minimumSampleCount = 4
  public static let minimumDuration: TimeInterval = 5 * 60
  public static let minimumChargeDrop = 0.5
  public static let maximumHistoryPointCount = 600

  public let sampleCount: Int
  public let duration: TimeInterval
  public let chargeDrop: Double
  public let percentPerHour: Double
  public let estimatedHoursToEmpty: Double

  public static func isEligible(snapshot: SensorSnapshot) -> Bool {
    guard snapshot.id == "power.source", snapshot.status == .available,
      snapshot.channels.first(where: { $0.id == "active_source" })?.formattedValue == "Battery",
      snapshot.channels.first(where: { $0.id == "battery_charging" })?.value == 0
    else { return false }
    return true
  }

  public init?(points input: [SensorHistoryPoint]) {
    let bounded = Array(input.suffix(Self.maximumHistoryPointCount))
    guard bounded.count >= Self.minimumSampleCount else { return nil }
    for point in bounded {
      guard point.timestamp.timeIntervalSinceReferenceDate.isFinite,
        point.value.isFinite,
        (0...100).contains(point.value)
      else { return nil }
    }
    for pair in zip(bounded, bounded.dropFirst()) {
      guard pair.0.timestamp < pair.1.timestamp else { return nil }
    }

    // A rise greater than controller rounding noise indicates that the old window may include a
    // charging session. Restart after the last such transition instead of mixing regimes.
    var startIndex = 0
    for index in 1..<bounded.count where bounded[index].value - bounded[index - 1].value > 0.25 {
      startIndex = index
    }
    let points = Array(bounded[startIndex...])
    guard points.count >= Self.minimumSampleCount,
      let first = points.first,
      let last = points.last
    else { return nil }

    let duration = last.timestamp.timeIntervalSince(first.timestamp)
    let chargeDrop = first.value - last.value
    guard duration.isFinite, duration >= Self.minimumDuration,
      chargeDrop.isFinite, chargeDrop >= Self.minimumChargeDrop
    else { return nil }

    let normalizedTimes = points.map {
      $0.timestamp.timeIntervalSince(first.timestamp) / duration
    }
    let normalizedCharges = points.map { $0.value / 100 }
    let count = Double(points.count)
    let meanTime = normalizedTimes.reduce(0, +) / count
    let meanCharge = normalizedCharges.reduce(0, +) / count
    var covariance = 0.0
    var variance = 0.0
    for (time, charge) in zip(normalizedTimes, normalizedCharges) {
      let timeDelta = time - meanTime
      covariance += timeDelta * (charge - meanCharge)
      variance += timeDelta * timeDelta
    }
    guard covariance.isFinite, variance.isFinite, variance > 0 else { return nil }

    let percentageChangeAcrossWindow = covariance / variance * 100
    let durationHours = duration / 3_600
    let percentPerHour = -percentageChangeAcrossWindow / durationHours
    guard percentPerHour.isFinite, (0.1...100).contains(percentPerHour) else { return nil }
    let estimatedHoursToEmpty = last.value / percentPerHour
    guard estimatedHoursToEmpty.isFinite, (0...168).contains(estimatedHoursToEmpty) else {
      return nil
    }

    self.sampleCount = points.count
    self.duration = duration
    self.chargeDrop = chargeDrop
    self.percentPerHour = percentPerHour
    self.estimatedHoursToEmpty = estimatedHoursToEmpty
  }
}

/// Summary of the public thermal-pressure ordinal retained for UI trend display.
///
/// The 0...3 encoding preserves order only. It is not a temperature, percentage, or linear scale.
public struct ThermalPressureTrend: Equatable, Sendable {
  public let sampleCount: Int
  public let latest: SystemThermalPressure
  public let highest: SystemThermalPressure
  public let transitionCount: Int

  public init?(points input: [SensorHistoryPoint]) {
    let points = Array(input.suffix(SensorHistoryRetention.maximumPointsPerSeries))
    guard !points.isEmpty else { return nil }

    var levels: [SystemThermalPressure] = []
    levels.reserveCapacity(points.count)
    for (index, point) in points.enumerated() {
      guard point.timestamp.timeIntervalSinceReferenceDate.isFinite,
        point.value.isFinite,
        (0...3).contains(point.value),
        point.value.rounded() == point.value,
        index == 0 || points[index - 1].timestamp < point.timestamp,
        let level = SystemThermalPressure(rawValue: Int(point.value))
      else { return nil }
      levels.append(level)
    }
    guard let latest = levels.last,
      let highest = levels.max(by: { $0.rawValue < $1.rawValue })
    else { return nil }

    self.sampleCount = levels.count
    self.latest = latest
    self.highest = highest
    self.transitionCount = zip(levels, levels.dropFirst()).count { $0 != $1 }
  }
}

public struct AmbientLuxCalibrationPoint: Codable, Equatable, Sendable {
  public let rawReference: Double
  public let luxReference: Double
  public let capturedAt: Date

  public init?(rawReference: Double, luxReference: Double, capturedAt: Date = .now) {
    guard rawReference.isFinite, rawReference > 0,
      luxReference.isFinite, luxReference > 0,
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
      let point = Self(
        rawReference: rawReference,
        luxReference: luxReference,
        capturedAt: capturedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .rawReference,
        in: container,
        debugDescription: "Ambient-light calibration points must be finite and positive."
      )
    }
    self = point
  }
}

/// A bounded user-referenced illuminance estimate.
///
/// One point retains the original zero-offset scale. Two to eight strictly monotonic points use a
/// numerically normalized least-squares line. Neither mode claims Apple calibration or certified
/// photometry.
public struct AmbientLuxCalibration: Codable, Equatable, Sendable {
  public static let maximumPointCount = 8
  public let points: [AmbientLuxCalibrationPoint]

  public var rawReference: Double { points.last?.rawReference ?? .nan }
  public var luxReference: Double { points.last?.luxReference ?? .nan }
  public var capturedAt: Date { points.last?.capturedAt ?? .distantPast }
  public var pointCount: Int { points.count }
  public var scale: Double { fit?.slope ?? .nan }
  public var rootMeanSquareError: Double { fit?.rootMeanSquareError ?? .nan }

  public init?(rawReference: Double, luxReference: Double, capturedAt: Date = .now) {
    guard
      let point = AmbientLuxCalibrationPoint(
        rawReference: rawReference,
        luxReference: luxReference,
        capturedAt: capturedAt
      ),
      let calibration = Self(points: [point])
    else { return nil }
    self = calibration
  }

  public init?(points: [AmbientLuxCalibrationPoint]) {
    guard !points.isEmpty, points.count <= Self.maximumPointCount,
      Self.hasStrictlyIncreasingReferences(points),
      AmbientLuxLinearFit(points: points) != nil
    else { return nil }
    self.points = points
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case points
    case rawReference
    case luxReference
    case capturedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let calibration: Self?
    if container.contains(.points) {
      let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      guard schemaVersion == 2 else {
        throw DecodingError.dataCorruptedError(
          forKey: .schemaVersion,
          in: container,
          debugDescription: "Unsupported ambient-light calibration schema."
        )
      }
      calibration = Self(
        points: try container.decode([AmbientLuxCalibrationPoint].self, forKey: .points)
      )
    } else {
      calibration = Self(
        rawReference: try container.decode(Double.self, forKey: .rawReference),
        luxReference: try container.decode(Double.self, forKey: .luxReference),
        capturedAt: try container.decode(Date.self, forKey: .capturedAt)
      )
    }
    guard let calibration else {
      throw DecodingError.dataCorruptedError(
        forKey: container.contains(.points) ? .points : .rawReference,
        in: container,
        debugDescription:
          "Ambient-light calibration must contain one to eight finite, positive, strictly monotonic points."
      )
    }
    self = calibration
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(2, forKey: .schemaVersion)
    try container.encode(points, forKey: .points)
  }

  public func addingPoint(
    rawReference: Double,
    luxReference: Double,
    capturedAt: Date = .now
  ) -> Self? {
    guard
      let point = AmbientLuxCalibrationPoint(
        rawReference: rawReference,
        luxReference: luxReference,
        capturedAt: capturedAt
      )
    else { return nil }
    var updatedPoints = points.filter { $0.rawReference != rawReference }
    updatedPoints.append(point)
    guard updatedPoints.count <= Self.maximumPointCount else { return nil }
    return Self(points: updatedPoints)
  }

  public func removingLastPoint() -> Self? {
    Self(points: Array(points.dropLast()))
  }

  public func estimatedLux(for rawValue: Double) -> Double? {
    fit?.estimate(rawValue: rawValue)
  }

  public func estimatedChannel(for rawValue: Double) -> SensorChannel? {
    guard let estimate = estimatedLux(for: rawValue) else { return nil }
    let note =
      pointCount == 1
      ? "Single-point user calibration; not calibrated or certified by Apple."
      : "\(pointCount)-point user linear fit; RMSE \(SensorFormatting.decimal(rootMeanSquareError, fractionDigits: 1)) lux; not calibrated or certified by Apple."
    return SensorChannel(
      id: "ambient_estimated_lux",
      label: "Estimated illuminance",
      value: estimate,
      formattedValue: SensorFormatting.decimal(estimate, fractionDigits: 1),
      unit: "lux",
      kind: .estimated,
      note: note
    )
  }

  private var fit: AmbientLuxLinearFit? {
    AmbientLuxLinearFit(points: points)
  }

  private static func hasStrictlyIncreasingReferences(
    _ points: [AmbientLuxCalibrationPoint]
  ) -> Bool {
    let sorted = points.sorted { $0.rawReference < $1.rawReference }
    for pair in zip(sorted, sorted.dropFirst()) {
      guard pair.0.rawReference < pair.1.rawReference,
        pair.0.luxReference < pair.1.luxReference
      else { return false }
    }
    return true
  }
}

private struct AmbientLuxLinearFit {
  let rawScale: Double
  let luxScale: Double
  let normalizedRawMean: Double
  let normalizedLuxMean: Double
  let normalizedSlope: Double
  let slope: Double
  let rootMeanSquareError: Double

  init?(points: [AmbientLuxCalibrationPoint]) {
    guard let rawScale = points.map(\.rawReference).max(), rawScale.isFinite, rawScale > 0,
      let luxScale = points.map(\.luxReference).max(), luxScale.isFinite, luxScale > 0
    else { return nil }
    let normalized = points.map {
      (raw: $0.rawReference / rawScale, lux: $0.luxReference / luxScale)
    }
    guard normalized.allSatisfy({ $0.raw.isFinite && $0.lux.isFinite }) else { return nil }

    let rawMean = normalized.map(\.raw).reduce(0, +) / Double(normalized.count)
    let luxMean = normalized.map(\.lux).reduce(0, +) / Double(normalized.count)
    let normalizedSlope: Double
    if normalized.count == 1 {
      normalizedSlope = 1
    } else {
      let covariance = normalized.reduce(0) {
        $0 + ($1.raw - rawMean) * ($1.lux - luxMean)
      }
      let variance = normalized.reduce(0) {
        $0 + ($1.raw - rawMean) * ($1.raw - rawMean)
      }
      guard covariance.isFinite, variance.isFinite, variance > 0 else { return nil }
      normalizedSlope = covariance / variance
    }

    let slope = normalizedSlope * (luxScale / rawScale)
    guard rawMean.isFinite, luxMean.isFinite,
      normalizedSlope.isFinite, normalizedSlope > 0,
      slope.isFinite, slope > 0
    else { return nil }

    var normalizedSquaredError = 0.0
    for point in normalized {
      let prediction = luxMean + normalizedSlope * (point.raw - rawMean)
      let residual = point.lux - prediction
      normalizedSquaredError += residual * residual
      guard normalizedSquaredError.isFinite else { return nil }
    }
    let normalizedRMSE = sqrt(normalizedSquaredError / Double(normalized.count))
    let rootMeanSquareError = normalizedRMSE * luxScale
    guard rootMeanSquareError.isFinite else { return nil }

    self.rawScale = rawScale
    self.luxScale = luxScale
    self.normalizedRawMean = rawMean
    self.normalizedLuxMean = luxMean
    self.normalizedSlope = normalizedSlope
    self.slope = slope
    self.rootMeanSquareError = rootMeanSquareError
  }

  func estimate(rawValue: Double) -> Double? {
    guard rawValue.isFinite, rawValue >= 0 else { return nil }
    let normalizedRaw = rawValue / rawScale
    let normalizedEstimate =
      normalizedLuxMean + normalizedSlope * (normalizedRaw - normalizedRawMean)
    let estimate = normalizedEstimate * luxScale
    guard normalizedRaw.isFinite, normalizedEstimate.isFinite, estimate.isFinite else { return nil }
    return max(estimate, 0)
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
