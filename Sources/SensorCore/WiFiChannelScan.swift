@preconcurrency import CoreWLAN
import Foundation

public enum WiFiChannelBand: Int, CaseIterable, Equatable, Sendable {
  case band2GHz = 1
  case band5GHz = 2
  case band6GHz = 3

  init?(coreWLANRawValue: Int) {
    self.init(rawValue: coreWLANRawValue)
  }

  public var displayName: String {
    switch self {
    case .band2GHz: "2.4 GHz"
    case .band5GHz: "5 GHz"
    case .band6GHz: "6 GHz"
    }
  }
}

public struct WiFiChannelScanSummary: Equatable, Identifiable, Sendable {
  public var id: String { "\(band.rawValue)-\(channelNumber)" }

  public let band: WiFiChannelBand
  public let channelNumber: Int
  public let reportedRecordCount: Int
  public let strongestRSSIDBm: Int?
  public let averageRSSIDBm: Double?
  public let reportedChannelWidthsMHz: [Int]

  public init(
    band: WiFiChannelBand,
    channelNumber: Int,
    reportedRecordCount: Int,
    strongestRSSIDBm: Int?,
    averageRSSIDBm: Double?,
    reportedChannelWidthsMHz: [Int]
  ) {
    self.band = band
    self.channelNumber = channelNumber
    self.reportedRecordCount = reportedRecordCount
    self.strongestRSSIDBm = strongestRSSIDBm
    self.averageRSSIDBm = averageRSSIDBm
    self.reportedChannelWidthsMHz = reportedChannelWidthsMHz
  }
}

public struct WiFiChannelScanResult: Equatable, Sendable {
  public let completedAt: Date
  public let reportedRecordCount: Int
  public let acceptedRecordCount: Int
  public let discardedRecordCount: Int
  public let truncatedRecordCount: Int
  public let channels: [WiFiChannelScanSummary]

  public init(
    completedAt: Date,
    reportedRecordCount: Int,
    acceptedRecordCount: Int,
    discardedRecordCount: Int,
    truncatedRecordCount: Int,
    channels: [WiFiChannelScanSummary]
  ) {
    self.completedAt = completedAt
    self.reportedRecordCount = reportedRecordCount
    self.acceptedRecordCount = acceptedRecordCount
    self.discardedRecordCount = discardedRecordCount
    self.truncatedRecordCount = truncatedRecordCount
    self.channels = channels
  }
}

public enum WiFiChannelScanFailure: Equatable, Sendable {
  case interfaceUnavailable
  case wifiOffOrUnavailable
  case serviceInactiveOrUnavailable
  case operationNotPermitted
  case systemTimeout
  case unsupported
  case failed
}

public enum WiFiChannelScanOutcome: Equatable, Sendable {
  case success(WiFiChannelScanResult)
  case failure(WiFiChannelScanFailure)
}

struct WiFiChannelScanReading: Equatable, Sendable {
  let channelNumber: Int
  let channelWidthRawValue: Int
  let channelBandRawValue: Int
  let rssiDBm: Int
}

enum WiFiChannelScanReducer {
  static let maximumProcessedRecordCount = 512

  private struct Key: Hashable {
    let band: WiFiChannelBand
    let channelNumber: Int
  }

  private struct Accumulator {
    var recordCount = 0
    var rssiTotal = 0
    var rssiCount = 0
    var strongestRSSIDBm: Int?
    var widthsMHz: Set<Int> = []
  }

  static func reduce(
    _ readings: [WiFiChannelScanReading],
    reportedRecordCount: Int? = nil,
    completedAt: Date = Date()
  ) -> WiFiChannelScanResult {
    let totalCount = max(readings.count, reportedRecordCount ?? readings.count)
    let processedReadings = readings.prefix(maximumProcessedRecordCount)
    var discardedRecordCount = 0
    var accumulators: [Key: Accumulator] = [:]

    for reading in processedReadings {
      guard
        (1...1_000).contains(reading.channelNumber),
        let band = WiFiChannelBand(coreWLANRawValue: reading.channelBandRawValue)
      else {
        discardedRecordCount += 1
        continue
      }

      let key = Key(band: band, channelNumber: reading.channelNumber)
      var accumulator = accumulators[key, default: Accumulator()]
      accumulator.recordCount += 1

      if (-120 ... -1).contains(reading.rssiDBm) {
        accumulator.rssiTotal += reading.rssiDBm
        accumulator.rssiCount += 1
        accumulator.strongestRSSIDBm = max(
          accumulator.strongestRSSIDBm ?? reading.rssiDBm,
          reading.rssiDBm
        )
      }

      if let width = WiFiChannelWidth(coreWLANRawValue: reading.channelWidthRawValue) {
        accumulator.widthsMHz.insert(width.rawValue)
      }
      accumulators[key] = accumulator
    }

    let channels = accumulators.map { key, accumulator in
      WiFiChannelScanSummary(
        band: key.band,
        channelNumber: key.channelNumber,
        reportedRecordCount: accumulator.recordCount,
        strongestRSSIDBm: accumulator.strongestRSSIDBm,
        averageRSSIDBm: accumulator.rssiCount > 0
          ? Double(accumulator.rssiTotal) / Double(accumulator.rssiCount) : nil,
        reportedChannelWidthsMHz: accumulator.widthsMHz.sorted()
      )
    }
    .sorted {
      ($0.band.rawValue, $0.channelNumber) < ($1.band.rawValue, $1.channelNumber)
    }

    let processedCount = processedReadings.count
    return WiFiChannelScanResult(
      completedAt: completedAt,
      reportedRecordCount: totalCount,
      acceptedRecordCount: processedCount - discardedRecordCount,
      discardedRecordCount: discardedRecordCount,
      truncatedRecordCount: max(0, totalCount - processedCount),
      channels: channels
    )
  }
}

public enum WiFiChannelScanner {
  public static func scan() async -> WiFiChannelScanOutcome {
    await Task.detached(priority: .userInitiated) {
      guard let interface = CWWiFiClient.shared().interface() else {
        return .failure(.interfaceUnavailable)
      }
      guard interface.powerOn() else {
        return .failure(.wifiOffOrUnavailable)
      }
      guard interface.serviceActive() else {
        return .failure(.serviceInactiveOrUnavailable)
      }

      do {
        let networks = try interface.scanForNetworks(withName: nil, includeHidden: false)
        let readings = networks.prefix(WiFiChannelScanReducer.maximumProcessedRecordCount).map {
          network -> WiFiChannelScanReading in
          let channel = network.wlanChannel
          return WiFiChannelScanReading(
            channelNumber: channel?.channelNumber ?? 0,
            channelWidthRawValue: channel?.channelWidth.rawValue ?? 0,
            channelBandRawValue: channel?.channelBand.rawValue ?? 0,
            rssiDBm: network.rssiValue
          )
        }
        return .success(
          WiFiChannelScanReducer.reduce(
            readings,
            reportedRecordCount: networks.count
          )
        )
      } catch {
        return .failure(classify(error))
      }
    }.value
  }

  static func classify(_ error: Error) -> WiFiChannelScanFailure {
    let error = error as NSError
    guard error.domain == CWErrorDomain else { return .failed }
    switch error.code {
    case CWErr.cwOperationNotPermittedErr.rawValue:
      return .operationNotPermitted
    case CWErr.cwTimeoutErr.rawValue:
      return .systemTimeout
    case CWErr.cwNotSupportedErr.rawValue:
      return .unsupported
    case CWErr.cwReferenceNotBoundErr.rawValue:
      return .interfaceUnavailable
    default:
      return .failed
    }
  }
}
