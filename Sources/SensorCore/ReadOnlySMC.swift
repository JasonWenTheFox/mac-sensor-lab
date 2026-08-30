import Foundation
import IOKit

// Read-only subset adapted from exelban/stats (MIT), commit
// db5fee1eae913e24a7e0c4a0395092d867cf902d.
// All mutation and fan-control methods are intentionally omitted.

private enum SMCCommand: UInt8 {
  case kernelIndex = 2
  case readBytes = 5
  case readKeyInfo = 9
}

private struct SMCKeyData {
  typealias Bytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  struct Version {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
  }

  struct PowerLimit {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpu: UInt32 = 0
    var gpu: UInt32 = 0
    var memory: UInt32 = 0
  }

  struct KeyInfo {
    var dataSize: IOByteCount32 = 0
    var dataType: UInt32 = 0
    var attributes: UInt8 = 0
  }

  var key: UInt32 = 0
  var version = Version()
  var powerLimit = PowerLimit()
  var keyInfo = KeyInfo()
  var padding: UInt16 = 0
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: Bytes = (
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
  )
}

private struct SMCValue {
  let key: String
  var dataSize: UInt32 = 0
  var dataType = ""
  var bytes = [UInt8](repeating: 0, count: 32)
}

extension UInt32 {
  fileprivate init(fourCharacterCode string: String) {
    precondition(string.utf8.count == 4)
    self = string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  fileprivate var fourCharacterString: String {
    let scalars = [24, 16, 8, 0].compactMap { shift in
      UnicodeScalar((self >> UInt32(shift)) & 0xFF)
    }
    return String(String.UnicodeScalarView(scalars))
  }
}

final class ReadOnlySMC: @unchecked Sendable {
  private var connection: io_connect_t = 0
  private let lock = NSLock()

  init() throws {
    var iterator: io_iterator_t = 0
    let matchingResult = IOServiceGetMatchingServices(
      kIOMainPortDefault,
      IOServiceMatching("AppleSMC"),
      &iterator
    )
    guard matchingResult == kIOReturnSuccess else {
      throw ReadOnlySMCOpenError.enumerationFailed(matchingResult)
    }
    defer { IOObjectRelease(iterator) }

    let device = IOIteratorNext(iterator)
    guard device != 0 else { throw ReadOnlySMCOpenError.serviceUnavailable }
    defer { IOObjectRelease(device) }

    let openResult = IOServiceOpen(device, mach_task_self_, 0, &connection)
    guard openResult == kIOReturnSuccess else {
      throw ReadOnlySMCOpenError.userClientOpenFailed(openResult)
    }
  }

  deinit {
    if connection != 0 { IOServiceClose(connection) }
  }

  func value(for key: String) -> Double? {
    guard key.utf8.count == 4 else { return nil }
    lock.lock()
    defer { lock.unlock() }

    var value = SMCValue(key: key)
    guard read(&value) == kIOReturnSuccess,
      value.dataSize > 0,
      value.bytes.prefix(Int(value.dataSize)).contains(where: { $0 != 0 })
    else {
      return nil
    }

    let b = value.bytes
    switch value.dataType {
    case "ui8 ":
      return Double(b[0])
    case "ui16":
      return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
    case "ui32":
      return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
    case "sp1e": return fixedUnsigned(b, divisor: 16_384)
    case "sp3c": return fixedUnsigned(b, divisor: 4_096)
    case "sp4b": return fixedUnsigned(b, divisor: 2_048)
    case "sp5a": return fixedUnsigned(b, divisor: 1_024)
    case "sp69": return fixedUnsigned(b, divisor: 512)
    case "sp78": return fixedSigned(b, divisor: 256)
    case "sp87": return fixedSigned(b, divisor: 128)
    case "sp96": return fixedSigned(b, divisor: 64)
    case "spa5": return fixedSigned(b, divisor: 32)
    case "spb4": return fixedSigned(b, divisor: 16)
    case "spf0": return fixedSigned(b, divisor: 1)
    case "fpe2":
      return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
    case "flt ":
      let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
      return Double(Float(bitPattern: bits))
    default:
      return nil
    }
  }

  private func fixedUnsigned(_ bytes: [UInt8], divisor: Double) -> Double {
    Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / divisor
  }

  private func fixedSigned(_ bytes: [UInt8], divisor: Double) -> Double {
    let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
    return Double(raw) / divisor
  }

  private func read(_ value: inout SMCValue) -> kern_return_t {
    var input = SMCKeyData()
    var output = SMCKeyData()
    input.key = UInt32(fourCharacterCode: value.key)
    input.data8 = SMCCommand.readKeyInfo.rawValue

    var result = call(SMCCommand.kernelIndex.rawValue, input: &input, output: &output)
    guard result == kIOReturnSuccess else { return result }

    value.dataSize = UInt32(output.keyInfo.dataSize)
    value.dataType = output.keyInfo.dataType.fourCharacterString
    input.keyInfo.dataSize = output.keyInfo.dataSize
    input.data8 = SMCCommand.readBytes.rawValue

    result = call(SMCCommand.kernelIndex.rawValue, input: &input, output: &output)
    guard result == kIOReturnSuccess else { return result }

    withUnsafeBytes(of: &output.bytes) { source in
      let count = min(Int(value.dataSize), value.bytes.count, source.count)
      value.bytes.replaceSubrange(0..<count, with: source.prefix(count))
    }
    return kIOReturnSuccess
  }

  private func call(
    _ index: UInt8,
    input: inout SMCKeyData,
    output: inout SMCKeyData
  ) -> kern_return_t {
    guard connection != 0 else { return kIOReturnNotOpen }
    var outputSize = MemoryLayout<SMCKeyData>.stride
    return IOConnectCallStructMethod(
      connection,
      UInt32(index),
      &input,
      MemoryLayout<SMCKeyData>.stride,
      &output,
      &outputSize
    )
  }
}

enum ReadOnlySMCOpenError: Error, Equatable {
  case enumerationFailed(IOReturn)
  case serviceUnavailable
  case userClientOpenFailed(IOReturn)
}
