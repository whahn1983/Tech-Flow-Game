//
//  TechFlowGameScene.swift
//  Tech Flow Runner
//
//  Owns the full gameplay simulation and rendering. The simulation runs on a
//  fixed 60 Hz timestep in "design space" (y-down, like the original web
//  reference) and is flipped to SpriteKit's y-up space only when positioning
//  nodes — this keeps the port faithful and makes Daily Seed runs deterministic.
//
//  Core collisions are resolved with explicit AABB tests (rectangular hitbox)
//  rather than the physics solver, again for determinism; physics categories
//  are still wired on the player node to honor the SpriteKit physics model.
//

import SpriteKit
import UIKit

protocol TechFlowGameSceneDelegate: AnyObject {
    func sceneDidUpdateHUD(_ snapshot: HUDSnapshot)
    func sceneDidEndRun(points: Int, bits: Int, bossKills: Int)
}

final class TechFlowGameScene: SKScene {

    weak var gameDelegate: TechFlowGameSceneDelegate?

    // MARK: Run state
    private(set) var runState: RunState = .menu
    private var config = RunConfig(modifier: .none, skin: .pulse, dailySeed: false,
                                   seedValue: nil, seedDate: "", reducedMotion: false)
    private var best: Int = 0

    private var rng = RandomSource(seed: nil)
    private var terrain: TerrainGenerator!

    // MARK: Layers
    private let rootNode = SKNode()
    private let backgroundLayer = SKNode()
    private let worldLayer = SKNode()
    private let fxLayer = SKNode()
    private let groundShape = SKShapeNode()
    private let caveShape = SKShapeNode()
    private let bannerLabel = SKLabelNode()
    private var player: Player!

    // MARK: Simulation values (mirror the reference)
    private var score: Double = 0
    private var speedMult: Double = 1
    private var baseSpeed: CGFloat = GameConstants.baseSpeedStart
    private var gameOverFlag = false
    private var worldOffset: CGFloat = 0
    private var groundOffset: CGFloat = 0
    private var sceneryOffset: CGFloat = 0
    private var spawnTimer: Double = 0
    private var framesSinceLastSpawn: Int = Int.max

    private var bitsCollected = 0
    private var combo: Double = 1
    private var comboTimer = 0
    private var level = 1
    private var nextLevelAt: CGFloat = GameConstants.levelInterval
    private var lastBossLevel = 1
    private var bossKillsThisRun = 0

    private var lastSpawnAction: ObstacleAction?
    private var queuedSpawnAction: ObstacleAction?

    // Power-up timers (frames; shield is a 0/1 single-hit flag)
    private var pwrShield = 0
    private var pwrOverclock = 0
    private var pwrMagnet = 0
    private var pwrSlowmo = 0

    // Input-feel state
    private var coyoteFrames = 0
    private var jumpBufferFrames = 0
    // Guards the jump buffer so it can be armed at most once per landing.
    // Without this, hammering the jump button re-arms `jumpBufferFrames`
    // every press; each brief ground contact then auto-fires a buffered jump
    // (and refills the double jump), letting a rapid tapper climb/float
    // forever instead of falling back down. The latch clears only when the
    // player has genuinely settled back on the ground (see stepSimulation).
    private var jumpBufferLatched = false
    private var isDucking = false
    private var duckHeldFrames = 0
    private var duckLockedOut = false
    private var dashFrames = 0
    private var dashCooldown = 0
    private var wallRunFrames = 0
    private var wallRunCooldown = 0
    private var speedMultiplier: CGFloat = 1

    // FX / pacing
    private var bossSpawnsSuppressed = 0
    private var nearMissCooldown = 0
    private var shakeFrames = 0
    private var shakeIntensity: CGFloat = 0
    private var hitstopFrames = 0

    // Entities
    private var obstacles: [Obstacle] = []
    private var bits: [CollectibleBit] = []
    private var powerups: [PowerUp] = []
    private var projectiles: [Projectile] = []
    private var boss: Boss?

    // Fixed-step loop
    private var lastUpdateTime: TimeInterval = 0
    private var accumulator: Double = 0
    private let fixedStep: Double = 1.0 / 60.0

    private var reduceMotion: Bool { config.reducedMotion }
    private var modifier: Modifier { config.modifier }

    // MARK: - Scene setup

    private var sceneConfigured = false

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(hex: 0x03060F)
        // Fixed reference size + aspect-fit so the playable area is identical on
        // every device (see GameConstants.designSize / GameSceneView).
        size = GameConstants.designSize
        scaleMode = .aspectFit
        physicsWorld.gravity = .zero   // gameplay gravity is integrated manually

        // The scene instance is reused across presentations (it lives on
        // AppState), so build the node hierarchy only once.
        if !sceneConfigured {
            rootNode.addChild(backgroundLayer)
            groundShape.zPosition = 5
            caveShape.zPosition = 6
            rootNode.addChild(caveShape)
            rootNode.addChild(groundShape)
            rootNode.addChild(worldLayer)
            rootNode.addChild(fxLayer)
            addChild(rootNode)

            bannerLabel.fontName = "AvenirNext-Bold"
            bannerLabel.fontSize = 30
            bannerLabel.fontColor = UIColor(hex: 0xFFD95C)
            bannerLabel.horizontalAlignmentMode = .center
            bannerLabel.verticalAlignmentMode = .center
            bannerLabel.alpha = 0
            bannerLabel.zPosition = 100
            addChild(bannerLabel)
            sceneConfigured = true
        }

