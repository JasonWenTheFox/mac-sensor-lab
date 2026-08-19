import CoreFoundation
import Foundation
import IOKit

enum IOKitHelpers {
  static func matchingService(_ className: String) -> io_service_t {
    IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
  }

  static func serviceCount(_ className: String) -> Int {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching(className),
        &iterator
      ) == kIOReturnSuccess
    else {
      return 0
    }
    defer { IOObjectRelease(iterator) }

    var count = 0
    var service = IOIteratorNext(iterator)
    while service != 0 {
      count += 1
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }
    return count
  }

  static func number(_ service: io_registry_entry_t, key: String) -> Double? {
    guard service != 0,
      let unmanaged = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )
    else {
      return nil
    }
    let value = unmanaged.takeRetainedValue()
    return (value as? NSNumber)?.doubleValue
  }

  static func bool(_ service: io_registry_entry_t, key: String) -> Bool? {
    guard service != 0,
      let unmanaged = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
      )
    else {
      return nil
    }
    let value = unmanaged.takeRetainedValue()
    if let number = value as? NSNumber { return number.boolValue }
    return nil
  }
}
