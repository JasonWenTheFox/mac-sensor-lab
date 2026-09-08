import AppKit
import CoreGraphics
import Foundation

public struct DisplayCalibrationModeSignature: Equatable, Hashable, Sendable {
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let pointWidth: Int
  public let pointHeight: Int
  public let rotationDegrees: Int

  public init?(
    pixelWidth: Int,
    pixelHeight: Int,
    pointWidth: Int,
    pointHeight: Int,
    rotationDegrees: Int
  ) {
    guard (1...100_000).contains(pixelWidth),
      (1...100_000).contains(pixelHeight),
      (1...100_000).contains(pointWidth),
      (1...100_000).contains(pointHeight),
      [0, 90, 180, 270].contains(rotationDegrees)
    else {
      return nil
    }

    let horizontalScale = Double(pixelWidth) / Double(pointWidth)
    let verticalScale = Double(pixelHeight) / Double(pointHeight)
    guard horizontalScale.isFinite,
      verticalScale.isFinite,
      (0.25...8).contains(horizontalScale),
      (0.25...8).contains(verticalScale)
    else {
      return nil
    }

    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.pointWidth = pointWidth
    self.pointHeight = pointHeight
    self.rotationDegrees = rotationDegrees
  }

  public var horizontalBackingPixelsPerPoint: Double {
    Double(pixelWidth) / Double(pointWidth)
  }

  static func currentAxes(
    pixelWidth: Int,
    pixelHeight: Int,
    pointWidth: Int,
    pointHeight: Int,
    rotationDegrees: Int
  ) -> DisplayCalibrationModeSignature? {
    switch rotationDegrees {
    case 0, 180:
      return DisplayCalibrationModeSignature(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        pointWidth: pointWidth,
        pointHeight: pointHeight,
        rotationDegrees: rotationDegrees
      )
    case 90, 270:
      return DisplayCalibrationModeSignature(
        pixelWidth: pixelHeight,
        pixelHeight: pixelWidth,
        pointWidth: pointHeight,
        pointHeight: pointWidth,
        rotationDegrees: rotationDegrees
      )
    default:
      return nil
    }
  }
}

public struct DisplayCalibrationContext: Equatable, Hashable, Sendable {
  public let slotIndex: Int
  public let topologyGeneration: UInt64
  public let modeRevision: UInt64
  public let mode: DisplayCalibrationModeSignature
}

public struct DisplayCalibrationMeasurement: Equatable, Sendable {
  public let referenceMillimeters: Double
  public let renderedPoints: Double
  public let millimetersPerPoint: Double
  public let logicalPointsPerInch: Double
  public let horizontalPixelsPerInch: Double
  public let physicalWidthMillimeters: Double

  init?(
    referenceMillimeters: Double,
    renderedPoints: Double,
    mode: DisplayCalibrationModeSignature
  ) {
    guard referenceMillimeters.isFinite,
      renderedPoints.isFinite,
      (10...2_000).contains(referenceMillimeters),
      (20...20_000).contains(renderedPoints)
    else {
      return nil
    }

    let millimetersPerPoint = referenceMillimeters / renderedPoints
    let logicalPointsPerInch = 25.4 / millimetersPerPoint
    let horizontalPixelsPerInch = logicalPointsPerInch * mode.horizontalBackingPixelsPerPoint
    let physicalWidthMillimeters = Double(mode.pointWidth) * millimetersPerPoint

    guard millimetersPerPoint.isFinite,
      logicalPointsPerInch.isFinite,
      horizontalPixelsPerInch.isFinite,
      physicalWidthMillimeters.isFinite,
      (0.01...10).contains(millimetersPerPoint),
      (10...2_000).contains(horizontalPixelsPerInch),
      physicalWidthMillimeters > 0
    else {
      return nil
    }

    self.referenceMillimeters = referenceMillimeters
    self.renderedPoints = renderedPoints
    self.millimetersPerPoint = millimetersPerPoint
    self.logicalPointsPerInch = logicalPointsPerInch
    self.horizontalPixelsPerInch = horizontalPixelsPerInch
    self.physicalWidthMillimeters = physicalWidthMillimeters
  }
}

public struct DisplayCalibrationSystemEstimate: Equatable, Sendable {
  public let horizontalSpanMillimeters: Double
  public let horizontalPixelsPerInch: Double

  init?(horizontalSpanMillimeters: Double, horizontalPixelWidth: Int) {
    guard horizontalSpanMillimeters.isFinite,
      (10...10_000).contains(horizontalSpanMillimeters),
      (1...100_000).contains(horizontalPixelWidth)
    else {
      return nil
    }

    let horizontalPixelsPerInch =
      Double(horizontalPixelWidth) * 25.4 / horizontalSpanMillimeters
    guard horizontalPixelsPerInch.isFinite,
      (10...2_000).contains(horizontalPixelsPerInch)
    else {
      return nil
    }

    self.horizontalSpanMillimeters = horizontalSpanMillimeters
    self.horizontalPixelsPerInch = horizontalPixelsPerInch
  }