        buildBackground()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        bannerLabel.position = CGPoint(x: size.width / 2, y: size.height - 70)
        if size.width > 0 && size.height > 0 { buildBackground() }
    }

    // MARK: - Public control surface

    private var pendingSetup = false

    func configureRun(config: RunConfig, best: Int) {
        self.config = config
        self.best = best
        self.rng = RandomSource(seed: config.dailySeed ? config.seedValue : nil)
        // Build the run on the first frame where the scene has its real device
        // size — at this point the hosting SKView may not have laid out yet, so
        // building terrain now would use a placeholder size.
        pendingSetup = true
    }

    func startRun() {
        runState = .running
        lastUpdateTime = 0
        accumulator = 0
        isPaused = false
    }

    func pauseRun() {
        guard runState == .running else { return }
        runState = .paused
        isPaused = true
    }

    func resumeRun() {
        guard runState == .paused else { return }
        runState = .running
        isPaused = false
        lastUpdateTime = 0
    }

    // MARK: - Reset

    private func resetRun() {
        worldLayer.removeAllChildren()
        fxLayer.removeAllChildren()
        obstacles.removeAll(); bits.removeAll(); powerups.removeAll(); projectiles.removeAll()
        boss = nil

        score = 0; speedMult = 1; baseSpeed = GameConstants.baseSpeedStart
        gameOverFlag = false; worldOffset = 0; groundOffset = 0; sceneryOffset = 0
        spawnTimer = 0; framesSinceLastSpawn = Int.max
        bitsCollected = 0; combo = 1; comboTimer = 0; level = 1
        nextLevelAt = GameConstants.levelInterval; lastBossLevel = 1; bossKillsThisRun = 0
        lastSpawnAction = nil; queuedSpawnAction = nil
        pwrShield = modifier.startsWithShield ? 1 : 0
        pwrOverclock = 0; pwrMagnet = 0; pwrSlowmo = 0
        coyoteFrames = 0; jumpBufferFrames = 0; jumpBufferLatched = false
        isDucking = false; duckHeldFrames = 0
        duckLockedOut = false; dashFrames = 0; dashCooldown = 0; wallRunFrames = 0
        wallRunCooldown = 0; speedMultiplier = 1
        bossSpawnsSuppressed = 0; nearMissCooldown = 0; shakeFrames = 0
        shakeIntensity = 0; hitstopFrames = 0

        let h = max(size.height, 1)
        let w = max(size.width, 1)
        terrain = TerrainGenerator(sceneHeight: h, playerHeight: GameConstants.playerHeight,
                                   playerWidth: GameConstants.playerWidth, rng: rng)
        terrain.initTerrain(screenWidth: w)

        player?.container.removeFromParent()
        player = Player()
        player.rebuildSkin(config.skin)
        player.w = GameConstants.playerWidth
        player.h = GameConstants.playerHeight
        let spawnGround = terrain.groundHeight(at: player.x + player.w * 0.5)
        player.y = spawnGround - player.h
        player.vy = 0
        player.onGround = true
        player.jumpsLeft = modifier.noDoubleJump ? 1 : 2
        if player.container.parent == nil { rootNode.addChild(player.container) }

        // Physics category tag on the player (informational; collisions are AABB).
        let body = SKPhysicsBody(rectangleOf: CGSize(width: player.w, height: player.h))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        body.contactTestBitMask = PhysicsCategory.none
        player.container.physicsBody = body

        publishHUD()
        renderFrame()
    }

    // MARK: - Main loop

    override func update(_ currentTime: TimeInterval) {
        if pendingSetup {
            // The scene size is locked to the fixed landscape reference design
            // size, so the play area is always the same regardless of device or
            // physical orientation (a portrait device is paused/overlaid by
            // AppState). This guard is a defensive check that the size is valid.
            guard size.width > 1, size.height > 1, size.width > size.height else {
                lastUpdateTime = currentTime; return
            }
            resetRun()
            pendingSetup = false
            lastUpdateTime = currentTime
            return
        }
        guard runState == .running else { lastUpdateTime = currentTime; return }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        var delta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        if delta > 0.25 { delta = 0.25 }   // avoid spiral-of-death after a stall
        accumulator += delta

        var steps = 0
        while accumulator >= fixedStep && steps < 5 {
            stepSimulation()
            accumulator -= fixedStep
            steps += 1
            if runState != .running { break }
        }
        renderFrame()
    }

    // MARK: - Input

    func tapJump() { jump() }

    func beginDuck() {
        if duckLockedOut { return }
        isDucking = true
    }

    func endDuck() {
        isDucking = false
        duckHeldFrames = 0
        duckLockedOut = false
    }

    func dash() {
        guard runState == .running else { return }
        if dashCooldown > 0 || dashFrames > 0 { return }
        dashFrames = GameConstants.dashFrames
        dashCooldown = GameConstants.dashCooldownFrames
        AudioManager.shared.dash()
        spawnBurst(atDesignX: player.x, designTop: player.y + player.h / 2, count: 8, color: .white)
    }

    private func doJump() {
        player.vy = player.jumpPower
        player.onGround = false
        player.jumpsLeft -= 1
        coyoteFrames = 0
        if player.jumpsLeft >= 1 { AudioManager.shared.jump() } else { AudioManager.shared.doubleJump() }
        HapticsManager.shared.jump()
    }

    private func jump() {
        guard runState == .running else { return }
        let playerWorldCenter = worldOffset + player.x + player.w * 0.5
        if let cave = terrain.caveAt(playerWorldCenter), wallRunFrames == 0, wallRunCooldown == 0, !player.onGround {
            let ceilingWave = sin(playerWorldCenter * 0.04 + cave.phase) * cave.amplitude
            let ceilingY = cave.baseCeiling + ceilingWave
            if player.y < ceilingY + 60 && player.y > ceilingY {
                wallRunFrames = GameConstants.wallRunFrames
                wallRunCooldown = GameConstants.wallRunCooldownFrames
                player.vy = -2
                AudioManager.shared.dash()
                return
            }
        }
        if player.onGround || coyoteFrames > 0 {
            player.jumpsLeft = modifier.noDoubleJump ? 1 : 2
            doJump()
            return
        }
        if player.jumpsLeft > 0 && !modifier.noDoubleJump {
            doJump()
            return
        }
        // Out of jumps: buffer this press so a jump fires the instant we land.
        // Arm it at most once per landing — the latch (cleared only after the
        // player settles back on the ground) stops rapid re-presses from
        // continuously re-arming the buffer, which is what let a masher
        // auto-bounce and float instead of falling.
        if !jumpBufferLatched {
            jumpBufferFrames = GameConstants.jumpBufferFrames
            jumpBufferLatched = true
        }
    }

    // MARK: - Simulation step (ported reference update loop)

    private func stepSimulation() {
        if gameOverFlag { return }
        if hitstopFrames > 0 {
            hitstopFrames -= 1
            publishHUD()
            return
        }

        // Power-up + cooldown timers
        if pwrOverclock > 0 { pwrOverclock -= 1 }
        if pwrMagnet > 0 { pwrMagnet -= 1 }
        if pwrSlowmo > 0 { pwrSlowmo -= 1 }
        if dashFrames > 0 { dashFrames -= 1 }
        if dashCooldown > 0 { dashCooldown -= 1 }
        if wallRunFrames > 0 { wallRunFrames -= 1 }
        if wallRunCooldown > 0 { wallRunCooldown -= 1 }
        if nearMissCooldown > 0 { nearMissCooldown -= 1 }
        if bossSpawnsSuppressed > 0 { bossSpawnsSuppressed -= 1 }

        if comboTimer > 0 {
            comboTimer -= 1
            if comboTimer == 0 { combo = 1 }
        }

        // Score + speed ramp
        let overclockMult: Double = pwrOverclock > 0 ? GameConstants.overclockScoreMult : 1
        let scoreGain = GameConstants.scoreGainBase * speedMult * combo * overclockMult * modifier.scoreMult
        score += scoreGain
        speedMult = min(GameConstants.speedMultMax, 1 + sqrt(score) * 0.04)

        let slowFactor: CGFloat = pwrSlowmo > 0 ? GameConstants.slowmoFactor : 1
        let bossFactor: CGFloat = boss != nil ? GameConstants.bossFactor : 1
        speedMultiplier = CGFloat(overclockMult) * slowFactor * bossFactor
        let moveSpeed = baseSpeed * CGFloat(speedMult) * speedMultiplier
        let dashBoost: CGFloat = dashFrames > 0 ? GameConstants.dashBoost : 0
        worldOffset += moveSpeed + dashBoost
        groundOffset += moveSpeed
        sceneryOffset += baseSpeed * CGFloat(speedMult) * speedMultiplier * (reduceMotion ? 0.05 : 0.3)

        terrain.ensureTerrainAhead(worldOffset + size.width + 460)
        terrain.prune(behindWorldX: worldOffset - size.width * 3)

        // Gravity (design space: positive vy = falling/down).
        let gravityAccel = abs(GameConstants.gravity) * CGFloat(modifier.gravityMult)
        player.vy += gravityAccel
        if wallRunFrames > 0 { player.vy = min(player.vy, -1.5) }
        player.y += player.vy

        // Duck timer / hitbox
        if isDucking {
            duckHeldFrames += 1
            if duckHeldFrames >= GameConstants.duckMaxFrames {
                isDucking = false
                duckLockedOut = true
            }
        }
        let targetH: CGFloat = isDucking ? GameConstants.duckHeight : GameConstants.playerHeight
        if player.h != targetH {
            let groundDelta = targetH - player.h
            player.h = targetH
            if player.onGround { player.y -= groundDelta }
        }

        // Ground / precipice resolution
        let playerWorldCenter = worldOffset + player.x + player.w * 0.5
        let currentGround = terrain.groundHeight(at: playerWorldCenter)
        var nowOnGround = false
        if terrain.isInPrecipice(playerWorldCenter) {
            player.onGround = false
            if player.y + player.h >= currentGround {
                if !tryHandleHit() {
                    triggerGameOver()
                    return
                } else {
                    player.y = currentGround - player.h - 40
                }
            }
        } else if player.y >= currentGround - player.h {
            player.y = currentGround - player.h
            player.vy = 0
            player.onGround = true
            nowOnGround = true
            player.jumpsLeft = modifier.noDoubleJump ? 1 : 2
            coyoteFrames = GameConstants.coyoteFrames
        } else {
            player.onGround = false
            if coyoteFrames > 0 { coyoteFrames -= 1 }
        }

        // Cave ceiling
        if let cave = terrain.caveAt(playerWorldCenter) {
            let ceilingWave = sin(playerWorldCenter * 0.04 + cave.phase) * cave.amplitude
            let ceilingY = cave.baseCeiling + ceilingWave
            if player.y <= ceilingY {
                if wallRunFrames > 0 {
                    player.y = ceilingY + 2
                    player.vy = 0
                } else if !tryHandleHit() {
                    triggerGameOver()
                    return
                } else {
                    player.y = ceilingY + 8
                    player.vy = 6
                }
            }
        }

        // Jump buffer
        if jumpBufferFrames > 0 && (nowOnGround || coyoteFrames > 0) {
            doJump()
            jumpBufferFrames = 0
            // Keep the latch set: the player must settle on the ground again
            // (branch below) before another press can arm the buffer, so a
            // continuous mash can't chain buffered jumps into an endless float.
        } else if jumpBufferFrames > 0 {
            jumpBufferFrames -= 1
        } else if nowOnGround {
            // Settled on the ground with no buffered jump pending — re-enable
            // buffering for the next airborne sequence.
            jumpBufferLatched = false
        }

        if player.y > size.height + 80 {
            triggerGameOver()
            return
        }

        // Trail
        spawnTrail()

        // Obstacle spawning (suspended during boss)
        if boss == nil {
            if framesSinceLastSpawn != Int.max { framesSinceLastSpawn += 1 }
            spawnTimer -= 16.7
            if spawnTimer <= 0 {
                scheduleNextObstacle()
                if let last = obstacles.last { maybeSpawnBitsAround(last) }
                maybeSpawnPowerup()
            }
        }

        // Boss spawn (one per level)
        if boss == nil && level > lastBossLevel && bossSpawnsSuppressed == 0 {
            spawnBoss()
            lastBossLevel = level
        }
        bossUpdate()

        updateObstacles()
        updateBits()
        updatePowerups()
        updateProjectiles()

        if shakeFrames > 0 {
            shakeFrames -= 1
            if shakeFrames == 0 { shakeIntensity = 0 }
        }

        maybeLevelUp()
        publishHUD()
    }

    // MARK: - Hit handling / level / game over

    func tryHandleHit() -> Bool {
        if pwrShield > 0 {
            pwrShield = 0
            AudioManager.shared.shield()
            triggerShake(8, 18)
            hitstopFrames = 6
            player.vy = min(player.vy, -6)
            spawnBurst(atDesignX: player.x + player.w / 2, designTop: player.y + player.h / 2, count: 18, color: UIColor(hex: 0x2EF8FF))
            return true
        }
        return false
    }

    private func maybeLevelUp() {
        guard worldOffset >= nextLevelAt else { return }
        level += 1
        nextLevelAt += GameConstants.levelInterval
        baseSpeed = min(GameConstants.baseSpeedMax, baseSpeed + GameConstants.baseSpeedPerLevel)
        showBanner("LEVEL \(level)")
        AudioManager.shared.levelUp()
        announce("Level \(level)")
        triggerShake(3, 14)
    }

    func triggerGameOver() {
        gameOverFlag = true
        finalizeRun()
    }

    private func finalizeRun() {
        runState = .gameOver
        let points = Int(floor(score))
        AudioManager.shared.death()
        HapticsManager.shared.hit()
        triggerShake(10, 30)
        spawnBurst(atDesignX: player.x + player.w / 2, designTop: player.y + player.h / 2, count: 24, color: UIColor(hex: 0xFF5A7C))
        announce("Signal lost. \(points) points. \(bitsCollected) bits.")
        publishHUD()
        gameDelegate?.sceneDidEndRun(points: points, bits: bitsCollected, bossKills: bossKillsThisRun)
    }

    // MARK: - HUD / banner / a11y

    private func publishHUD() {
        var snap = HUDSnapshot()
        snap.points = Int(floor(score))
        snap.speed = speedMult
        snap.best = max(best, Int(floor(score)))
        snap.bits = bitsCollected
        snap.combo = combo
        snap.level = level
        snap.shieldActive = pwrShield > 0
        snap.overclockSeconds = pwrOverclock > 0 ? Int(ceil(Double(pwrOverclock) / 60)) : 0
        snap.magnetSeconds = pwrMagnet > 0 ? Int(ceil(Double(pwrMagnet) / 60)) : 0
        snap.slowmoSeconds = pwrSlowmo > 0 ? Int(ceil(Double(pwrSlowmo) / 60)) : 0
        gameDelegate?.sceneDidUpdateHUD(snap)
    }

    func showBanner(_ text: String) {
        bannerLabel.text = text
        bannerLabel.removeAllActions()
        bannerLabel.alpha = 1
        bannerLabel.run(.sequence([.wait(forDuration: 0.9), .fadeOut(withDuration: 0.6)]))
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func triggerShake(_ intensity: CGFloat, _ frames: Int) {
        if reduceMotion { return }
        shakeIntensity = max(shakeIntensity, intensity)
        shakeFrames = max(shakeFrames, frames)
    }
}

