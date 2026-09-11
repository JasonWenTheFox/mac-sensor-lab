import Foundation

struct CameraFrameAnalysis: Equatable, Sendable {
  let sampledPixelCount: Int
  let meanRelativeLuma: Double
  let minimumRelativeLuma: Double
  let maximumRelativeLuma: Double

  var sampledContrastSpan: Double {
    maximumRelativeLuma - minimumRelativeLuma
  }
}

enum CameraFrameAnalyzer {
  static let maximumDimension = 8_192
  static let maximumBytesPerRow = 65_536
  static let maximumBufferByteCount = 512 * 1_024 * 1_024
  static let maximumSampledPixelCount = 4_096

  static func analyzeBGRA(
    width: Int,
    height: Int,
    bytesPerRow: Int,
    bytes: [UInt8]
  ) -> CameraFrameAnalysis? {
    analyzeBGRA(
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      byteCount: bytes.count,
      byteAt: { bytes[$0] }
    )
  }

  static func analyzeBGRA(
    width: Int,
    height: Int,
    bytesPerRow: Int,
    byteCount: Int,
    byteAt: (Int) -> UInt8
  ) -> CameraFrameAnalysis? {
    guard (1...maximumDimension).contains(width),
      (1...maximumDimension).contains(height),
      bytesPerRow > 0,
      bytesPerRow <= maximumBytesPerRow,
      byteCount > 0,
      byteCount <= maximumBufferByteCount
    else { return nil }

    let (minimumRowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 4)
    let (minimumBufferBytes, bufferOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
    guard !rowOverflow, !bufferOverflow,
      bytesPerRow >= minimumRowBytes,
      byteCount >= minimumBufferBytes
    else { return nil }

    let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    guard !pixelOverflow, pixelCount > 0 else { return nil }
    let samplingStride = max(
      1,
      Int(ceil(sqrt(Double(pixelCount) / Double(maximumSampledPixelCount))))
    )

    var sampledPixelCount = 0
    var lumaSum = 0.0
    var minimumLuma = Double.infinity
    var maximumLuma = -Double.infinity

    var y = samplingStride / 2
    while y < height {
      var x = samplingStride / 2
      while x < width {
        guard sampledPixelCount < maximumSampledPixelCount else { break }
        let offset = y * bytesPerRow + x * 4
        guard offset >= 0, offset + 2 < byteCount else { return nil }
        let blue = Double(byteAt(offset))
        let green = Double(byteAt(offset + 1))
        let red = Double(byteAt(offset + 2))
        let relativeLuma = (0.0722 * blue + 0.7152 * green + 0.2126 * red) / 255
        guard relativeLuma.isFinite, (0...1).contains(relativeLuma) else { return nil }
        lumaSum += relativeLuma
        minimumLuma = min(minimumLuma, relativeLuma)
        maximumLuma = max(maximumLuma, relativeLuma)
        sampledPixelCount += 1
        x += samplingStride
      }
      y += samplingStride
    }

    guard sampledPixelCount > 0 else { return nil }
    let calculatedMean = lumaSum / Double(sampledPixelCount)
    let roundingTolerance = 1e-12
    guard calculatedMean.isFinite,
      minimumLuma.isFinite,
      maximumLuma.isFinite,
      minimumLuma <= calculatedMean + roundingTolerance,
      calculatedMean <= maximumLuma + roundingTolerance
    else { return nil }
    let mean = min(max(calculatedMean, minimumLuma), maximumLuma)

    return CameraFrameAnalysis(
      sampledPixelCount: sampledPixelCount,
      meanRelativeLuma: mean,
      minimumRelativeLuma: minimumLuma,
      maximumRelativeLuma: maximumLuma
    )
  }
}

struct CameraFrameObservation: Equatable, Sendable {
  static let maximumFrameCount: UInt64 = 100_000

  let deliveredFrameCount: UInt64
  let droppedFrameCount: UInt64
  let observationUptimeSeconds: Double
  let width: Int
  let height: Int
  let analysis: CameraFrameAnalysis

  init?(
    deliveredFrameCount: UInt64,
    droppedFrameCount: UInt64,
    observationUptimeSeconds: Double,
    width: Int,
    height: Int,
    analysis: CameraFrameAnalysis
  ) {
    guard (1...Self.maximumFrameCount).contains(deliveredFrameCount),
      droppedFrameCount <= Self.maximumFrameCount,
      observationUptimeSeconds.isFinite,
      observationUptimeSeconds >= 0,
      (1...CameraFrameAnalyzer.maximumDimension).contains(width),
      (1...CameraFrameAnalyzer.maximumDimension).contains(height),
      (1...CameraFrameAnalyzer.maximumSampledPixelCount).contains(analysis.sampledPixelCount),
      (0...1).contains(analysis.minimumRelativeLuma),
      (0...1).contains(analysis.meanRelativeLuma),
      (0...1).contains(analysis.maximumRelativeLuma),
      analysis.minimumRelativeLuma <= analysis.meanRelativeLuma,
      analysis.meanRelativeLuma <= analysis.maximumRelativeLuma
    else { return nil }
    self.deliveredFrameCount = deliveredFrameCount
    self.droppedFrameCount = droppedFrameCount
    self.observationUptimeSeconds = observationUptimeSeconds
    self.width = width
    self.height = height
    self.analysis = analysis
  }
}
