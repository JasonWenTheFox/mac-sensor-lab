import SensorCore
import SwiftUI

@main
struct MacSensorLabApp: App {
  @StateObject private var model: SensorDashboardModel

  init() {
    let isDemoMode = CommandLine.arguments.contains("--demo")
    _model = StateObject(
      wrappedValue: SensorDashboardModel(
        providers: isDemoMode
          ? SensorDemoProviderRegistry.providers() : SensorProviderRegistry.providers(),
        isDemoMode: isDemoMode
      ))
  }

  var body: some Scene {
    Window("Mac Sensor Lab", id: "dashboard") {
      RootView(model: model)
        .frame(minWidth: 940, minHeight: 640)
        .task { await model.runLiveUpdates() }
        .onDisappear {
          Task { await model.stopRecording() }
        }
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 1120, height: 760)

    Settings {
      SettingsView(model: model)
    }
  }
}

private struct SettingsView: View {
  @ObservedObject var model: SensorDashboardModel

  var body: some View {
    Form {
      if model.isDemoMode {
        Section("Data mode") {
          Label("Demo data — no hardware is being read", systemImage: "testtube.2")
            .foregroundStyle(.orange)
        }
      }
      Section("Sampling") {
        Picker("Automatic sampling interval", selection: $model.samplingCadence) {
          ForEach(SamplingCadence.allCases) { cadence in
            Text(cadence.displayName).tag(cadence)
          }
        }
        Text("The interval is remembered. Pause state is intentionally reset on every launch.")
          .foregroundStyle(.secondary)
      }
      Section("Safety") {
        Text(
          "Mac Sensor Lab reads sensors locally and does not request administrator access in this build."
        )
        Text(
          "Permission-gated providers are opt-in and will explain their purpose before requesting access."
        )
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 330)
    .padding()
  }
}
