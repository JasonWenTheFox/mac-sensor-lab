public enum SensorPreferenceKeys {
  public static func samplingCadence(isDemoMode: Bool) -> String {
    scoped("dev.macsensorlab.samplingCadence", isDemoMode: isDemoMode)
  }

  public static func ambientLuxCalibration(isDemoMode: Bool) -> String {
    scoped("dev.macsensorlab.ambientLuxCalibration", isDemoMode: isDemoMode)
  }

  public static func ambientSpectralReference(isDemoMode: Bool) -> String {
    scoped("dev.macsensorlab.ambientSpectralReference", isDemoMode: isDemoMode)
  }

  public static func lidHasReference(isDemoMode: Bool) -> String {
    scoped("dev.macsensorlab.lid.hasReference", isDemoMode: isDemoMode)
  }

  public static func lidReferenceAngle(isDemoMode: Bool) -> String {
    scoped("dev.macsensorlab.lid.referenceAngle", isDemoMode: isDemoMode)
  }

  private static func scoped(_ base: String, isDemoMode: Bool) -> String {
    base + (isDemoMode ? ".demo" : "")
  }
}
