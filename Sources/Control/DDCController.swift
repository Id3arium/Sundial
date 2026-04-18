import Foundation

class DDCController {
    var cliPath: String
    var displayName: String

    init(cliPath: String, displayName: String) {
        self.cliPath = cliPath
        self.displayName = displayName
    }

    // MARK: - Public API

    func apply(_ preset: Preset) async {
        await setPercent("combinedBrightness", value: preset.combinedBrightness)
        NightShiftController.setStrength(preset.nightShift)
    }

    /// Smoothly interpolate from `from` to `to` over `duration` seconds.
    /// Cancellable — callers should wrap in a Task.
    func applySmooth(from: Preset, to: Preset, duration: TimeInterval = 60) async {
        let stepInterval: TimeInterval = 2.0
        let steps = max(1, Int(duration / stepInterval))

        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let t = Double(step) / Double(steps)
            await apply(from.lerp(to: to, t: t))
            if step < steps {
                try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
            }
        }
    }

    // MARK: - Private

    private func setPercent(_ param: String, value: Int) async {
        // Remap [0,100] → [15,100]: 0% combined brightness is a pitch-black unrecoverable screen
        let mapped = 15 + (value * 85 / 100)
        // betterdisplaycli set -namelike=GIGABYTE -combinedBrightness=70%
        run([cliPath, "set", "-namelike=\(displayName)", "-\(param)=\(mapped)%"])
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    @discardableResult
    private func run(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            if status != 0 {
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let cmd = args.joined(separator: " ")
                print("[Sundial] CLI exited \(status) for: \(cmd)")
                if !out.isEmpty { print("[Sundial] stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
                if !err.isEmpty { print("[Sundial] stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))") }
                if out.contains("Failed") || err.contains("Failed") {
                    print("[Sundial] BetterDisplay reported 'Failed' — the display name in Settings may not match any connected monitor. Check Settings → Display name and confirm it matches (partial match) the monitor name shown in BetterDisplay.")
                }
            }
            return status
        } catch {
            print("[Sundial] Could not launch BetterDisplay: \(error.localizedDescription) — verify the path in Settings points to /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay and that BetterDisplay.app is installed.")
            return -1
        }
    }
}
