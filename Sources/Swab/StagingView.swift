import AppKit
import SwiftUI

struct StagingView: View {
    @EnvironmentObject private var stager: Stager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    iconsStep
                    backdropStep
                    resolutionStep
                    placementStep
                    dndReminder
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 680)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Steps

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
                          detail: "Covers the wallpaper with a full-screen color layer under your windows and icons. Your real wallpaper is never touched.")
            }
            .toggleStyle(.switch)

            if stager.useBackdrop {
                HStack(spacing: 10) {
                    ForEach(BackdropStyle.allCases, id: \.self) { style in
                        Button {
                            stager.backdropStyle = style
                        } label: {
                            Circle()
                                .fill(LinearGradient(colors: style.swiftUIColors,
                                                     startPoint: .top,
                                                     endPoint: .bottom))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().strokeBorder(
                                        stager.backdropStyle == style
                                            ? Color.accentColor
                                            : Color.primary.opacity(0.15),
                                        lineWidth: stager.backdropStyle == style ? 2.5 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(style.rawValue)
                    }
                    Spacer()
                    Text(stager.backdropStyle.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
    }

    private var resolutionStep: some View {
        StepBox {
            Toggle(isOn: $stager.changeResolution) {
                StepLabel(title: "Set resolution",
                          detail: "Switches the main display for the session; the exact original mode comes back on Restore.")
            }
            .toggleStyle(.switch)

            if stager.changeResolution {
                Picker("Target", selection: $stager.targetModeID) {
                    Text("Choose a resolution…").tag(Optional<Int32>.none)
                    ForEach(stager.modeChoices) { choice in
                        Text(choice.label + (choice.id == stager.currentModeID ? "  (current)" : ""))
                            .tag(Optional(choice.id))
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var placementStep: some View {
        StepBox {
            Toggle(isOn: $stager.placeWindow) {
                StepLabel(title: "Place a window",
                          detail: "Centers and sizes another app's front window to a tidy frame, and returns it on Restore.")
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

    private var dndReminder: some View {
        StepBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.indigo)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Do Not Disturb — a reminder, not a toggle")
                        .font(.body.weight(.medium))
                    Text("macOS doesn't let apps flip Focus modes, so Swab won't pretend to. Switch it on in Control Center before you hit record.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Focus Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
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
