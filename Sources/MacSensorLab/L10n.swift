import Foundation

/// Centralized UI localization for the native app target.
///
/// Sensor payloads remain stable English facts for export and diagnostics. The app resolves their
/// display strings here when a matching translation exists, so localization never changes IDs or
/// serialized data.
public enum L10n {
  public static func text(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
  }

  public static func format(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: text(key), locale: .current, arguments: arguments)
  }
}
