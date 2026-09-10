import AVFAudio
import Accelerate
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
  let spectrum: MicrophoneSpectrumAnalysis?
}

struct MicrophoneSpectrumBin: Equatable, Identifiable, Sendable {
  let index: Int
  let lowerFrequencyHz: Double
  let upperFrequencyHz: Double
  let relativeMagnitudeDB: Double

  var id: Int { index }
  var centerFrequencyHz: Double { (lowerFrequencyHz + upperFrequencyHz) / 2 }
}

struct MicrophoneSpectrumAnalysis: Equatable, Sendable {
  let fftSize: Int
  let frequencyResolutionHz: Double
  let nyquistFrequencyHz: Double
  let bins: [MicrophoneSpectrumBin]
  let strongestBinCenterFrequencyHz: Double?
}

final class MicrophoneSpectrumAnalyzer: @unchecked Sendable {
  static let supportedFFTSizes = [256, 512, 1_024, 2_048]
  static let maximumDisplayBinCount = 128
  static let displayFloorDB = -80.0
  static let maximumSampleRate = 768_000.0

  private struct Configuration {
    let window: [Float]
    let transform: vDSP.DiscreteFourierTransform<Float>
  }

  private let configurations: [Int: Configuration]

  init() {
    var configurations: [Int: Configuration] = [:]
    for fftSize in Self.supportedFFTSizes {
      guard
        let transform = try? vDSP.DiscreteFourierTransform<Float>(
          count: fftSize,
          direction: .forward,
          transformType: .complexComplex,
          ofType: Float.self
        )
      else { continue }
      configurations[fftSize] = Configuration(
        window: vDSP.window(
          ofType: Float.self,
          usingSequence: .hanningDenormalized,
          count: fftSize,
          isHalfWindow: false
        ),
        transform: transform
      )
    }
    self.configurations = configurations
  }

  // A capture session owns one analyzer and invokes it only from its serialized tap callback.
  // Reusing the immutable window and DFT setup avoids rebuilding them for every audio buffer.
  func analyze(samples: [Float], sampleRate: Double) -> MicrophoneSpectrumAnalysis? {
    guard sampleRate.isFinite,
      (1...Self.maximumSampleRate).contains(sampleRate),
      samples.count <= MicrophonePCMAnalyzer.maximumFrameCount,
      let fftSize = Self.supportedFFTSizes.last(where: { $0 <= samples.count }),
      let configuration = configurations[fftSize]
    else { return nil }

    let recentSamples = samples.suffix(fftSize)
    var mean = 0.0
    for sample in recentSamples {
      guard sample.isFinite,
        abs(Double(sample)) <= MicrophonePCMAnalyzer.maximumAbsoluteSample
      else { return nil }
      mean += Double(sample)
    }
    mean /= Double(fftSize)
    guard mean.isFinite else { return nil }

    var windowedSamples = Array(repeating: Float.zero, count: fftSize)
    for (index, sample) in recentSamples.enumerated() {
      let centeredSample = Double(sample) - mean
      guard centeredSample.isFinite else { return nil }
      windowedSamples[index] = Float(centeredSample) * configuration.window[index]
    }

    let output = configuration.transform.transform(
      real: windowedSamples,
      imaginary: Array(repeating: 0, count: fftSize)
    )
    let positiveBinCount = fftSize / 2
    var magnitudes = Array(repeating: 0.0, count: positiveBinCount)
    var strongestOffset: Int?
    var strongestMagnitude = 0.0
    for offset in 0..<positiveBinCount {
      let fftBin = offset + 1
      let magnitude = hypot(Double(output.real[fftBin]), Double(output.imaginary[fftBin]))
      guard magnitude.isFinite, magnitude >= 0 else { return nil }
      magnitudes[offset] = magnitude
      if magnitude > strongestMagnitude {
        strongestMagnitude = magnitude
        strongestOffset = offset
      }
    }

    let resolution = sampleRate / Double(fftSize)
    let displayBinCount = min(Self.maximumDisplayBinCount, positiveBinCount)
    var bins: [MicrophoneSpectrumBin] = []
    bins.reserveCapacity(displayBinCount)
    for displayIndex in 0..<displayBinCount {
      let startOffset = displayIndex * positiveBinCount / displayBinCount
      let endOffset = ((displayIndex + 1) * positiveBinCount / displayBinCount) - 1
      guard startOffset <= endOffset else { return nil }
      let groupPeak = magnitudes[startOffset...endOffset].max() ?? 0
      let relativeMagnitudeDB: Double
      if strongestMagnitude > 0, groupPeak > 0 {
        relativeMagnitudeDB = max(
          Self.displayFloorDB,
          20 * log10(groupPeak / strongestMagnitude)
        )
      } else {
        relativeMagnitudeDB = Self.displayFloorDB
      }
      let firstFFTBin = startOffset + 1
      let lastFFTBin = endOffset + 1
      bins.append(
        MicrophoneSpectrumBin(
          index: displayIndex,
          lowerFrequencyHz: max(0, (Double(firstFFTBin) - 0.5) * resolution),
          upperFrequencyHz: min(
            sampleRate / 2,
            (Double(lastFFTBin) + 0.5) * resolution
          ),
          relativeMagnitudeDB: relativeMagnitudeDB
        )
      )
    }

    let strongestBinCenterFrequencyHz = strongestOffset.map {
      Double($0 + 1) * resolution
    }
    return MicrophoneSpectrumAnalysis(
      fftSize: fftSize,
      frequencyResolutionHz: resolution,
      nyquistFrequencyHz: sampleRate / 2,
      bins: bins,
      strongestBinCenterFrequencyHz: strongestBinCenterFrequencyHz
    )
  }
}