// MARK: - Obstacle scheduling
//
// Ported from the reference's fairness-aware scheduler: the player's reaction
// budget is measured in frames, placements are validated against terrain
// (caves, precipices, slopes) and neighbouring obstacles, and a "preview"
// action is queued so the next gap is pre-validated too.

extension TechFlowGameScene {

    private func transitionFrames(from: ObstacleAction?, to: ObstacleAction) -> Int {
        switch (from, to) {
        case (nil, .jump): return 24
        case (nil, .stay): return 20
        case (.some(.jump), .jump): return 22
        case (.some(.jump), .stay): return 44
        case (.some(.stay), .jump): return 26
        case (.some(.stay), .stay): return 18
        }
    }

    private func pickRandomAction() -> ObstacleAction {
        rng.double() < 0.24 ? .stay : .jump
    }

    private func minGapPx(from: ObstacleAction?, to: ObstacleAction) -> CGFloat {
        let moveSpeed = baseSpeed * CGFloat(speedMult)
        return CGFloat(transitionFrames(from: from, to: to)) * moveSpeed
    }

    private func canTransition(from: ObstacleAction?, to: ObstacleAction, gapPx: CGFloat) -> Bool {
        gapPx >= minGapPx(from: from, to: to)
    }

    private func spawnDelayMs(from: ObstacleAction?, to: ObstacleAction) -> Double {
        let moveSpeed = baseSpeed * CGFloat(speedMult)
        let baselineFrames = (23.0 + rng.double() * 35.0).rounded()
        let randomGapPx = CGFloat(baselineFrames) * moveSpeed
        let minGap = minGapPx(from: from, to: to)
        let maxGap = minGap + moveSpeed * CGFloat(16 + rng.double() * 18)
        let gapPx = max(minGap, min(randomGapPx, maxGap))
        return Double(gapPx / moveSpeed) * (1000.0 / 60.0)
    }

