import AVFAudio
import Foundation

struct MicrophoneWaveformBin: Equatable, Identifiable, Sendable {
  let index: Int
  let minimum: Double
  let maximum: Double

  var id: Int { index }
}

struct MicrophonePCMAnalysis: Equatable, Sendable {
  let waveform: [MicrophoneWaveformBin]
  let rootMeanSquareAmplitude: Double
  let peakAmplitude: Double
  let rootMeanSquareDBFS: Double?
  let peakDBFS: Double?
}

enum MicrophonePCMAnalyzer {
  static let maximumWaveformBinCount = 128
  static let maximumFrameCount = 65_536
  static let maximumChannelCount = 64
  static let maximumAnalyzedSampleCount = 262_144
  static let maximumAbsoluteSample = 16.0

  static func analyze(channels: [[Float]]) -> MicrophonePCMAnalysis? {
    guard let firstChannel = channels.first else { return nil }
    let frameCount = firstChannel.count
    guard channels.allSatisfy({ $0.count == frameCount }) else { return nil }

    return analyze(
      frameCount: frameCount,
      channelCount: channels.count,
      stride: 1
    ) { channel, frame in
      channels[channel][frame]
    }
  }

  static func analyze(buffer: AVAudioPCMBuffer) -> MicrophonePCMAnalysis? {
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let stride = Int(buffer.stride)
    guard buffer.format.commonFormat == .pcmFormatFloat32,
      let channelData = buffer.floatChannelData
    else { return nil }

    return analyze(
      frameCount: frameCount,
      channelCount: channelCount,
      stride: stride
    ) { channel, frame in
      channelData[channel][frame * stride]
    }
  }

  static func decibelsFullScale(forAmplitude amplitude: Double) -> Double? {
    guard amplitude.isFinite,
      amplitude > 0,
      amplitude <= maximumAbsoluteSample
    else { return nil }
    let decibels = 20 * log10(amplitude)
    return decibels.isFinite ? decibels : nil
  }

  private static func analyze(
    frameCount: Int,
    channelCount: Int,
    stride: Int,
    sampleAt: (_ channel: Int, _ frame: Int) -> Float
  ) -> MicrophonePCMAnalysis? {
    guard (1...maximumFrameCount).contains(frameCount),
      (1...maximumChannelCount).contains(channelCount),
      stride == 1 || stride == channelCount
    else { return nil }

    let (sampleCount, sampleCountOverflow) = frameCount.multipliedReportingOverflow(
      by: channelCount
    )
    guard !sampleCountOverflow,
      sampleCount <= maximumAnalyzedSampleCount
    else { return nil }

    let binCount = min(frameCount, maximumWaveformBinCount)
    var minima = Array(repeating: Double.infinity, count: binCount)
    var maxima = Array(repeating: -Double.infinity, count: binCount)
    var squaredSum = 0.0
    var peak = 0.0

    for frame in 0..<frameCount {
      var monoSum = 0.0
      for channel in 0..<channelCount {
        let sample = Double(sampleAt(channel, frame))
        guard sample.isFinite, abs(sample) <= maximumAbsoluteSample else { return nil }
        monoSum += sample
        squaredSum += sample * sample
        peak = max(peak, abs(sample))
      }

      let monoSample = monoSum / Double(channelCount)
      guard monoSample.isFinite else { return nil }
      let binIndex = frame * binCount / frameCount
      minima[binIndex] = min(minima[binIndex], monoSample)
      maxima[binIndex] = max(maxima[binIndex], monoSample)
    }

    let calculatedRootMeanSquare = sqrt(squaredSum / Double(sampleCount))
    let roundingTolerance = 1e-12
    guard calculatedRootMeanSquare.isFinite,
      calculatedRootMeanSquare >= 0,
      calculatedRootMeanSquare <= peak + roundingTolerance
    else { return nil }
    let rootMeanSquare = min(calculatedRootMeanSquare, peak)

    var waveform: [MicrophoneWaveformBin] = []
    waveform.reserveCapacity(binCount)
    for index in 0..<binCount {
      guard minima[index].isFinite,
        maxima[index].isFinite,
        minima[index] <= maxima[index]
      else { return nil }
      waveform.append(
        MicrophoneWaveformBin(
          index: index,
          minimum: minima[index],
          maximum: maxima[index]
        )
      )
    }

    return MicrophonePCMAnalysis(
      waveform: waveform,
      rootMeanSquareAmplitude: rootMeanSquare,
      peakAmplitude: peak,
      rootMeanSquareDBFS: decibelsFullScale(forAmplitude: rootMeanSquare),
      peakDBFS: decibelsFullScale(forAmplitude: peak)
    )
  }
}

struct MicrophoneLevelPoint: Equatable, Identifiable, Sendable {
  static let displayFloorDBFS = -96.0

  let id: UInt64
  let elapsedSeconds: Double
  let rootMeanSquareDBFS: Double
  let peakDBFS: Double

  init?(id: UInt64, elapsedSeconds: Double, analysis: MicrophonePCMAnalysis) {
    guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { return nil }
    self.id = id
    self.elapsedSeconds = elapsedSeconds
    self.rootMeanSquareDBFS = max(
      analysis.rootMeanSquareDBFS ?? Self.displayFloorDBFS,
      Self.displayFloorDBFS
    )
    self.peakDBFS = max(
      analysis.peakDBFS ?? Self.displayFloorDBFS,
      Self.displayFloorDBFS
    )
  }
}
