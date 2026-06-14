import Foundation

@MainActor
class DDCController {
    var cliPath: String
    var displayName: String

    init(cliPath: String, displayName: String) {
        self.cliPath = cliPath
        self.displayName = displayName
    }

    // MARK: - Public API

    func apply(_ preset: Preset) async {
        await setPercent("hardwareBrightness", value: preset.hardwareBrightness)
        await setPercent("hardwareContrast", value: preset.hardwareContrast)
        NightShiftController.setStrength(preset.nightShift)
    }

    /// Apply only a single parameter — used during live slider drag to avoid
    /// re-sending unchanged params and triggering BetterDisplay's poll/snap.
    func applySingle(_ param: String, value: Int) async {
        if param == "nightShift" {
            NightShiftController.setStrength(value)
        } else {
            await setPercent(param, value: value)
        }
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

    /// Returns true if the display's actual DDC brightness and contrast match the preset.
    /// Uses raw DDC reads (VCP codes) to bypass BetterDisplay's cache.
    func matches(_ preset: Preset) -> Bool {
        guard let brightness = readDDC(vcp: 0x10),
              let contrast   = readDDC(vcp: 0x12) else { return false }
        return abs(brightness - preset.hardwareBrightness) <= 1
            && abs(contrast   - preset.hardwareContrast)   <= 1
    }

    /// Probe whether the configured display is reachable over DDC by attempting
    /// a raw brightness read (VCP 0x10). Used by setup validation to confirm the
    /// CLI path + display name resolve to a real, controllable monitor before
    /// unlocking presets. Returns true if the read returns a value.
    func probe() async -> Bool {
        readDDC(vcp: 0x10) != nil
    }

    // MARK: - Private

    /// Read a raw DDC value from the monitor via VCP code. Returns the integer
    /// value directly from the display hardware, bypassing BetterDisplay's cache.
    /// VCP 0x10 = brightness, 0x12 = contrast.
    private func readDDC(vcp: Int) -> Int? {
        let hex = String(format: "0x%02X", vcp)
        let output = runCapture([cliPath, "get", "-nameLike=\(displayName)", "-ddc", "-vcp=\(hex)"])
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func setPercent(_ param: String, value: Int) async {
        run([cliPath, "set", "-namelike=\(displayName)", "-\(param)=\(value)%"])
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    private func runCapture(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
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
