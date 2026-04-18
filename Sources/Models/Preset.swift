import Foundation

struct Preset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String

    /// Combined brightness (0–100) — BetterDisplay blends hardware backlight
    /// and software dimming together. Remapped to [15,100] on apply so the
    /// screen never goes pitch black.
    /// Driven via BetterDisplay CLI (`-combinedBrightness`).
    /// Codable key kept as `softwareBrightness` for backward compat with old configs.
    var combinedBrightness: Int

    /// Night Shift strength (0–100). 0 = off, 100 = maximum warmth.
    /// Driven via macOS's built-in Night Shift (CoreBrightness private framework).
    var nightShift: Int

    /// When false, the scheduler skips any schedule entry pointing at this preset.
    /// Temporary disable without deleting. Defaults true (back-compat with older configs).
    var enabled: Bool = true

    static let defaults: [Preset] = [
        Preset(name: "Morning", combinedBrightness: 50, nightShift: 30),
        Preset(name: "Day",     combinedBrightness: 90, nightShift: 0),
        Preset(name: "Evening", combinedBrightness: 60, nightShift: 50),
        Preset(name: "Night",   combinedBrightness: 25, nightShift: 90),
    ]

    /// Linear interpolation toward another preset (used for smooth transitions)
    func lerp(to other: Preset, t: Double) -> Preset {
        func lerpInt(_ a: Int, _ b: Int) -> Int { Int(Double(a) + (Double(b) - Double(a)) * t) }
        return Preset(
            id: id,
            name: name,
            combinedBrightness: lerpInt(combinedBrightness, other.combinedBrightness),
            nightShift:         lerpInt(nightShift, other.nightShift),
            enabled:            enabled
        )
    }

    // MARK: - Codable (manual to default `enabled` to true for older configs)

    enum CodingKeys: String, CodingKey {
        case id, name, nightShift, enabled
        case combinedBrightness = "softwareBrightness"
    }

    init(id: UUID = UUID(), name: String, combinedBrightness: Int, nightShift: Int, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.combinedBrightness = combinedBrightness
        self.nightShift = nightShift
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.combinedBrightness = try c.decode(Int.self, forKey: .combinedBrightness)
        self.nightShift = try c.decode(Int.self, forKey: .nightShift)
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }
}
