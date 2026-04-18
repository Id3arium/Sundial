import Foundation
import AppKit

@MainActor
class Scheduler {
    private var timer: Timer?
    private var transitionTask: Task<Void, Never>?
    private var lastAppliedEntryID: UUID?
    private var lastAppliedPreset: Preset?

    private weak var state: AppState?
    private var controller: DDCController?

    func start(state: AppState, controller: DDCController) {
        self.state = state
        self.controller = controller

        observeWake(state: state, controller: controller)

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick(state: state, controller: controller)
            }
        }
        // Fire immediately
        tick(state: state, controller: controller)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        transitionTask?.cancel()
        transitionTask = nil
    }

    /// Called when a preview ends — snap monitor back to whatever the schedule says
    /// *right now* (not whatever we were about to apply). Bypasses the "already applied"
    /// dedupe so the re-apply always happens.
    func reapplyForCurrentTime() {
        guard let state, let controller else { return }
        guard let entry = activeEntry(in: state.schedule, presets: state.presets) else { return }
        guard let preset = state.preset(for: entry.presetID) else { return }

        lastAppliedEntryID = entry.id
        lastAppliedPreset = preset
        state.activePresetID = preset.id

        transitionTask?.cancel()
        transitionTask = Task {
            await controller.apply(preset)
        }
    }

    /// Re-evaluate "which preset should be active right now" and apply if it changed.
    /// Call after any edit that can change the answer: enabling/disabling a preset,
    /// toggling a schedule entry, editing a time. Respects ongoing previews.
    func recompute() {
        guard let state, let controller else { return }
        guard state.previewingPresetID == nil else { return }
        // Force the tick to act even if the entry ID hasn't changed — the
        // underlying preset's enabled state might have.
        lastAppliedEntryID = nil
        tick(state: state, controller: controller)
    }

    // MARK: - Tick

    private func tick(state: AppState, controller: DDCController) {
        // Preview owns the monitor while active — don't fight it.
        guard state.previewingPresetID == nil else { return }

        controller.cliPath = state.cliPath
        controller.displayName = state.displayName

        guard let entry = activeEntry(in: state.schedule, presets: state.presets) else { return }
        guard entry.id != lastAppliedEntryID else { return }
        guard let preset = state.preset(for: entry.presetID) else { return }

        let previous = lastAppliedPreset
        lastAppliedEntryID = entry.id
        lastAppliedPreset = preset
        state.activePresetID = preset.id

        transitionTask?.cancel()
        transitionTask = Task {
            if let from = previous {
                await controller.applySmooth(from: from, to: preset, duration: 60)
            } else {
                await controller.apply(preset)
            }
        }
    }

    // MARK: - Wake handling

    private func observeWake(state: AppState, controller: DDCController) {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard state.applyOnWake,
                      state.previewingPresetID == nil,
                      let preset = state.preset(for: state.activePresetID) else { return }
                // Snap (no smooth) after wake — monitor may have reset DDC state
                self.transitionTask?.cancel()
                self.transitionTask = Task {
                    await controller.apply(preset)
                }
            }
        }
    }

    // MARK: - Active entry logic

    /// Returns the most recent enabled schedule entry (pointing at an enabled preset) whose time ≤ now.
    /// Wraps midnight: if nothing is before now, returns the last entry of the day.
    private func activeEntry(in schedule: [ScheduleEntry], presets: [Preset]) -> ScheduleEntry? {
        let enabledPresetIDs = Set(presets.filter { $0.enabled }.map { $0.id })
        let enabled = schedule.filter { $0.enabled && enabledPresetIDs.contains($0.presetID) }
        guard !enabled.isEmpty else { return nil }

        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        if let entry = enabled.last(where: { $0.minutesSinceMidnight <= nowMinutes }) {
            return entry
        }
        return enabled.max(by: { $0.minutesSinceMidnight < $1.minutesSinceMidnight })
    }
}
