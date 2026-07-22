import AppKit
import SwiftUI

struct StagingView: View {
    @EnvironmentObject private var stager: Stager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                stageTab.tabItem { Label("Stage", systemImage: "sparkles") }
                captureTab.tabItem { Label("Capture", systemImage: "record.circle") }
                automationTab.tabItem { Label("Automation", systemImage: "bolt") }
            }
            .padding(.top, 8)
            Divider()
            footer
        }
        .frame(width: 500, height: 720)
        .onAppear { stager.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 1) {
                Text("Swab").font(.title3.bold())
                Text("Stage a spotless desktop, then put it all back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let countdown = stager.countdownLabel {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                    Text(countdown).monospacedDigit()
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.teal.opacity(0.18)))
                .help("Swab restores automatically when this reaches zero.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Tab 1 — Stage

    private var stageTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                presetsStep
                iconsStep
                backdropStep
                resolutionStep
                placementStep
            }
            .padding(14)
        }
    }

    @State private var newPresetName = ""

    private var presetsStep: some View {
        StepBox {
            StepLabel(title: "Presets",
                      detail: "Save this whole setup under a name — steps, backdrop, resolutions and all — and load it again in one click.")

            HStack(spacing: 8) {
                TextField("Preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePreset)
                Button("Save", action: savePreset)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 8)

            if stager.presets.presets.isEmpty {
                Text("No presets yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(stager.presets.presets) { preset in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name).font(.callout.weight(.medium))
                                Text(preset.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Load") { stager.apply(preset) }
                                .controlSize(.small)
                            Button {
                                stager.presets.delete(id: preset.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .help("Delete “\(preset.name)”")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func savePreset() {
        stager.saveCurrentAsPreset(named: newPresetName)
        newPresetName = ""
    }

    private var iconsStep: some View {
        StepBox {
            Toggle(isOn: $stager.hideIcons) {
                StepLabel(title: "Hide desktop icons",
                          detail: "Flips Finder's CreateDesktop setting — Finder relaunches when staging and again when restoring.")
            }
            .toggleStyle(.switch)
        }
    }

    private var backdropStep: some View {
        StepBox {
            Toggle(isOn: $stager.useBackdrop) {
                StepLabel(title: "Clean backdrop",
                          detail: "Covers the wallpaper with a full-screen layer under your windows and icons. Your real wallpaper is never touched.")
            }
            .toggleStyle(.switch)

            if stager.useBackdrop {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Fill", selection: $stager.backdrop.kind) {
                        ForEach(BackdropKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch stager.backdrop.kind {
                    case .preset:
                        HStack(spacing: 10) {
                            ForEach(BackdropStyle.allCases, id: \.self) { style in
                                Button {
                                    stager.backdrop.preset = style
                                } label: {
                                    Circle()
                                        .fill(LinearGradient(colors: style.swiftUIColors,
                                                             startPoint: .top,
                                                             endPoint: .bottom))
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle().strokeBorder(
                                                stager.backdrop.preset == style
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(0.15),
                                                lineWidth: stager.backdrop.preset == style ? 2.5 : 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(style.rawValue)
                            }
                            Spacer()
                            Text(stager.backdrop.preset.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .solid:
                        ColorPicker("Color", selection: colorBinding(\.topHex), supportsOpacity: false)
                    case .gradient:
                        HStack(spacing: 16) {
                            ColorPicker("Top", selection: colorBinding(\.topHex), supportsOpacity: false)
                            ColorPicker("Bottom", selection: colorBinding(\.bottomHex), supportsOpacity: false)
                        }
                    case .image:
                        HStack(spacing: 8) {
                            Text(stager.backdrop.imagePath.map {
                                URL(fileURLWithPath: $0).lastPathComponent
                            } ?? "No image chosen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Choose…", action: chooseBackdropImage)
                                .controlSize(.small)
                        }
                    }

                    // Preview strip, so the choice is visible before staging.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: stager.backdrop.swiftUIColors,
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 34)
                        .overlay {
                            if stager.backdrop.kind == .image, !stager.backdrop.isRenderable {
                                Text("Pick a readable image file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.12)))
                }
                .padding(.top, 8)
            }
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<BackdropConfig, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: stager.backdrop[keyPath: keyPath]) ?? .darkGray) },
            set: { stager.backdrop[keyPath: keyPath] = NSColor($0).hexString }
        )
    }

    private func chooseBackdropImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            stager.backdrop.imagePath = url.path
        }
    }

    private var resolutionStep: some View {
        StepBox {
            Toggle(isOn: $stager.changeResolution) {
                StepLabel(title: "Set resolution",
                          detail: "Switches displays for the session; the exact original modes come back on Restore. Leave a display on “Don't change” to skip it.")
            }
            .toggleStyle(.switch)

            if stager.changeResolution {
                VStack(alignment: .leading, spacing: 8) {
                    if stager.displays.isEmpty {
                        Text("No displays found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(stager.displays) { display in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(display.name).font(.callout.weight(.medium))
                                if display.isMain {
                                    Text("main")
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                                }
                                Spacer()
                                Text("now \(display.currentLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Picker("", selection: modeBinding(for: display)) {
                                Text("Don't change").tag(Optional<Int32>.none)
                                ForEach(display.modes) { mode in
                                    Text(mode.label).tag(Optional(mode.id))
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func modeBinding(for display: DisplayInfo) -> Binding<Int32?> {
        let key = String(display.id)
        return Binding(
            get: { stager.displayTargets[key] },
            set: { value in
                if let value {
                    stager.displayTargets[key] = value
                } else {
                    stager.displayTargets.removeValue(forKey: key)
                }
            }
        )
    }

    private var placementStep: some View {
        StepBox {
            Toggle(isOn: $stager.placeWindow) {
                StepLabel(title: "Place a window",
                          detail: "Centers and sizes another app's front window to a tidy frame, and returns it on Restore. Swab remembers the frame you pick for each app.")
            }
            .toggleStyle(.switch)

            if stager.placeWindow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("App", selection: $stager.targetAppPid) {
                            Text("Choose an app…").tag(Optional<pid_t>.none)
                            ForEach(stager.runningApps) { app in
                                Text(app.name).tag(Optional(app.pid))
                            }
                        }
                        Button {
                            stager.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh the app list")
                    }
                    Picker("Frame", selection: $stager.placement) {
                        ForEach(PlacementPreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !stager.axTrusted {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Moving another app's window needs Accessibility access.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Grant…") { stager.requestAccessibility() }
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Tab 2 — Capture

    private var captureTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                captureStep
                cursorStep
                focusStep
            }
            .padding(14)
        }
    }

    private var captureStep: some View {
        StepBox {
            StepLabel(title: "Capture",
                      detail: "Shoot a screenshot or record the screen without leaving Swab. Files land in Pictures › Swab — the Desktop is usually hidden while you're staged.")

            HStack(spacing: 8) {
                Button {
                    stager.capture.screenshot(showCursor: stager.showCursorInCaptures)
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }
                Button {
                    if stager.capture.isRecording {
                        stager.capture.stopRecording()
                    } else {
                        stager.capture.startRecording(showCursor: stager.showCursorInCaptures)
                    }
                } label: {
                    Label(stager.capture.isRecording ? "Stop Recording" : "Record",
                          systemImage: stager.capture.isRecording ? "stop.circle" : "record.circle")
                }
                .tint(stager.capture.isRecording ? .red : nil)
                Spacer()
                if stager.capture.lastOutput != nil {
                    Button("Reveal") { stager.capture.revealLastOutput() }
                        .controlSize(.small)
                }
            }
            .padding(.top, 8)

            if let last = stager.capture.lastOutput {
                Text(last.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 4)
            }

            Text("macOS asks for Screen Recording permission the first time you record.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var cursorStep: some View {
        StepBox {
            StepLabel(title: "Cursor",
                      detail: "The pointer is left out of captures unless you ask for it. Click rings are drawn in a click-through overlay, so they show up in a recording without changing where your clicks land.")

            Toggle(isOn: $stager.showCursorInCaptures) {
                Text("Include the cursor in screenshots and recordings")
            }
            .padding(.top, 8)

            Toggle(isOn: $stager.highlightClicks) {
                Text("Highlight clicks with an on-screen ring")
            }
            .padding(.top, 2)
        }
    }

    private var focusStep: some View {
        StepBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.indigo)
                    .padding(.top, 2)
                StepLabel(title: "Focus pairing",
                          detail: "macOS still gives apps no way to set a Focus mode, so Swab won't pretend to. What it can do is run two Shortcuts you build — one to switch Focus on when staging, one to switch it back on Restore.")
                Spacer()
            }

            if !FocusMode.isAvailable {
                Text("The Shortcuts command-line tool isn't available on this Mac, so this step is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                Toggle(isOn: $stager.pairFocus) {
                    Text("Run a shortcut when staging and restoring")
                }
                .padding(.top, 8)

                if stager.pairFocus {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("On stage", selection: $stager.focusOnShortcut) {
                                Text("Choose…").tag("")
                                ForEach(stager.focusShortcuts, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            Button {
                                stager.refreshFocusShortcuts()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Reload the shortcut list")
                        }
                        Picker("On restore", selection: $stager.focusOffShortcut) {
                            Text("Choose…").tag("")
                            ForEach(stager.focusShortcuts, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        if stager.focusShortcuts.isEmpty {
                            Text("No shortcuts found. Build two in the Shortcuts app using the “Set Focus” action, then reload this list.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button("Open Shortcuts…") {
                            if let url = URL(string: "shortcuts://") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 6)
                    .onAppear {
                        if stager.focusShortcuts.isEmpty { stager.refreshFocusShortcuts() }
                    }
                }
            }
        }
    }

    // MARK: Tab 3 — Automation

    private var automationTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                hotkeyStep
                autoRestoreStep
                cliStep
            }
            .padding(14)
        }
    }

    private var hotkeyStep: some View {
        StepBox {
            Toggle(isOn: $stager.hotkeyEnabled) {
                StepLabel(title: "Global hotkey",
                          detail: "One combination that stages when the desk is clear and restores when it's staged — so you never have to reach for the menu mid-recording.")
            }
            .toggleStyle(.switch)

            if stager.hotkeyEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HotkeyRecorder(binding: $stager.hotkeyBinding)
                    if stager.hotkeyConflict {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Another app already owns that combination — pick a different one.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var autoRestoreStep: some View {
        StepBox {
            Toggle(isOn: $stager.autoRestore) {
                StepLabel(title: "Auto-restore timer",
                          detail: "Stage for a fixed stretch and let Swab put everything back on its own — a safety net for when a recording runs long or you walk away.")
            }
            .toggleStyle(.switch)

            if stager.autoRestore {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $stager.autoRestoreMinutes, in: 1...180) {
                        Text("Restore after \(stager.autoRestoreMinutes) minute\(stager.autoRestoreMinutes == 1 ? "" : "s")")
                    }
                    if stager.secondsRemaining != nil {
                        HStack(spacing: 8) {
                            Text("Time left: \(stager.countdownLabel ?? "")")
                                .monospacedDigit()
                            Spacer()
                            Button("+5 min") { stager.extendCountdown(byMinutes: 5) }
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @State private var cliMessage: String?

    private var cliStep: some View {
        StepBox {
            StepLabel(title: "Command line",
                      detail: "Installs a small `swab` command so a build script or CI job can stage and restore: swab stage, swab restore, swab preset \"Demo\".")

            HStack(spacing: 8) {
                Button("Install `swab`…") {
                    if let url = CommandLineBridge.install() {
                        cliMessage = CommandLineBridge.isOnPath(url)
                            ? "Installed at \(url.path)."
                            : "Installed at \(url.path) — add that directory to your PATH."
                    } else {
                        cliMessage = "Couldn't write to /usr/local/bin or ~/.local/bin."
                    }
                }
                Spacer()
                if let installed = CommandLineBridge.installedPath {
                    Text(installed.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.top, 8)

            if let cliMessage {
                Text(cliMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                stager.stage()
            } label: {
                Label(stager.isStaged ? "Staged" : "Stage",
                      systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.teal)
            .disabled(stager.isStaged)

            Button {
                stager.restore()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!stager.isStaged)

            if !stager.statusMessage.isEmpty {
                Text(stager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }
}

// MARK: Hotkey recorder

/// Click, then press the combination. A local event monitor is enough — the
/// window is key while recording — so this needs no extra permission.
private struct HotkeyRecorder: View {
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text("Shortcut")
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Press keys…" : binding.displayString)
                    .frame(minWidth: 96)
                    .monospaced()
            }
            .tint(isRecording ? .teal : nil)
            if isRecording {
                Button("Cancel") { stop() }
                    .controlSize(.small)
            }
            Spacer()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let captured = HotkeyBinding(event: event) {
                binding = captured
                stop()
            }
            // Swallow the key either way, so a bare keypress doesn't leak into
            // whatever control is focused behind the recorder.
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

// MARK: Small building blocks

private struct StepBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

private struct StepLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
