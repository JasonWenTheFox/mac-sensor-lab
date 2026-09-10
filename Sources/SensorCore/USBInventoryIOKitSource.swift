import CoreFoundation
import Foundation
import IOKit
import IOUSBHost

public enum USBInventoryReader {
  public static func read() async -> USBInventoryOutcome {
    await Task.detached(priority: .userInitiated) {
      USBInventoryIOKitSource.read()
    }.value
  }
}

private enum USBInventoryIOKitSource {
  private enum EnumerationResult {
    case success([io_service_t])
    case failure(USBInventoryFailure)
  }

  private enum ParentResult {
    case found(Int)
    case absent
    case depthExceeded
  }

  static func read() -> USBInventoryOutcome {
    let deviceServices: [io_service_t]
    switch enumerate(
      className: "IOUSBHostDevice",
      maximumCount: USBInventoryReducer.maximumDeviceCount
    ) {
    case .success(let services):
      deviceServices = services
    case .failure(let failure):
      return .failure(failure)
    }
    defer {
      for service in deviceServices { IOObjectRelease(service) }
    }

    let interfaceServices: [io_service_t]
    switch enumerate(
      className: "IOUSBHostInterface",
      maximumCount: USBInventoryReducer.maximumInterfaceCount
    ) {
    case .success(let services):
      interfaceServices = services
    case .failure(let failure):
      return .failure(failure)
    }
    defer {
      for service in interfaceServices { IOObjectRelease(service) }
    }

    var rawDevices: [USBInventoryRawDevice] = []
    rawDevices.reserveCapacity(deviceServices.count)
    for (index, service) in deviceServices.enumerated() {
      let parentIndex: Int?
      switch nearestDeviceParent(of: service, candidates: deviceServices) {
      case .found(let foundIndex):
        parentIndex = foundIndex
      case .absent:
        parentIndex = nil
      case .depthExceeded:
        return .failure(.invalidTopology)
      }
      rawDevices.append(
        USBInventoryRawDevice(
          sourceIndex: index,
          parentSourceIndex: parentIndex,
          vendorID: number(service, key: IOUSBHostMatchingPropertyKey.vendorID.rawValue),
          productID: number(service, key: IOUSBHostMatchingPropertyKey.productID.rawValue),
          deviceReleaseNumber: number(
            service,
            key: IOUSBHostMatchingPropertyKey.deviceReleaseNumber.rawValue
          ),
          deviceClass: number(
            service,
            key: IOUSBHostMatchingPropertyKey.deviceClass.rawValue
          ),
          deviceSubClass: number(
            service,
            key: IOUSBHostMatchingPropertyKey.deviceSubClass.rawValue
          ),
          deviceProtocol: number(
            service,
            key: IOUSBHostMatchingPropertyKey.deviceProtocol.rawValue
          ),
          currentConfiguration: number(
            service,
            key: IOUSBHostDevicePropertyKey.currentConfiguration.rawValue
          ),
          connectionSpeed: number(
            service,
            key: IOUSBHostMatchingPropertyKey.speed.rawValue
          )
        )
      )
    }

    var rawInterfaces: [USBInventoryRawInterface] = []
    rawInterfaces.reserveCapacity(interfaceServices.count)
    for (index, service) in interfaceServices.enumerated() {
      let parentIndex: Int?
      switch nearestDeviceParent(of: service, candidates: deviceServices) {
      case .found(let foundIndex):
        parentIndex = foundIndex
      case .absent:
        parentIndex = nil
      case .depthExceeded:
        return .failure(.invalidTopology)
      }
      rawInterfaces.append(
        USBInventoryRawInterface(
          sourceIndex: index,
          parentDeviceSourceIndex: parentIndex,
          interfaceNumber: number(
            service,
            key: IOUSBHostMatchingPropertyKey.interfaceNumber.rawValue
          ),
          interfaceClass: number(
            service,
            key: IOUSBHostMatchingPropertyKey.interfaceClass.rawValue
          ),
          interfaceSubClass: number(
            service,
            key: IOUSBHostMatchingPropertyKey.interfaceSubClass.rawValue
          ),
          interfaceProtocol: number(
            service,
            key: IOUSBHostMatchingPropertyKey.interfaceProtocol.rawValue
          ),
          alternateSetting: number(
            service,
            key: IOUSBHostInterfacePropertyKey.alternateSetting.rawValue
          )
        )
      )
    }

    return USBInventoryReducer.reduce(devices: rawDevices, interfaces: rawInterfaces)
  }

  private static func enumerate(className: String, maximumCount: Int) -> EnumerationResult {
    guard let matching = IOServiceMatching(className) else {
      return .failure(.enumerationUnavailable)
    }
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard result == kIOReturnSuccess else {
      return .failure(classify(result))
    }
    defer { IOObjectRelease(iterator) }

    var services: [io_service_t] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
      guard services.count < maximumCount else {
        IOObjectRelease(service)
        for retainedService in services { IOObjectRelease(retainedService) }
        return .failure(.safetyLimitReached)
      }
      services.append(service)
      service = IOIteratorNext(iterator)
    }
    return .success(services)
  }

  private static func nearestDeviceParent(
    of entry: io_registry_entry_t,
    candidates: [io_service_t]
  ) -> ParentResult {
    var current = entry
    var ownsCurrent = false
    defer {
      if ownsCurrent { IOObjectRelease(current) }
    }

    for _ in 0..<USBInventoryReducer.maximumHierarchyDepth {
      var parent: io_registry_entry_t = 0
      let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
      if ownsCurrent {
        IOObjectRelease(current)
        ownsCurrent = false
      }
      guard result == kIOReturnSuccess, parent != 0 else {
        return .absent
      }
      current = parent
      ownsCurrent = true

      if let index = candidates.firstIndex(where: { IOObjectIsEqualTo(parent, $0) != 0 }) {
        return .found(index)
      }
      if "IOUSBHostDevice".withCString({ IOObjectConformsTo(parent, $0) != 0 }) {
        return .absent
      }
    }
    return .depthExceeded
  }

  private static func number(_ service: io_registry_entry_t, key: String)
    -> USBInventoryRawNumber
  {
    guard
      let unmanaged = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )
    else {
      return .missing
    }
    let value = unmanaged.takeRetainedValue()
    guard CFGetTypeID(value) == CFNumberGetTypeID(),
      let number = value as? NSNumber,
      let integer = SensorNumericSafety.uint64(number),
      integer <= UInt64(Int64.max)
    else {
      return .malformed
    }
    return .integer(Int64(integer))
  }

  private static func classify(_ result: kern_return_t) -> USBInventoryFailure {
    switch result {
    case kIOReturnNotPermitted, kIOReturnNotPrivileged:
      .operationNotPermitted
    case kIOReturnUnsupported:
      .unsupported
    case kIOReturnNoResources, kIOReturnNoMemory:
      .enumerationUnavailable
    default:
      .failed
    }
  }
}
