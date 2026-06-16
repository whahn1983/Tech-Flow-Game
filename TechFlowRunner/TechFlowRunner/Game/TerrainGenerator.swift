//
//  TerrainGenerator.swift
//  Tech Flow Runner
//
//  Procedural side-scrolling terrain: rolling ground, slopes, precipices (gaps)
//  and cave ceilings, with the same clearance/safety rules as the reference so
//  obstacle/terrain combinations stay fair. Everything is computed in design
//  space (y increases downward); the scene flips to y-up for rendering.
//
//  When a seeded RandomSource is supplied (Daily Seed mode) the entire course
//  is deterministic.
//

import CoreGraphics
import Foundation

struct Cave {
    var start: CGFloat
    var end: CGFloat
    var baseCeiling: CGFloat
    var amplitude: CGFloat
    var phase: CGFloat
}

struct Precipice {
    var start: CGFloat
    var end: CGFloat
}

struct TerrainPoint {
    var x: CGFloat
    var y: CGFloat
}

/// Tunable safety budget controlling fair obstacle/terrain placement.
struct CourseSafety {
    let minTakeoffBuffer: CGFloat = 96
    let minTakeoffBufferForStay: CGFloat = 176
    let minLandingBuffer: CGFloat = 162
    let minLandingBufferForStay: CGFloat = 220
    let minCaveHeadroom: CGFloat
    let minCaveHeadroomForJumpObstacle: CGFloat = 168
    let minCaveHeadroomForAnyObstacle: CGFloat = 112
    let jumpObstacleCaveApproachBuffer: CGFloat = 72
    let maxDownhillBeforeJumpObstacle: CGFloat = 34
    let maxDownhillAfterStayObstacle: CGFloat = 24
    let maxDownhillBeforeDrone: CGFloat = 36
    let maxDownhillBeforeDroneInCave: CGFloat = 22
    let stayObstacleRunoutDistance: CGFloat = 154
    let minJumpClearance: CGFloat
    let clearanceSampleStep: CGFloat = 8
    let maxPrecipiceWidth: CGFloat = 136
    let precipiceAvoidanceBuffer: CGFloat = 80
    let obstacleSpacingBuffer: CGFloat = 28

    // [previousAction][nextAction] minimum pixel gaps.
    func minObstacleGap(inCave: Bool, from: ObstacleAction, to: ObstacleAction) -> CGFloat {
        if inCave {
            switch (from, to) {
            case (.jump, .jump): return 230
            case (.jump, .stay): return 168
            case (.stay, .jump): return 188
            case (.stay, .stay): return 140
            }
        } else {
            switch (from, to) {
            case (.jump, .jump): return 170
            case (.jump, .stay): return 132
            case (.stay, .jump): return 140
            case (.stay, .stay): return 116
            }
        }
    }

    init(playerHeight: CGFloat) {
        minCaveHeadroom = playerHeight + 14
        minJumpClearance = playerHeight + 138
    }
}

final class TerrainGenerator {
    let step: CGFloat = GameConstants.terrainStep
    private(set) var points: [TerrainPoint] = []
    private(set) var caves: [Cave] = []
    private(set) var precipices: [Precipice] = []

    private var lastX: CGFloat = 0
    private var currentY: CGFloat
    private var slope: CGFloat = 0
    private var nextPrecipiceAt: CGFloat = 420
    private var nextCaveAt: CGFloat = 360

    let baseGroundY: CGFloat
    let precipiceFloorY: CGFloat
    let safety: CourseSafety

    private let rng: RandomSource
    private let playerW: CGFloat

    init(sceneHeight: CGFloat, playerHeight: CGFloat, playerWidth: CGFloat, rng: RandomSource) {
        self.baseGroundY = sceneHeight - GameConstants.groundBaseInset
        self.precipiceFloorY = sceneHeight - 1
        self.currentY = baseGroundY
        self.safety = CourseSafety(playerHeight: playerHeight)
        self.rng = rng
        self.playerW = playerWidth
    }

