import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var schedule: [ScheduleEntry] = []
    @Published var activePresetID: UUID?
    @Published var displayName: String = ""
    @Published var cliPath: String = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
    @Published var applyOnWake: Bool = true
    @Published var launchAtLogin: Bool = false

    /// True once the BetterDisplay path + display name have been verified against
    /// real hardware (a DDC read succeeded). Until then, the menu bar shows the
    /// setup screen instead of presets — Sundial can't control a monitor it can't
    /// reach, and silently-failing sliders are a worse first-run than an honest gate.
    /// Persisted so a returning user with a known-good setup skips onboarding.
    @Published var isSetUp: Bool = false

    /// ID of the preset currently being live-previewed, if any.
    /// While non-nil, the Scheduler suppresses its own apply calls —
    /// the preview owns the monitor until the user ends it.
    @Published var previewingPresetID: UUID?

    /// Set by the app at startup — lets views ask the scheduler to snap back
    /// to the current-time preset when a preview ends.
    var onPreviewEnded: (() -> Void)?

    /// Set by the app at startup — lets views ask the scheduler to re-evaluate
    /// which preset should be active right now (e.g. after toggling Enabled).
    var onScheduleChanged: (() -> Void)?

    private let configURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Sundial")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    init() {
        load()
    }

    // MARK: - Persistence

    private struct Config: Codable {
        var presets: [Preset]
        var schedule: [ScheduleEntry]
        var displayName: String
        var cliPath: String
        var applyOnWake: Bool
        var launchAtLogin: Bool
        var isSetUp: Bool?
    }

    func save() {
        let config = Config(
            presets: presets,
            schedule: schedule,
            displayName: displayName,
            cliPath: cliPath,
            applyOnWake: applyOnWake,
            launchAtLogin: launchAtLogin,
            isSetUp: isSetUp
        )
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[Sundial] Save failed: \(error)")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            seedDefaults()
            return
        }
        presets = config.presets
        schedule = config.schedule.sorted { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        displayName = config.displayName
        cliPath = config.cliPath
        applyOnWake = config.applyOnWake
        launchAtLogin = config.launchAtLogin
        isSetUp = config.isSetUp ?? false
    }

    // MARK: - Setup validation

    /// Verify the current BetterDisplay path + display name actually reach a
    /// monitor by attempting a DDC brightness read. On success, flips `isSetUp`
    /// to true (unlocking presets) and persists. Returns nil on success, or a
    /// user-facing failure reason on error.
    func validateSetup() async -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Enter your monitor's display name (a partial match of the name shown in BetterDisplay)."
        }
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return "BetterDisplay CLI not found at that path. Confirm BetterDisplay.app is installed and the path points to .../Contents/MacOS/BetterDisplay."
        }
        let controller = DDCController(cliPath: cliPath, displayName: trimmedName)
        let reachable = await controller.probe()
        guard reachable else {
            return "Couldn't read brightness from a monitor matching \"\(trimmedName)\". Check the display name matches a connected monitor in BetterDisplay and that the monitor has DDC/CI enabled in its on-screen menu."
        }
        isSetUp = true
        save()
        return nil
    }

    private func seedDefaults() {
        presets = Preset.defaults
        schedule = [
            ScheduleEntry(presetID: presets[0].id, hour: 6,  minute: 30),
            ScheduleEntry(presetID: presets[1].id, hour: 10, minute: 0),
            ScheduleEntry(presetID: presets[2].id, hour: 18, minute: 30),
            ScheduleEntry(presetID: presets[3].id, hour: 22, minute: 0),
        ]
        save()
    }

    // MARK: - Mutations

    func addPreset(_ preset: Preset) {
        presets.append(preset)
        save()
    }

    func updatePreset(_ preset: Preset) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[i] = preset
        save()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        schedule.removeAll { $0.presetID == id }
        save()
    }

    func addScheduleEntry(_ entry: ScheduleEntry) {
        schedule.append(entry)
        schedule.sort { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        save()
    }

    func updateScheduleEntry(_ entry: ScheduleEntry) {
        guard let i = schedule.firstIndex(where: { $0.id == entry.id }) else { return }
        schedule[i] = entry
        schedule.sort { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        save()
    }

    func deleteScheduleEntry(id: UUID) {
        schedule.removeAll { $0.id == id }
        save()
    }

    func preset(for id: UUID?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}
