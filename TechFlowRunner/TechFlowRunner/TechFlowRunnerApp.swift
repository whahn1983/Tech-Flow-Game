//
//  TechFlowRunnerApp.swift
//  Tech Flow Runner
//
//  App entry point. Loads persistence, prepares audio, authenticates Game
//  Center, and shows the main menu. The single AppState/scene is shared across
//  the whole UI.
//

import SwiftUI
import UIKit

@main
struct TechFlowRunnerApp: App {
    // The app delegate reports the orientations currently allowed by
    // OrientationManager (menus: all-but-upside-down; gameplay: landscape).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear { app.onLaunch() }
                .onChange(of: scenePhase) { _, phase in
                    // Auto-pause when the app leaves the foreground mid-run.
                    if phase != .active && app.runState == .running {
                        app.pause()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color(UIColor(hex: 0x03060F)).ignoresSafeArea()
            switch app.runState {
            case .menu:
                MainMenuView()
                    .transition(.opacity)
            default:
                GameContainerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.runState)
    }
}
