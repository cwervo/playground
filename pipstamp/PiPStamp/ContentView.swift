import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: StampEngine
    @State private var newLabel = ""

    private let layout = FrameRenderer.Layout()

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                pipSection
                refreshSection
                payloadSection
                keyboardSection
                setupSection
            }
            .navigationTitle("PiPStamp")
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            SampleBufferView(layer: engine.pip.displayLayer)
                .aspectRatio(layout.width / layout.height, contentMode: .fit)
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(12)
                .padding(.vertical, 4)
            Text(engine.markdown)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            LabeledContent("Payload", value: "\(engine.markdown.utf8.count) bytes")
            if let modules = engine.moduleCount {
                LabeledContent("Density", value: "\(modules) modules per side")
            }
        } header: {
            Text("Live stamp")
        } footer: {
            Text("This view is the PiP video source. What you see here is exactly what floats over other apps.")
        }
    }

    private var pipSection: some View {
        Section("Picture in Picture") {
            if !engine.pip.isSupported {
                Label("PiP is not supported on this device.", systemImage: "exclamationmark.triangle")
            }
            Button {
                engine.pip.toggle()
            } label: {
                Label(engine.pip.isActive ? "Stop PiP" : "Start PiP",
                      systemImage: engine.pip.isActive ? "pip.exit" : "pip.enter")
            }
            .disabled(!engine.pip.isPossible)

            Toggle("Start PiP when leaving the app", isOn: $engine.settings.startPiPAutomatically)
            Toggle("Keep alive with silent audio", isOn: $engine.settings.keepAliveWithSilentAudio)

            LabeledContent("Status", value: engine.pip.isActive ? "Active" :
                            (engine.pip.isPossible ? "Ready" : "Not possible yet"))
            if engine.pip.renderSize.width > 0 {
                LabeledContent("Window", value: "\(Int(engine.pip.renderSize.width))×\(Int(engine.pip.renderSize.height)) px")
            }
            if let error = engine.pip.lastError {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
    }

    private var refreshSection: some View {
        Section {
            Picker("Every", selection: $engine.settings.refreshSeconds) {
                ForEach(StampSettings.refreshPresets, id: \.self) { seconds in
                    Text(Self.describe(seconds: seconds)).tag(seconds)
                }
            }
            Stepper("Custom: \(Self.describe(seconds: engine.settings.refreshSeconds))",
                    value: $engine.settings.refreshSeconds,
                    in: StampSettings.minimumRefreshSeconds...StampSettings.maximumRefreshSeconds,
                    step: 30)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LabeledContent("Next refresh", value: countdown(at: timeline.date))
            }
            if let last = engine.lastRefresh {
                LabeledContent("Last refresh",
                               value: "\(last.formatted(date: .omitted, time: .standard)) · \(engine.lastReason.rawValue)")
            }
            Button {
                engine.refresh(reason: .manual)
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Refresh")
        } footer: {
            Text("Minimum is 60 seconds. A keyboard capture also refreshes immediately and restarts the countdown.")
        }
    }

    private var payloadSection: some View {
        Section {
            Toggle("Current app", isOn: $engine.settings.includeApp)
            Toggle("Text around the cursor", isOn: $engine.settings.includeScreenText)
            Toggle("Field details", isOn: $engine.settings.includeFieldInfo)
            Toggle("Device name", isOn: $engine.settings.includeDevice)
            Stepper("Max text: \(engine.settings.maxScreenTextChars) chars",
                    value: $engine.settings.maxScreenTextChars, in: 0...400, step: 20)
            Picker("Error correction", selection: $engine.settings.errorCorrection) {
                ForEach(StampSettings.ErrorCorrection.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("What goes in the QR")
        } footer: {
            Text("Less text and lower error correction keep the code coarse enough to scan from a small PiP window.")
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("Capture while typing", isOn: $engine.settings.autoCaptureWhileTyping)
            Toggle("Show QR inside the keyboard", isOn: $engine.settings.showQRInKeyboard)
            if let context = engine.context {
                LabeledContent("Last capture") {
                    VStack(alignment: .trailing) {
                        Text(context.capturedAt.formatted(date: .omitted, time: .standard))
                        Text(context.appName ?? "app not tagged")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No capture from the keyboard yet.").foregroundStyle(.secondary)
            }
            ForEach(engine.settings.hostLabels, id: \.self) { label in
                Text(label)
            }
            .onDelete { offsets in
                engine.settings.hostLabels.remove(atOffsets: offsets)
            }
            HStack {
                TextField("Add app label", text: $newLabel)
                Button("Add") {
                    engine.settings.hostLabels.append(newLabel)
                    newLabel = ""
                }
                .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text("Labels appear as chips in the keyboard so you can tag which app you are in. iOS does not tell keyboards the host app's name.")
        }
    }

    private var setupSection: some View {
        Section("Setup") {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard → PiPStamp")
                Text("2. Tap PiPStamp → Allow Full Access (needed to talk to this app)")
                Text("3. Start PiP here, then switch apps. Hold the globe key to pick PiPStamp.")
            }
            .font(.footnote)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
        }
    }

    // MARK: Helpers

    private func countdown(at date: Date) -> String {
        guard let next = engine.nextRefresh else { return "—" }
        let remaining = max(0, Int(next.timeIntervalSince(date).rounded(.up)))
        return Self.describe(seconds: remaining)
    }

    private static func describe(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds / 60) min \(seconds % 60)s"
    }
}