    private func rand(_ min: CGFloat, _ max: CGFloat) -> CGFloat { rng.cgFloat(Double(min), Double(max)) }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.max(lo, Swift.min(hi, v)) }

    func isInPrecipice(_ worldX: CGFloat) -> Bool {
        precipices.contains { worldX >= $0.start && worldX <= $0.end }
    }

    func caveAt(_ worldX: CGFloat) -> Cave? {
        caves.first { worldX >= $0.start && worldX <= $0.end }
    }

    func caveCeiling(at worldX: CGFloat) -> CGFloat? {
        guard let cave = caveAt(worldX) else { return nil }
        let wave = sin(worldX * 0.04 + cave.phase) * cave.amplitude
        return cave.baseCeiling + wave
    }

    func precipiceNear(_ worldX: CGFloat, padding: CGFloat = 0) -> Precipice? {
        precipices.first { worldX >= $0.start - padding && worldX <= $0.end + padding }
    }

    private func requiredGroundForJumpClearance(_ worldX: CGFloat) -> CGFloat? {
        guard let ceiling = caveCeiling(at: worldX) else { return nil }
        return ceiling + safety.minJumpClearance
    }

    private func enforceJumpClearance(previous: TerrainPoint?, nextX: CGFloat, nextY: CGFloat) -> CGFloat {
        guard let prev = previous else { return nextY }
        var adjusted = nextY
        let width = nextX - prev.x
        guard width > 0 else { return adjusted }

        func enforce(at sampleX: CGFloat) {
            guard let requiredGroundY = requiredGroundForJumpClearance(sampleX) else { return }
            let t = (sampleX - prev.x) / width
            guard t > 0 else { return }
            let sampleGroundY = prev.y + (adjusted - prev.y) * t
            if sampleGroundY >= requiredGroundY { return }
            let requiredNextY = prev.y + (requiredGroundY - prev.y) / t
            adjusted = Swift.max(adjusted, requiredNextY)
        }

        var sampleX = prev.x + safety.clearanceSampleStep
        while sampleX < nextX {
            enforce(at: sampleX)
            sampleX += safety.clearanceSampleStep
        }
        enforce(at: nextX)
        return adjusted
    }

    private func segmentIndex(_ worldX: CGFloat) -> Int {
        guard points.count >= 2 else { return 0 }
        if worldX <= points[0].x { return 0 }
        var low = 0
        var high = points.count - 2
        while low <= high {
            let mid = (low + high) / 2
            if points[mid + 1].x < worldX { low = mid + 1 } else { high = mid - 1 }
        }
        return Int(clamp(CGFloat(low), 0, CGFloat(points.count - 2)))
    }

    func groundHeight(at worldX: CGFloat) -> CGFloat {
        if isInPrecipice(worldX) { return precipiceFloorY }
        guard points.count >= 2 else { return baseGroundY }
        let i = segmentIndex(worldX)
        let p1 = points[i]
        let p2 = points[Swift.min(i + 1, points.count - 1)]
        if p1.x == p2.x { return p1.y }
        let t = (worldX - p1.x) / (p2.x - p1.x)
        return p1.y + (p2.y - p1.y) * t
    }

    func ensureTerrainAhead(_ maxWorldX: CGFloat) {
        while lastX < maxWorldX {
            lastX += step

            if lastX > nextPrecipiceAt {
                let start = lastX + rand(40, 150)
                let width = rand(80, safety.maxPrecipiceWidth)
                precipices.append(Precipice(start: start, end: start + width))
                nextPrecipiceAt = start + rand(460, 780)
            }

            if lastX > nextCaveAt {
                let start = lastX + rand(60, 140)
                let length = rand(240, 430)
                let ceiling = rand(70, 140)
                caves.append(Cave(start: start, end: start + length,
                                  baseCeiling: ceiling, amplitude: rand(8, 18),
                                  phase: rand(0, CGFloat.pi * 2)))
                nextCaveAt = start + rand(520, 880)
            }

            slope += rand(-0.36, 0.36)
            slope = clamp(slope, -1.8, 1.8)
            currentY += slope * step * 0.25
            currentY += (baseGroundY - currentY) * 0.04
            currentY = clamp(currentY, baseGroundY - GameConstants.groundMaxRise, baseGroundY + GameConstants.groundMaxDrop)

            if rng.double() < 0.09 {
                currentY += rand(-26, 22)
                currentY = clamp(currentY, baseGroundY - GameConstants.groundMaxRise, baseGroundY + GameConstants.groundMaxDrop)
            }

            let previous = points.last
            currentY = enforceJumpClearance(previous: previous, nextX: lastX, nextY: currentY)
            currentY = clamp(currentY, baseGroundY - GameConstants.groundMaxRise, baseGroundY + GameConstants.groundMaxDrop)

            points.append(TerrainPoint(x: lastX, y: currentY))
        }
    }

    func initTerrain(screenWidth: CGFloat) {
        points.removeAll(); caves.removeAll(); precipices.removeAll()
        lastX = 0
        currentY = baseGroundY
        slope = 0
        nextPrecipiceAt = 420
        nextCaveAt = 360
        points.append(TerrainPoint(x: 0, y: baseGroundY))
        ensureTerrainAhead(screenWidth * 2)
    }

    /// Drops terrain data that has scrolled well behind the player.
    func prune(behindWorldX pruneX: CGFloat) {
        var pruneTo = 0
        while pruneTo + 1 < points.count && points[pruneTo + 1].x < pruneX { pruneTo += 1 }
        if pruneTo > 0 { points.removeFirst(pruneTo) }
        caves.removeAll { $0.end < pruneX }
        precipices.removeAll { $0.end < pruneX }
    }
}