    private func applySpawnGap(_ gapPx: CGFloat, _ moveSpeed: CGFloat) {
        spawnTimer = Double(gapPx / moveSpeed) * (1000.0 / 60.0)
    }

    private func hasFrameBudget(from: ObstacleAction?, to: ObstacleAction) -> Bool {
        guard let from else { return true }
        return framesSinceLastSpawn >= transitionFrames(from: from, to: to)
    }

    private func createObstacle(action: ObstacleAction, worldX: CGFloat) -> Obstacle {
        var wx = worldX
        var groundY = terrain.groundHeight(at: wx)
        if terrain.isInPrecipice(wx) {
            if let p = terrain.precipices.first(where: { wx >= $0.start && wx <= $0.end }) {
                wx = p.end + 50
            } else {
                wx += 50
            }
            groundY = terrain.groundHeight(at: wx)
        }

        if action == .stay {
            return Obstacle(worldX: wx, y: groundY - 138, w: 72, h: 22, type: .drone, action: .stay)
        }
        let roll = rng.double()
        if roll < 0.34 {
            return Obstacle(worldX: wx, y: groundY - 20, w: 28, h: 20, type: .bug, action: .jump)
        }
        if roll < 0.67 {
            return Obstacle(worldX: wx, y: groundY - 52, w: 36, h: 52, type: .server, action: .jump)
        }
        return Obstacle(worldX: wx, y: groundY - 24, w: 62, h: 24, type: .laser, action: .jump)
    }

    private func hasNearbyObstacle(_ start: CGFloat, _ end: CGFloat, ignore: Obstacle?) -> Bool {
        let buffer = terrain.safety.obstacleSpacingBuffer
        return obstacles.contains { placed in
            if let ignore, placed === ignore { return false }
            let ps = placed.worldX - buffer
            let pe = placed.worldX + placed.w + buffer
            return start < pe && end > ps
        }
    }

    private func previousObstacle(before start: CGFloat) -> Obstacle? {
        var previous: Obstacle?
        for c in obstacles {
            let cEnd = c.worldX + c.w
            if cEnd <= start, previous == nil || cEnd > (previous!.worldX + previous!.w) {
                previous = c
            }
        }
        return previous
    }

