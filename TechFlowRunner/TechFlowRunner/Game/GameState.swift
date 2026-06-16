//
//  GameState.swift
//  Tech Flow Runner
//
//  Value types describing the run state machine, the immutable configuration
//  captured at run start, the live HUD snapshot published to SwiftUI, and the
//  result captured at run end.
//

import Foundation

enum RunState: Equatable {
    case menu
    case countdown
    case running
    case paused
    case gameOver
}

/// Captured the instant a run starts. Held for the whole run so menu changes
/// after death cannot re-categorize a finished score.
struct RunConfig: Equatable {
    var modifier: Modifier
    var skin: Skin
    var dailySeed: Bool
    var seedValue: UInt32?
    var seedDate: String
    var reducedMotion: Bool
}

/// Snapshot of values the SwiftUI HUD renders each frame.
struct HUDSnapshot: Equatable {
    var points: Int = 0
    var speed: Double = 1.0
    var best: Int = 0
    var bits: Int = 0
    var combo: Double = 1.0
    var level: Int = 1

    var shieldActive = false
    var overclockSeconds = 0
    var magnetSeconds = 0
    var slowmoSeconds = 0
}

/// Captured at run end and used to drive the game-over overlay and submission.
struct RunResult: Equatable {
    var points: Int = 0
    var bits: Int = 0
    var modifier: Modifier = .none
    var daily: Bool = false
    var seedDate: String = ""
    var isNewBest: Bool = false
    var submission: SubmissionState = .pending

    enum SubmissionState: Equatable {
        case pending
        case submitted
        case notSignedIn
        case localOnly
    }
}