final class MicrophoneSpectrumCadence: @unchecked Sendable {
  static let minimumIntervalSeconds = 0.1

  private var accumulatedSeconds = MicrophoneSpectrumCadence.minimumIntervalSeconds

  // A capture session owns one cadence gate and calls it only from its audio callback.
  func shouldAnalyze(frameCount: Int, sampleRate: Double) -> Bool {
    guard frameCount > 0,
      frameCount <= MicrophonePCMAnalyzer.maximumFrameCount,
      sampleRate.isFinite,
      sampleRate > 0,
      sampleRate <= MicrophoneSpectrumAnalyzer.maximumSampleRate
    else { return false }

    accumulatedSeconds += Double(frameCount) / sampleRate
    guard accumulatedSeconds >= Self.minimumIntervalSeconds else { return false }
    accumulatedSeconds.formTruncatingRemainder(dividingBy: Self.minimumIntervalSeconds)
    return true
  }
}

enum MicrophonePCMAnalyzer {
  static let maximumWaveformBinCount = 128
  static let maximumFrameCount = 65_536
  static let maximumChannelCount = 64
  static let maximumAnalyzedSampleCount = 262_144
  static let maximumAbsoluteSample = 16.0

  static func analyze(
    channels: [[Float]],
    sampleRate: Double? = nil,
    spectrumAnalyzer: MicrophoneSpectrumAnalyzer? = nil
  ) -> MicrophonePCMAnalysis? {
    guard let firstChannel = channels.first else { return nil }
    let frameCount = firstChannel.count
    guard channels.allSatisfy({ $0.count == frameCount }) else { return nil }

    return analyze(
      frameCount: frameCount,
      channelCount: channels.count,
      stride: 1,
      sampleRate: sampleRate,
      spectrumAnalyzer: spectrumAnalyzer
    ) { channel, frame in
      channels[channel][frame]
    }
  }

  static func analyze(
    buffer: AVAudioPCMBuffer,
    spectrumAnalyzer: MicrophoneSpectrumAnalyzer? = nil
  ) -> MicrophonePCMAnalysis? {
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let stride = Int(buffer.stride)
    guard buffer.format.commonFormat == .pcmFormatFloat32,
      let channelData = buffer.floatChannelData
    else { return nil }

    return analyze(
      frameCount: frameCount,
      channelCount: channelCount,
      stride: stride,
      sampleRate: buffer.format.sampleRate,
      spectrumAnalyzer: spectrumAnalyzer
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
    sampleRate: Double?,
    spectrumAnalyzer: MicrophoneSpectrumAnalyzer?,
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
    let shouldAnalyzeSpectrum = sampleRate != nil && spectrumAnalyzer != nil
    var monoSamples: [Float] = []
    if shouldAnalyzeSpectrum {
      monoSamples.reserveCapacity(frameCount)
    }

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
      if shouldAnalyzeSpectrum {
        monoSamples.append(Float(monoSample))
      }
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

    let spectrum: MicrophoneSpectrumAnalysis?
    if let sampleRate, let spectrumAnalyzer {
      spectrum = spectrumAnalyzer.analyze(samples: monoSamples, sampleRate: sampleRate)
    } else {
      spectrum = nil
    }

    return MicrophonePCMAnalysis(
      waveform: waveform,
      rootMeanSquareAmplitude: rootMeanSquare,
      peakAmplitude: peak,
      rootMeanSquareDBFS: decibelsFullScale(forAmplitude: rootMeanSquare),
      peakDBFS: decibelsFullScale(forAmplitude: peak),
      spectrum: spectrum
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