  static func currentHorizontalAxis(
    physicalWidthMillimeters: Double,
    physicalHeightMillimeters: Double,
    mode: DisplayCalibrationModeSignature
  ) -> DisplayCalibrationSystemEstimate? {
    let horizontalSpan =
      mode.rotationDegrees == 90 || mode.rotationDegrees == 270
      ? physicalHeightMillimeters : physicalWidthMillimeters
    return DisplayCalibrationSystemEstimate(
      horizontalSpanMillimeters: horizontalSpan,
      horizontalPixelWidth: mode.pixelWidth
    )
  }
}

public struct DisplayCalibrationSlotState: Equatable, Sendable {
  public let context: DisplayCalibrationContext
  public let horizontalCalibration: DisplayCalibrationMeasurement?
}

struct DisplayCalibrationDisplayIdentity: Equatable, Hashable, Sendable {
  let rawValue: CGDirectDisplayID
}

struct DisplayCalibrationObservation: Equatable, Sendable {
  let identity: DisplayCalibrationDisplayIdentity
  let mode: DisplayCalibrationModeSignature
  let systemEstimate: DisplayCalibrationSystemEstimate?

  init(
    identity: DisplayCalibrationDisplayIdentity,
    mode: DisplayCalibrationModeSignature,
    systemEstimate: DisplayCalibrationSystemEstimate? = nil
  ) {
    self.identity = identity
    self.mode = mode
    self.systemEstimate = systemEstimate
  }
}

enum DisplayCalibrationSynchronizationResult: Equatable {
  case unchanged
  case topologyChanged
  case modeChanged(slotIndices: [Int])
  case invalidated
}

@MainActor
public final class DisplayCalibrationSession {
  private struct Record {
    let identity: DisplayCalibrationDisplayIdentity
    var mode: DisplayCalibrationModeSignature
    var modeRevision: UInt64
    var systemEstimate: DisplayCalibrationSystemEstimate?
    var horizontalCalibration: DisplayCalibrationMeasurement?
  }

  public private(set) var topologyGeneration: UInt64 = 0
  private var records: [Record] = []

  public init() {}

  public var slots: [DisplayCalibrationSlotState] {
    records.indices.map { index in
      slotState(at: index)
    }
  }

  @discardableResult
  public func refreshFromSystem() -> Bool {
    guard let observations = SystemDisplayCalibrationReader.observations() else {
      _ = synchronize(observations: [])
      return false
    }

    _ = synchronize(observations: observations)
    return !records.isEmpty
  }

  public func context(forSlotIndex slotIndex: Int) -> DisplayCalibrationContext? {
    guard slotIndex > 0, records.indices.contains(slotIndex - 1) else {
      return nil
    }

    return makeContext(at: slotIndex - 1)
  }

  public func context(for screen: NSScreen) -> DisplayCalibrationContext? {
    guard
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber,
      let rawValue = CGDirectDisplayID(number.stringValue),
      let index = records.firstIndex(where: { $0.identity.rawValue == rawValue })
    else {
      return nil
    }

    return makeContext(at: index)
  }

  @discardableResult
  public func calibrateHorizontal(
    context: DisplayCalibrationContext,
    referenceMillimeters: Double,
    renderedPoints: Double
  ) -> DisplayCalibrationMeasurement? {
    guard let index = validatedIndex(for: context),
      let measurement = DisplayCalibrationMeasurement(
        referenceMillimeters: referenceMillimeters,
        renderedPoints: renderedPoints,
        mode: records[index].mode
      )
    else {
      return nil
    }

    records[index].horizontalCalibration = measurement
    return measurement
  }

  public func calibration(
    for context: DisplayCalibrationContext
  ) -> DisplayCalibrationMeasurement? {
    guard let index = validatedIndex(for: context) else {
      return nil
    }

    return records[index].horizontalCalibration
  }

  public func systemEstimate(
    for context: DisplayCalibrationContext
  ) -> DisplayCalibrationSystemEstimate? {
    guard let index = validatedIndex(for: context) else {
      return nil
    }

    return records[index].systemEstimate
  }

  @discardableResult
  public func clearCalibration(for context: DisplayCalibrationContext) -> Bool {
    guard let index = validatedIndex(for: context) else {
      return false
    }

    records[index].horizontalCalibration = nil
    return true
  }

  public func clearAllCalibrations() {
    for index in records.indices {
      records[index].horizontalCalibration = nil
    }
  }

