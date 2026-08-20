import Darwin
import Foundation

public enum SensorPrivateFileWriterError: LocalizedError, Equatable {
  case invalidDestination

  public var errorDescription: String? {
    switch self {
    case .invalidDestination:
      "The export destination must be a local file URL."
    }
  }
}

/// Atomically replaces a user-selected local file through a same-directory owner-only temp file.
public enum SensorPrivateFileWriter {
  public static let ownerReadWritePermissions: mode_t = 0o600

  public static func write(_ data: Data, to destinationURL: URL) throws {
    guard destinationURL.isFileURL, !destinationURL.lastPathComponent.isEmpty else {
      throw SensorPrivateFileWriterError.invalidDestination
    }

    let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
      ".mac-sensor-lab-export.XXXXXX"
    )
    var template = Array(temporaryURL.path.utf8CString)
    let descriptor = template.withUnsafeMutableBufferPointer { buffer in
      mkstemp(buffer.baseAddress!)
    }
    guard descriptor >= 0 else { throw posixError(operation: "create temporary export") }

    let temporaryPath = template.withUnsafeBufferPointer { buffer in
      String(cString: buffer.baseAddress!)
    }
    var shouldRemoveTemporaryFile = true
    defer {
      if shouldRemoveTemporaryFile {
        temporaryPath.withCString { _ = Darwin.unlink($0) }
      }
    }

    guard fchmod(descriptor, ownerReadWritePermissions) == 0 else {
      let error = posixError(operation: "set private export permissions")
      Darwin.close(descriptor)
      throw error
    }

    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }

    let renameResult = temporaryPath.withCString { sourcePath in
      destinationURL.path.withCString { destinationPath in
        Darwin.rename(sourcePath, destinationPath)
      }
    }
    guard renameResult == 0 else {
      throw posixError(operation: "replace export destination")
    }
    shouldRemoveTemporaryFile = false
  }

  private static func posixError(operation: String, code: Int32 = errno) -> NSError {
    let description = "Could not \(operation): \(String(cString: strerror(code)))"
    return NSError(
      domain: NSPOSIXErrorDomain,
      code: Int(code),
      userInfo: [NSLocalizedDescriptionKey: description]
    )
  }
}
