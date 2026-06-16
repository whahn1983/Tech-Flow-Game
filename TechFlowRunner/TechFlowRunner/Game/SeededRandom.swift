//
//  SeededRandom.swift
//  Tech Flow Runner
//
//  Deterministic Mulberry32 RNG. When Daily Seed mode is active, every source
//  of gameplay randomness (terrain, obstacles, bits, power-ups, boss timing)
//  draws from a single instance seeded by the UTC date, so all players on the
//  same app version traverse an identical course.
//

import Foundation

struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        self.state = seed == 0 ? 1 : seed
    }

    /// Returns a value in [0, 1). Matches the Mulberry32 reference used by the
    /// web build so daily courses are reproducible across platforms.
    mutating func nextDouble() -> Double {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        let result = (t ^ (t >> 14))
        return Double(result) / Double(UInt32.max)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    mutating func nextCGFloat(_ min: Double, _ max: Double) -> CGFloat {
        CGFloat(min + nextDouble() * (max - min))
    }
}

/// Random source abstraction so gameplay code is agnostic to whether it is in
/// deterministic (daily) or free-roam (system random) mode.
final class RandomSource {
    private var seeded: SeededRandom?
    let isSeeded: Bool

    init(seed: UInt32?) {
        if let seed {
            self.seeded = SeededRandom(seed: seed)
            self.isSeeded = true
        } else {
            self.seeded = nil
            self.isSeeded = false
        }
    }

    /// [0, 1)
    func double() -> Double {
        if seeded != nil {
            return seeded!.nextDouble()
        }
        return Double.random(in: 0..<1)
    }

    func cgFloat(_ min: Double, _ max: Double) -> CGFloat {
        CGFloat(min + double() * (max - min))
    }

    func int(_ min: Int, _ max: Int) -> Int {
        guard max > min else { return min }
        return min + Int(double() * Double(max - min))
    }

    /// Daily seed derived from the current UTC date as an integer YYYYMMDD.
    static func dailySeed(for date: Date = Date()) -> UInt32 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let value = y * 10000 + m * 100 + d
        return UInt32(truncatingIfNeeded: value) == 0 ? 1 : UInt32(truncatingIfNeeded: value)
    }

    /// "YYYY-MM-DD" string for the current UTC date, used for display and for
    /// the daily leaderboard label.
    static func dailySeedDateString(for date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