  @discardableResult
  func synchronize(
    observations: [DisplayCalibrationObservation]
  ) -> DisplayCalibrationSynchronizationResult {
    guard observations.count <= 16,
      observations.allSatisfy({ $0.identity.rawValue != 0 }),
      Set(observations.map(\.identity)).count == observations.count
    else {
      invalidateAllRecords()
      return .invalidated
    }

    let observedIdentities = observations.map(\.identity)
    let recordedIdentities = records.map(\.identity)
    guard observedIdentities == recordedIdentities else {
      topologyGeneration = nextRevision(after: topologyGeneration)
      records = observations.map { observation in
        Record(
          identity: observation.identity,
          mode: observation.mode,
          modeRevision: 0,
          systemEstimate: observation.systemEstimate,
          horizontalCalibration: nil
        )
      }
      return .topologyChanged
    }

    var changedSlots: [Int] = []
    for index in records.indices {
      records[index].systemEstimate = observations[index].systemEstimate
      if records[index].mode != observations[index].mode {
        records[index].mode = observations[index].mode
        records[index].modeRevision = nextRevision(after: records[index].modeRevision)
        records[index].horizontalCalibration = nil
        changedSlots.append(index + 1)
      }
    }

    if changedSlots.isEmpty {
      return .unchanged
    }

    return .modeChanged(slotIndices: changedSlots)
  }

  private func validatedIndex(for context: DisplayCalibrationContext) -> Int? {
    let index = context.slotIndex - 1
    guard records.indices.contains(index),
      context.topologyGeneration == topologyGeneration,
      context.modeRevision == records[index].modeRevision,
      context.mode == records[index].mode
    else {
      return nil
    }

    return index
  }

  private func makeContext(at index: Int) -> DisplayCalibrationContext {
    DisplayCalibrationContext(
      slotIndex: index + 1,
      topologyGeneration: topologyGeneration,
      modeRevision: records[index].modeRevision,
      mode: records[index].mode
    )
  }

  private func slotState(at index: Int) -> DisplayCalibrationSlotState {
    DisplayCalibrationSlotState(
      context: makeContext(at: index),
      horizontalCalibration: records[index].horizontalCalibration
    )
  }

  private func invalidateAllRecords() {
    topologyGeneration = nextRevision(after: topologyGeneration)
    records = []
  }

  private func nextRevision(after value: UInt64) -> UInt64 {
    value == .max ? 1 : value + 1
  }
}

@MainActor
private enum SystemDisplayCalibrationReader {
  static func observations() -> [DisplayCalibrationObservation]? {
    let maximumDisplayCount: UInt32 = 16
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
      displayCount > 0,
      displayCount <= maximumDisplayCount
    else {
      return nil
    }

    var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
    var actualDisplayCount: UInt32 = 0
    guard CGGetActiveDisplayList(displayCount, &displayIDs, &actualDisplayCount) == .success,
      actualDisplayCount == displayCount
    else {
      return nil
    }
    displayIDs = Array(displayIDs.prefix(Int(actualDisplayCount)))

    let mainDisplayID = CGMainDisplayID()
    let activeDisplayIDs = Array(displayIDs.prefix(Int(displayCount))).sorted { lhs, rhs in
      if lhs == mainDisplayID {
        return rhs != mainDisplayID
      }
      if rhs == mainDisplayID {
        return false
      }

      let lhsBounds = CGDisplayBounds(lhs)
      let rhsBounds = CGDisplayBounds(rhs)
      let lhsPosition = (lhsBounds.minX, lhsBounds.minY, lhsBounds.width, lhsBounds.height)
      let rhsPosition = (rhsBounds.minX, rhsBounds.minY, rhsBounds.width, rhsBounds.height)
      if lhsPosition != rhsPosition {
        return lhsPosition < rhsPosition
      }
      return lhs < rhs
    }

    var observations: [DisplayCalibrationObservation] = []
    observations.reserveCapacity(activeDisplayIDs.count)
    for displayID in activeDisplayIDs {
      guard displayID != 0,
        let mode = CGDisplayCopyDisplayMode(displayID),
        let rotationDegrees = normalizedRotation(CGDisplayRotation(displayID)),
        let signature = DisplayCalibrationModeSignature.currentAxes(
          pixelWidth: mode.pixelWidth,
          pixelHeight: mode.pixelHeight,
          pointWidth: mode.width,
          pointHeight: mode.height,
          rotationDegrees: rotationDegrees
        )
      else {
        return nil
      }

      observations.append(
        DisplayCalibrationObservation(
          identity: DisplayCalibrationDisplayIdentity(rawValue: displayID),
          mode: signature,
          systemEstimate: systemEstimate(displayID: displayID, mode: signature)
        )
      )
    }

    return observations
  }

  private static func systemEstimate(
    displayID: CGDirectDisplayID,
    mode: DisplayCalibrationModeSignature
  ) -> DisplayCalibrationSystemEstimate? {
    let size = CGDisplayScreenSize(displayID)
    return DisplayCalibrationSystemEstimate.currentHorizontalAxis(
      physicalWidthMillimeters: Double(size.width),
      physicalHeightMillimeters: Double(size.height),
      mode: mode
    )
  }

  private static func normalizedRotation(_ value: Double) -> Int? {
    guard value.isFinite else {
      return nil
    }

    let remainder = value.truncatingRemainder(dividingBy: 360)
    let normalized = remainder < 0 ? remainder + 360 : remainder
    for candidate in [0, 90, 180, 270, 360] {
      if abs(normalized - Double(candidate)) <= 0.01 {
        return candidate == 360 ? 0 : candidate
      }
    }
    return nil
  }
}