    private func hasCaveInSpan(_ start: CGFloat, _ end: CGFloat) -> Bool {
        var x = start
        while x <= end {
            if terrain.caveCeiling(at: x) != nil { return true }
            x += terrain.safety.clearanceSampleStep
        }
        return terrain.caveCeiling(at: end) != nil
    }

    private func isPlacementWinnable(_ obstacle: Obstacle, action: ObstacleAction) -> Bool {
        let s = terrain.safety
        let obStart = obstacle.worldX
        let obEnd = obstacle.worldX + obstacle.w
        let obCenter = obStart + obstacle.w * 0.5
        let requiredLanding = action == .stay ? s.minLandingBufferForStay : s.minLandingBuffer
        let requiredTakeoff = action == .stay ? s.minTakeoffBufferForStay : s.minTakeoffBuffer

        if action == .jump {
            let approachStart = obStart - s.jumpObstacleCaveApproachBuffer
            if hasCaveInSpan(approachStart, obEnd) { return false }
            let uphillSampleX = obStart - player.w
            let downhill = terrain.groundHeight(at: obStart) - terrain.groundHeight(at: uphillSampleX)
            if downhill > s.maxDownhillBeforeJumpObstacle { return false }
        } else {
            let postGround = terrain.groundHeight(at: obEnd)
            var lowestRunout = postGround
            let runoutEnd = obEnd + s.stayObstacleRunoutDistance
            var x = obEnd + s.clearanceSampleStep
            while x <= runoutEnd {
                lowestRunout = max(lowestRunout, terrain.groundHeight(at: x))
                x += s.clearanceSampleStep
            }
            if lowestRunout - postGround > s.maxDownhillAfterStayObstacle { return false }

            let droneApproachStart = obStart - requiredTakeoff
            var peakApproachY = terrain.groundHeight(at: droneApproachStart)
            var sx = droneApproachStart + s.clearanceSampleStep
            while sx < obStart {
                peakApproachY = min(peakApproachY, terrain.groundHeight(at: sx))
                sx += s.clearanceSampleStep
            }
            let approachDrop = terrain.groundHeight(at: obStart) - peakApproachY
            let approachHasCave = hasCaveInSpan(droneApproachStart, obEnd)
            let maxApproachDrop = approachHasCave ? s.maxDownhillBeforeDroneInCave : s.maxDownhillBeforeDrone
            if approachDrop > maxApproachDrop { return false }
        }

        if hasNearbyObstacle(obStart, obEnd, ignore: obstacle) { return false }

        if let prev = previousObstacle(before: obStart) {
            let prevEnd = prev.worldX + prev.w
            let inCave = hasCaveInSpan(prevEnd, obStart + obstacle.w * 0.2)
            let requiredGap = s.minObstacleGap(inCave: inCave, from: prev.action, to: action)
            if obStart - prevEnd < requiredGap { return false }
        }

        if terrain.precipiceNear(obStart, padding: s.precipiceAvoidanceBuffer) != nil ||
            terrain.precipiceNear(obEnd, padding: s.precipiceAvoidanceBuffer) != nil {
            return false
        }

        let adjacentPrecipice = terrain.precipices.first { drop in
            (obStart >= drop.end && obStart - drop.end < requiredLanding) ||
            (obEnd <= drop.start && drop.start - obEnd < requiredTakeoff)
        }
        if adjacentPrecipice != nil { return false }

        let ceilingSampleStart = obStart - player.w
        let ceilingSampleEnd = obEnd + player.w
        var cx = ceilingSampleStart
        while cx <= ceilingSampleEnd {
            let groundY = terrain.groundHeight(at: cx)
            if let ceilingY = terrain.caveCeiling(at: cx) {
                let headroom = groundY - ceilingY
                if headroom < s.minCaveHeadroomForAnyObstacle { return false }
                if action == .jump && headroom < s.minCaveHeadroomForJumpObstacle { return false }
                if action == .jump && headroom - obstacle.h < player.h * 2.0 { return false }
                if hasNearbyObstacle(cx - 8, cx + 8, ignore: obstacle), headroom < s.minCaveHeadroom + 10 {
                    return false
                }
            }
            cx += s.clearanceSampleStep
        }

        let centerGround = terrain.groundHeight(at: obCenter)
        if let centerCeiling = terrain.caveCeiling(at: obCenter) {
            let centerHeadroom = centerGround - centerCeiling
            if centerHeadroom < s.minCaveHeadroom { return false }
            if action == .jump && centerHeadroom - obstacle.h < player.h * 2.0 { return false }
        }

        return true
    }

    func scheduleNextObstacle() {
        let moveSpeed = baseSpeed * CGFloat(speedMult)
        let spawnEdgeX = worldOffset + size.width + 20
        let preferred = queuedSpawnAction

        for attempt in 0..<24 {
            let nextAction = (attempt == 0 ? preferred : nil) ?? pickRandomAction()
            if !hasFrameBudget(from: lastSpawnAction, to: nextAction) { continue }

            let obstacle = createObstacle(action: nextAction, worldX: spawnEdgeX)
            if !isPlacementWinnable(obstacle, action: nextAction) { continue }

            let spawnShift = max(0, obstacle.worldX - spawnEdgeX)
            addObstacle(obstacle)
            lastSpawnAction = nextAction
            queuedSpawnAction = nil
            framesSinceLastSpawn = 0

            for _ in 0..<24 {
                let previewAction = pickRandomAction()
                let previewGapPx = CGFloat(spawnDelayMs(from: nextAction, to: previewAction)) * moveSpeed * (60.0 / 1000.0)
                if !canTransition(from: nextAction, to: previewAction, gapPx: previewGapPx) { continue }
                applySpawnGap(previewGapPx + spawnShift, moveSpeed)
                queuedSpawnAction = previewAction
                return
            }
            let fallbackGap = CGFloat(spawnDelayMs(from: nextAction, to: .jump)) * moveSpeed * (60.0 / 1000.0)
            applySpawnGap(fallbackGap + spawnShift, moveSpeed)
            queuedSpawnAction = .jump
            return
        }

        let fallbackAction = preferred ?? .jump
        let fallbackObstacle = createObstacle(action: fallbackAction, worldX: spawnEdgeX)
        if isPlacementWinnable(fallbackObstacle, action: fallbackAction) {
            let shift = max(0, fallbackObstacle.worldX - spawnEdgeX)
            addObstacle(fallbackObstacle)
            lastSpawnAction = fallbackAction
            framesSinceLastSpawn = 0
            applySpawnGap(CGFloat(spawnDelayMs(from: fallbackAction, to: .jump)) * moveSpeed * (60.0 / 1000.0) + shift, moveSpeed)
            queuedSpawnAction = .jump
            return
        }
        applySpawnGap(CGFloat(spawnDelayMs(from: fallbackAction, to: .jump)) * moveSpeed * (60.0 / 1000.0), moveSpeed)
        queuedSpawnAction = .jump
    }

