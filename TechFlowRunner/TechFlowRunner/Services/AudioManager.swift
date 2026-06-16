//
//  AudioManager.swift
//  Tech Flow Runner
//
//  Owns looping background music (the bundled "Tech Flow.mp3") and a small set
//  of procedurally synthesized sound effects, mirroring the original game's
//  WebAudio tones. All audio respects a single `muted` flag persisted locally.
//
//  Music does not start until the player interacts (tapping Start or the music
//  toggle), satisfying iOS autoplay expectations.
//

import AVFoundation

final class AudioManager {
    static let shared = AudioManager()

    private(set) var muted: Bool = PersistenceManager.shared.muted

    private var musicPlayer: AVAudioPlayer?
    private let engine = AVAudioEngine()
    private let toneNode = AVAudioPlayerNode()
    private var engineConfigured = false
    private let sampleRate: Double = 44_100

    private init() {}

    // MARK: Session

    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .ambient respects the hardware mute switch and mixes politely with
        // other audio; appropriate for a casual game with an optional score.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func prepareMusic() {
        guard musicPlayer == nil else { return }
        guard let url = Self.musicURL() else {
            #if DEBUG
            print("AudioManager: Tech Flow.mp3 not found in bundle.")
            #endif
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // loop forever
            player.volume = 0.55
            player.prepareToPlay()
            musicPlayer = player
        } catch {
            #if DEBUG
            print("AudioManager: failed to load music: \(error)")
            #endif
        }
    }

    private static func musicURL() -> URL? {
        // The asset is bundled with a space in its name to preserve the
        // original filename ownership requirement.
        if let url = Bundle.main.url(forResource: "Tech Flow", withExtension: "mp3") {
            return url
        }
        return Bundle.main.url(forResource: "TechFlow", withExtension: "mp3")
    }

    // MARK: Music control

    func startMusic() {
        guard !muted else { return }
        prepareMusic()
        configureSession()
        if let player = musicPlayer, !player.isPlaying {
            player.play()
        }
    }

    func pauseMusic() {
        musicPlayer?.pause()
    }

    func stopMusic() {
        musicPlayer?.stop()
        musicPlayer?.currentTime = 0
    }

    @discardableResult
    func toggleMute() -> Bool {
        setMuted(!muted)
        return muted
    }

    func setMuted(_ value: Bool) {
        muted = value
        PersistenceManager.shared.muted = value
        if muted {
            pauseMusic()
        } else {
            startMusic()
        }
    }

    // MARK: SFX synthesis

    private enum Wave { case sine, square, triangle, sawtooth }

    private func ensureEngine() {
        guard !engineConfigured else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(toneNode)
        engine.connect(toneNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            toneNode.play()
            engineConfigured = true
        } catch {
            #if DEBUG
            print("AudioManager: engine start failed: \(error)")
            #endif
        }
    }

    // `delay` adds a short lead of silence so chained calls read as a quick
    // arpeggio rather than stacking. Buffers queue on the player node in call
    // order, which is sufficient for these brief UI tones.
    private func tone(_ frequency: Double, _ duration: Double, _ wave: Wave, gain: Double, delay: Double = 0) {
        guard !muted else { return }
        ensureEngine()
        guard engineConfigured else { return }

        let totalDuration = duration + delay
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let delayFrames = Int(delay * sampleRate)
        for frame in 0..<Int(frameCount) {
            if frame < delayFrames {
                channel[frame] = 0
                continue
            }
            let t = Double(frame - delayFrames) / sampleRate
            let phase = (frequency * t).truncatingRemainder(dividingBy: 1.0)
            var sample: Double
            switch wave {
            case .sine:
                sample = sin(twoPi * frequency * t)
            case .square:
                sample = phase < 0.5 ? 1.0 : -1.0
            case .triangle:
                sample = 4.0 * abs(phase - 0.5) - 1.0
            case .sawtooth:
                sample = 2.0 * phase - 1.0
            }
            // Exponential decay envelope, matching the WebAudio reference feel.
            let env = exp(-3.0 * t / max(duration, 0.0001))
            channel[frame] = Float(sample * gain * env)
        }

        toneNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: SFX vocabulary (mirrors the web build)

    func jump() { tone(620, 0.09, .square, gain: 0.5) }
    func doubleJump() { tone(820, 0.09, .square, gain: 0.5) }
    func bit() { tone(1100, 0.05, .sine, gain: 0.4) }
    func combo() { tone(1500, 0.07, .triangle, gain: 0.5) }
    func dash() { tone(560, 0.08, .sawtooth, gain: 0.5) }
    func laser() { tone(220, 0.12, .sawtooth, gain: 0.4) }

    func powerUp() {
        tone(660, 0.07, .square, gain: 0.45)
        tone(990, 0.09, .square, gain: 0.45, delay: 0.07)
    }

    func shield() {
        tone(440, 0.18, .square, gain: 0.55)
        tone(880, 0.18, .square, gain: 0.55, delay: 0.08)
    }

    func levelUp() {
        tone(520, 0.1, .square, gain: 0.55)
        tone(780, 0.12, .square, gain: 0.55, delay: 0.09)
        tone(1040, 0.14, .square, gain: 0.55, delay: 0.2)
    }

    func bossIncoming() {
        tone(110, 0.4, .sawtooth, gain: 0.6)
        tone(75, 0.5, .sawtooth, gain: 0.55, delay: 0.2)
    }

    func bossDefeated() {
        tone(880, 0.18, .square, gain: 0.6)
        tone(1320, 0.2, .square, gain: 0.6, delay: 0.1)
        tone(1760, 0.25, .square, gain: 0.6, delay: 0.22)
    }

    func death() {
        tone(180, 0.4, .sawtooth, gain: 0.7)
        tone(90, 0.5, .sawtooth, gain: 0.55, delay: 0.09)
    }
}
