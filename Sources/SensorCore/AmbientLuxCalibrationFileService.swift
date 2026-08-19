import Foundation

public enum AmbientLuxCalibrationFileError: LocalizedError, Equatable {
  case invalidSource
  case fileTooLarge(maximumBytes: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidSource:
      "The calibration source must be a local file."
    case .fileTooLarge(let maximumBytes):
      "The calibration file exceeds the \(SensorFormatting.bytes(UInt64(maximumBytes))) safety limit."
    }
  }
}

public enum AmbientLuxCalibrationFileService {
  public static let maximumByteCount = 64 * 1_024

  public static func data(for calibration: AmbientLuxCalibration) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(calibration)
  }

  public static func calibration(from data: Data) throws -> AmbientLuxCalibration {
    guard data.count <= maximumByteCount else {
      throw AmbientLuxCalibrationFileError.fileTooLarge(maximumBytes: maximumByteCount)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(AmbientLuxCalibration.self, from: data)
  }

  public static func read(from url: URL) throws -> AmbientLuxCalibration {
    guard url.isFileURL else { throw AmbientLuxCalibrationFileError.invalidSource }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumByteCount + 1) ?? Data()
    return try calibration(from: data)
  }
}