    private func addObstacle(_ obstacle: Obstacle) {
        obstacles.append(obstacle)
        worldLayer.addChild(obstacle.node)
    }
}

// MARK: - Bits, power-ups, boss spawning

extension TechFlowGameScene {

    private func addBit(worldX: CGFloat, y: CGFloat) {
        let bit = CollectibleBit(worldX: worldX, y: y)
        bits.append(bit)
        worldLayer.addChild(bit.node)
    }

    func spawnBitArc(startWorldX: CGFloat) {
        let count = 5 + Int(rng.double() * 4)
        let ground = terrain.groundHeight(at: startWorldX)
        let peak = 80 + rng.cgFloat(0, 50)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            let x = startWorldX + CGFloat(i) * 30
            let arc = -peak * sin(t * .pi)
            addBit(worldX: x, y: ground + arc - 18)
        }
    }

    func spawnBitLine(startWorldX: CGFloat, atY: CGFloat) {
        let count = 4 + Int(rng.double() * 3)
        for i in 0..<count {
            addBit(worldX: startWorldX + CGFloat(i) * 26, y: atY)
        }
    }

    func maybeSpawnBitsAround(_ obstacle: Obstacle) {
        if rng.double() > 0.6 { return }
        spawnBitArc(startWorldX: obstacle.worldX - 60)
    }

    func maybeSpawnPowerup() {
        if rng.double() > 0.012 { return }
        var allowed = PowerUpKind.allCases
        if !modifier.allowShield { allowed.removeAll { $0 == .shield } }
        guard !allowed.isEmpty else { return }
        let idx = min(allowed.count - 1, Int(rng.double() * Double(allowed.count)))
        let kind = allowed[idx]
        let worldX = worldOffset + size.width + 40
        let ground = terrain.groundHeight(at: worldX)
        let powerup = PowerUp(worldX: worldX, baseY: ground - 70 - rng.cgFloat(0, 40),
                              kind: kind, bobPhase: rng.cgFloat(0, Double.pi * 2))
        powerups.append(powerup)
        worldLayer.addChild(powerup.node)
    }

    func activatePowerup(_ kind: PowerUpKind) {
        switch kind {
        case .shield: pwrShield = 1
        case .overclock: pwrOverclock = GameConstants.overclockFrames
        case .magnet: pwrMagnet = GameConstants.magnetFrames
        case .slowmo: pwrSlowmo = GameConstants.slowmoFrames
        }
        AudioManager.shared.powerUp()
        HapticsManager.shared.powerUp()
        announceA11y("\(kind) active")
        spawnBurst(atDesignX: player.x + player.w / 2, designTop: player.y + player.h / 2, count: 14, color: UIColor(hex: 0xFFD95C))
    }

    func spawnBoss() {
        guard boss == nil else { return }
        let baseGroundY = terrain.baseGroundY
        let yCenter = (40 + (baseGroundY - 70 - 30)) / 2
        let newBoss = Boss(worldX: worldOffset + size.width + 80, y: yCenter)
        boss = newBoss
        worldLayer.addChild(newBoss.node)
        bossSpawnsSuppressed = newBoss.timer + 60
        AudioManager.shared.bossIncoming()
        triggerShakePublic(6, 30)
        announceA11y("Mainframe boss incoming")
        showBannerPublic("⚠ MAINFRAME BOSS ⚠")
    }

    private func bossDefeated() {
        guard let b = boss else { return }
        AudioManager.shared.bossDefeated()
        HapticsManager.shared.bossDefeated()
        triggerShakePublic(10, 40)
        spawnBurst(atDesignX: b.worldX - worldOffset + b.w / 2, designTop: b.y + b.h / 2, count: 36, color: UIColor(hex: 0xFFD95C))
        let bx = b.worldX - 200
        let by = b.y + b.h + 20
        spawnBitLine(startWorldX: bx, atY: by)
        spawnBitLine(startWorldX: bx + 30, atY: by + 20)
        pwrOverclock = max(pwrOverclock, GameConstants.bossOverclockFrames)
        bossKillsThisRun += 1
        b.node.removeFromParent()
        boss = nil
    }

    func bossUpdate() {
        guard let b = boss else { return }
        let targetWorldX = worldOffset + size.width - b.w - 8
        b.worldX += (targetWorldX - b.worldX) * 0.04
        let baseGroundY = terrain.baseGroundY
        let yMin: CGFloat = 18
        let yMax = baseGroundY - b.h
        let yCenter = (yMin + yMax) / 2
        let yAmp = (yMax - yMin) / 2
        b.phase += 0.025
        b.y = yCenter + sin(b.phase) * yAmp
        b.timer -= 1
        b.cooldown -= 1
        if b.cooldown <= 0 {
            let baseY = b.y + b.h - 8
            let baseX = b.worldX + 12
            for i in 0..<3 {
                let p = Projectile(worldX: baseX, y: baseY + CGFloat(i) * 14,
                                   vx: -7 - CGFloat(speedMult) * 0.6, life: 240)
                projectiles.append(p)
                worldLayer.addChild(p.node)
            }
            AudioManager.shared.laser()
            b.cooldown = 70 - min(40, level * 4)
            b.pattern += 1
        }
        if b.timer <= 0 { bossDefeated() }
    }

    // Bridges so this extension can reach the private helpers above.
    private func announceA11y(_ s: String) { UIAccessibility.post(notification: .announcement, argument: s) }
    private func triggerShakePublic(_ i: CGFloat, _ f: Int) { triggerShakeBridge(i, f) }
    private func showBannerPublic(_ t: String) { showBannerBridge(t) }
}

// MARK: - Entity updates / collisions

extension TechFlowGameScene {

