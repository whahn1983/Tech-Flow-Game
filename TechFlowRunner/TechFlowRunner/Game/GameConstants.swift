//
//  GameConstants.swift
//  Tech Flow Runner
//
//  Central tuning values for the SpriteKit simulation. Values are expressed in
//  SpriteKit points and a y-up coordinate space (origin bottom-left), so the
//  signs of gravity/jump differ from the original web canvas reference, which
//  used a y-down space. They have been re-tuned to feel equivalent on device.
//

import CoreGraphics
import Foundation

enum GameConstants {
    // MARK: Reference design space.
    // The simulation is tuned against the iPhone 16 Pro logical (point) size:
    // 2622 × 1206 px at @3x == 874 × 402 pt. The SpriteKit scene is locked to
    // this size on every device and uniformly scaled (aspect-fit) so the
    // playable area — and therefore the difficulty — is identical regardless of
    // physical screen size. Larger screens simply zoom this same area in;
    // smaller screens zoom it out. See `GameSceneView`.
    static let designWidth: CGFloat = 874
    static let designHeight: CGFloat = 402
    static let designSize = CGSize(width: designWidth, height: designHeight)

    // MARK: Player physics (y-up: gravity is negative, jump impulse positive).
    static let gravity: CGFloat = -0.75
    static let jumpVelocity: CGFloat = 14.0
    static let featherFallGravityMult: CGFloat = 0.6

    static let playerStartX: CGFloat = 120
    static let playerWidth: CGFloat = 48
    static let playerHeight: CGFloat = 58
    static let duckHeight: CGFloat = 32

    // MARK: World scroll.
    static let baseSpeedStart: CGFloat = 4.2
    static let baseSpeedMax: CGFloat = 7.0
    static let baseSpeedPerLevel: CGFloat = 0.1
    static let speedMultMax: CGFloat = 5.0
    static let dashBoost: CGFloat = 4.0

    // MARK: Levels / scoring.
    static let levelInterval: CGFloat = 20000
    static let maxCombo: Double = 8.0
    static let comboFramesDuration: Int = 180          // ~3s at 60fps
    static let scoreGainBase: Double = 0.2
    static let bitScoreValue: Double = 8.0
    static let nearMissBonus: Double = 5.0

    // MARK: Input feel (frames at 60fps).
    static let coyoteFrames: Int = 6
    static let jumpBufferFrames: Int = 6
    static let duckMaxFrames: Int = 120
    static let dashFrames: Int = 18
    static let dashCooldownFrames: Int = 90
    static let wallRunFrames: Int = 30
    static let wallRunCooldownFrames: Int = 90

    // MARK: Power-up durations (frames).
    static let overclockFrames: Int = 5 * 60
    static let magnetFrames: Int = 7 * 60
    static let slowmoFrames: Int = 4 * 60
    static let bossOverclockFrames: Int = 4 * 60

    // MARK: Boss.
    static let bossSurvivalFrames: Int = 12 * 60
    static let bossWidth: CGFloat = 110
    static let bossHeight: CGFloat = 70

    // MARK: Factors.
    static let slowmoFactor: CGFloat = 0.55
    static let bossFactor: CGFloat = 0.5
    static let overclockScoreMult: Double = 2.0

    // MARK: Terrain layout (world-space, y-up). `groundBaseY` is computed from
    // the live scene height at runtime; these are the relative offsets used by
    // the generator so terrain reads the same regardless of device size.
    static let terrainStep: CGFloat = 34
    static let groundBaseInset: CGFloat = 72   // ground sits this far above the bottom edge
    static let groundMaxRise: CGFloat = 110     // terrain can climb this much above base
    static let groundMaxDrop: CGFloat = 44      // terrain can dip this much below base
}
