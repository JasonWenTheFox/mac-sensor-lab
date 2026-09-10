@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public enum CameraInventoryReader {
  public static func read() async -> CameraInventoryOutcome {
    await Task.detached(priority: .userInitiated) {
      CameraInventoryAVFoundationSource.read()
    }.value
  }
}

private enum CameraInventoryAVFoundationSource {
  static func read() -> CameraInventoryOutcome {
    guard
      Bundle.main.object(forInfoDictionaryKey: "NSCameraUseContinuityCameraDeviceType") as? Bool
        == true
    else {
      return .failure(.continuityBoundaryMissing)
    }

    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .external],
      mediaType: .video,
      position: .unspecified
    )
    let devices = discovery.devices
    guard devices.count <= CameraInventoryReducer.maximumDeviceCount else {
      return .failure(.safetyLimitReached)
    }

    var rawDevices: [CameraInventoryRawDevice] = []
    rawDevices.reserveCapacity(devices.count)
    for (deviceIndex, device) in devices.enumerated() {
      let rawType: CameraInventoryRawDeviceType
      switch device.deviceType {
      case .builtInWideAngleCamera:
        rawType = .builtInWideAngle
      case .external:
        rawType = .external
      case .continuityCamera:
        rawType = .continuityCamera
      case .deskViewCamera:
        rawType = .deskViewCamera
      default:
        rawType = .unsupported
      }

      let formats = device.formats
      guard formats.count <= CameraInventoryReducer.maximumFormatCountPerDevice else {
        return .failure(.safetyLimitReached)
      }
      var rawFormats: [CameraInventoryRawFormat] = []
      rawFormats.reserveCapacity(formats.count)
      for (formatIndex, format) in formats.enumerated() {
        let ranges = format.videoSupportedFrameRateRanges
        let colorSpaces = format.supportedColorSpaces
        guard
          ranges.count <= CameraInventoryReducer.maximumFrameRateRangeCountPerFormat,
          colorSpaces.count <= CameraInventoryReducer.maximumColorSpaceCountPerFormat
        else {
          return .failure(.safetyLimitReached)
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        rawFormats.append(
          CameraInventoryRawFormat(
            sourceIndex: formatIndex,
            width: Int64(dimensions.width),
            height: Int64(dimensions.height),
            frameRateRanges: ranges.map {
              CameraInventoryRawFrameRateRange(
                minimum: $0.minFrameRate,
                maximum: $0.maxFrameRate
              )
            },
            autofocusSystemRawValue: format.autoFocusSystem.rawValue,
            colorSpaceRawValues: colorSpaces.map(\.rawValue)
          )
        )
      }
      rawDevices.append(
        CameraInventoryRawDevice(
          sourceIndex: deviceIndex,
          deviceType: rawType,
          positionRawValue: device.position.rawValue,
          transportRawValue: UInt32(bitPattern: device.transportType),
          formats: rawFormats
        )
      )
    }

    return CameraInventoryReducer.reduce(devices: rawDevices)
  }
}