    func updateObstacles() {
        for i in stride(from: obstacles.count - 1, through: 0, by: -1) {
            let ob = obstacles[i]
            let screenX = ob.worldX - worldOffset
            let hit = player.x < screenX + ob.w &&
                player.x + player.w > screenX &&
                player.y < ob.y + ob.h &&
                player.y + player.h > ob.y
            if hit {
                if !tryHandleHitBridge() {
                    ob.node.removeFromParent()
                    obstacles.remove(at: i)
                    triggerGameOverBridge()
                    return
                }
                ob.node.removeFromParent()
                obstacles.remove(at: i)
                continue
            }
            // Near-miss bonus
            if screenX + ob.w < player.x && screenX + ob.w > player.x - 6 && nearMissCooldown == 0 {
                let verticalGap = min(abs(ob.y + ob.h - player.y), abs(ob.y - (player.y + player.h)))
                if verticalGap > 0 && verticalGap < 14 {
                    nearMissCooldown = 30
                    combo = min(GameConstants.maxCombo, combo + 0.2)
                    comboTimer = GameConstants.comboFramesDuration
                    score += GameConstants.nearMissBonus
                    spawnBurst(atDesignX: player.x + player.w, designTop: player.y + player.h * 0.3, count: 6, color: UIColor(hex: 0xFFD95C))
                    AudioManager.shared.combo()
                }
            }
            if screenX + ob.w < -20 {
                ob.node.removeFromParent()
                obstacles.remove(at: i)
            }
        }
    }

    func updateBits() {
        let magnetActive = pwrMagnet > 0
        for i in stride(from: bits.count - 1, through: 0, by: -1) {
            let bit = bits[i]
            if magnetActive {
                let playerWorldX = worldOffset + player.x + player.w / 2
                let dx = playerWorldX - bit.worldX
                let dy = (player.y + player.h / 2) - bit.y
                let dist2 = dx * dx + dy * dy
                if dist2 < 230 * 230 {
                    let d = sqrt(dist2)
                    if d > 0 {
                        bit.worldX += (dx / d) * 5
                        bit.y += (dy / d) * 5
                    }
                }
            }
            let screenX = bit.worldX - worldOffset
            let collide = player.x < screenX + bit.w &&
                player.x + player.w > screenX &&
                player.y < bit.y + bit.h &&
                player.y + player.h > bit.y
            if collide {
                bit.node.removeFromParent()
                bits.remove(at: i)
                let value = bit.value * modifier.bitsMult
                bitsCollected += value
                combo = min(GameConstants.maxCombo, combo + 0.1 * Double(value))
                comboTimer = GameConstants.comboFramesDuration
                score += GameConstants.bitScoreValue * Double(value)
                spawnBurst(atDesignX: screenX + 4, designTop: bit.y + 4, count: 5, color: UIColor(hex: 0xFFD95C))
                AudioManager.shared.bit()
                HapticsManager.shared.collect()
                continue
            }
            if screenX + bit.w < -20 {
                bit.node.removeFromParent()
                bits.remove(at: i)
            }
        }
    }

    func updatePowerups() {
        for i in stride(from: powerups.count - 1, through: 0, by: -1) {
            let it = powerups[i]
            it.bob += 0.1
            let screenX = it.worldX - worldOffset
            let drawY = it.baseY + sin(it.bob) * 4
            let collide = player.x < screenX + it.w &&
                player.x + player.w > screenX &&
                player.y < drawY + it.h &&
                player.y + player.h > drawY
            if collide {
                activatePowerupBridge(it.kind)
                it.node.removeFromParent()
                powerups.remove(at: i)
                continue
            }
            if screenX + it.w < -20 {
                it.node.removeFromParent()
                powerups.remove(at: i)
            }
        }
    }

    func updateProjectiles() {
        for i in stride(from: projectiles.count - 1, through: 0, by: -1) {
            let p = projectiles[i]
            p.worldX += p.vx
            p.life -= 1
            let screenX = p.worldX - worldOffset
            let collide = player.x < screenX + p.w &&
                player.x + player.w > screenX &&
                player.y < p.y + p.h &&
                player.y + player.h > p.y
            if collide {
                p.node.removeFromParent()
                projectiles.remove(at: i)
                if !tryHandleHitBridge() {
                    triggerGameOverBridge()
                    return
                }
                continue
            }
            if screenX < -40 || p.life <= 0 {
                p.node.removeFromParent()
                projectiles.remove(at: i)
            }
        }
    }

    func spawnTrail() {
        guard !reduceMotion else { return }
        let colors = player == nil ? [UIColor.cyan] : config.skin.colors
        let color = Bool.random() ? colors[0] : colors[1]
        let screenX = player.x + 4
        let designTop = player.y + player.h * 0.55
        ParticleEffect.trail(in: fxLayer, at: CGPoint(x: screenX, y: size.height - designTop), color: color, reducedMotion: reduceMotion)
    }

    /// Spawns a burst. `screenX` is already in screen space; `designTop` is a
    /// design-space (y-down) coordinate that is flipped to scene y-up here.
    func spawnBurst(atDesignX screenX: CGFloat, designTop: CGFloat, count: Int, color: UIColor) {
        ParticleEffect.burst(in: fxLayer, at: CGPoint(x: screenX, y: size.height - designTop),
                             count: count, color: color, reducedMotion: reduceMotion)
    }

    // Bridges to private members so the extension can call them.
    private func tryHandleHitBridge() -> Bool { tryHandleHitInternal() }
    private func triggerGameOverBridge() { triggerGameOverInternal() }
    private func activatePowerupBridge(_ k: PowerUpKind) { activatePowerupInternal(k) }
}

// MARK: - Rendering

extension TechFlowGameScene {

    func buildBackground() {
        backgroundLayer.removeAllChildren()
        let w = max(size.width, 320)
        let h = max(size.height, 240)
        let baseGroundY = h - GameConstants.groundBaseInset

        // Parallax neon skyline. Built across an extra 510pt (3 building tiles)
        // so the layer can wrap seamlessly by that period.
        var x: CGFloat = 0
        var i = 0
        while x < w + 600 {
            let bWidth: CGFloat = 130
            let bHeight = 110 + CGFloat(i % 3) * 30
            let building = SKShapeNode(rect: CGRect(x: x, y: baseGroundY - bHeight, width: bWidth, height: bHeight))
            building.fillColor = UIColor(hex: 0x8E5CFF).withAlphaComponent(0.22)
            building.strokeColor = .clear
            building.zPosition = 1
            backgroundLayer.addChild(building)
            // Lit windows
            var wy = baseGroundY - bHeight + 14
            while wy < baseGroundY - 12 {
                var wx = x + 12
                while wx < x + bWidth - 12 {
                    let win = SKShapeNode(rect: CGRect(x: wx, y: wy, width: 8, height: 9))
                    win.fillColor = UIColor(hex: 0x2EF8FF).withAlphaComponent(0.55)
                    win.strokeColor = .clear
                    win.zPosition = 1
                    backgroundLayer.addChild(win)
                    wx += 22
                }
                wy += 20
            }
            x += 170
            i += 1
        }
        // Stars
        for s in 0..<60 {
            let sx = CGFloat((s * 41 + 17) % Int(w + 200))
            let sy = baseGroundY + 40 + CGFloat((s * 29 + 23) % Int(max(60, h - baseGroundY - 40)))
            let star = SKShapeNode(rect: CGRect(x: sx, y: sy, width: 2, height: 2))
            star.fillColor = UIColor.white.withAlphaComponent(0.7)
            star.strokeColor = .clear
            star.zPosition = 0
            backgroundLayer.addChild(star)
        }
    }

    func renderFrame() {
        guard terrain != nil, player != nil else { return }
        let h = size.height

        // Parallax wrap (period 510 keeps the i%3 height pattern aligned).
        backgroundLayer.position = CGPoint(x: -(sceneryOffset.truncatingRemainder(dividingBy: 510)), y: 0)

        renderTerrain()

        // Player
        player.syncVisualHeightIfNeeded()
        player.container.position = CGPoint(x: player.x, y: h - (player.y + player.h))
        player.setShield(pwrShield > 0)
        player.setOverclock(pwrOverclock > 0)
        player.setDashing(dashFrames > 0)

        for ob in obstacles {
            ob.node.position = CGPoint(x: ob.worldX - worldOffset, y: h - (ob.y + ob.h))
        }
        for bit in bits {
            bit.node.position = CGPoint(x: bit.worldX - worldOffset, y: h - (bit.y + bit.h))
        }
        for it in powerups {
            let drawY = it.baseY + sin(it.bob) * 4
            it.node.position = CGPoint(x: it.worldX - worldOffset, y: h - (drawY + it.h))
        }
        for p in projectiles {
            p.node.position = CGPoint(x: p.worldX - worldOffset, y: h - (p.y + p.h))
        }
        if let b = boss {
            b.node.position = CGPoint(x: b.worldX - worldOffset, y: h - (b.y + b.h))
            b.updateBar()
        }

        // Screen shake
        if shakeFrames > 0 && shakeIntensity > 0 && !reduceMotion {
            let dx = CGFloat.random(in: -1...1) * shakeIntensity
            let dy = CGFloat.random(in: -1...1) * shakeIntensity
            rootNode.position = CGPoint(x: dx, y: dy)
        } else {
            rootNode.position = .zero
        }
    }

    private func renderTerrain() {
        let h = size.height
        let w = size.width
        let renderWorldOffset = floor(worldOffset)
        terrain.ensureTerrainAhead(renderWorldOffset + w + terrain.step * 2 + 300)

        // Ground silhouette (filled from bottom up to the surface).
        let groundPath = CGMutablePath()
        groundPath.move(to: CGPoint(x: -terrain.step, y: 0))
        var sx = -terrain.step
        let sampleStep: CGFloat = 6
        while sx <= w + terrain.step {
            let worldX = renderWorldOffset + sx
            let surfaceSceneY = h - terrain.groundHeight(at: worldX)
            groundPath.addLine(to: CGPoint(x: sx, y: surfaceSceneY))
            sx += sampleStep
        }
        groundPath.addLine(to: CGPoint(x: w + terrain.step, y: 0))
        groundPath.closeSubpath()
        groundShape.path = groundPath
        groundShape.fillColor = UIColor(hex: 0x16233F)
        groundShape.strokeColor = UIColor(hex: 0x2EF8FF).withAlphaComponent(0.5)
        groundShape.lineWidth = 2
        groundShape.glowWidth = 1

        // Cave ceilings (filled from the top down to the ceiling curve).
        let cavePath = CGMutablePath()
        for cave in terrain.caves {
            if cave.end < worldOffset - 40 || cave.start > worldOffset + w + 40 { continue }
            let startX = cave.start - renderWorldOffset
            let endX = cave.end - renderWorldOffset
            cavePath.move(to: CGPoint(x: startX, y: h))
            cavePath.addLine(to: CGPoint(x: startX, y: h - cave.baseCeiling))
            var worldX = cave.start
            while worldX <= cave.end {
                let sxx = worldX - renderWorldOffset
                let wave = sin(worldX * 0.04 + cave.phase) * cave.amplitude
                cavePath.addLine(to: CGPoint(x: sxx, y: h - (cave.baseCeiling + wave)))
                worldX += 16
            }
            let endWave = sin(cave.end * 0.04 + cave.phase) * cave.amplitude
            cavePath.addLine(to: CGPoint(x: endX, y: h - (cave.baseCeiling + endWave)))
            cavePath.addLine(to: CGPoint(x: endX, y: h))
            cavePath.closeSubpath()
        }
        caveShape.path = cavePath
        caveShape.fillColor = UIColor(hex: 0x101A30)
        caveShape.strokeColor = UIColor(hex: 0xFF5CD1).withAlphaComponent(0.35)
        caveShape.lineWidth = 1.5
    }
}

// MARK: - Private bridges used by extensions in this file
//
// These thin wrappers expose a handful of `private` members to the extensions
// above (Swift `private` is file-scoped, so same-file extensions can call them
// through these intentionally simple shims).

extension TechFlowGameScene {
    func tryHandleHitInternal() -> Bool { tryHandleHit() }
    func triggerGameOverInternal() { triggerGameOver() }
    func activatePowerupInternal(_ kind: PowerUpKind) { activatePowerup(kind) }
    func triggerShakeBridge(_ i: CGFloat, _ f: Int) { triggerShake(i, f) }
    func showBannerBridge(_ t: String) { showBanner(t) }
}

